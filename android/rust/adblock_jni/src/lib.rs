use adblock::lists::{FilterFormat, FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::Engine;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jstring, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;
use serde_json::Value;
use std::collections::HashSet;
use std::panic;
use std::ptr;
use std::sync::{Mutex, OnceLock};

fn engine_slot() -> &'static Mutex<Option<Engine>> {
    static ENGINE: OnceLock<Mutex<Option<Engine>>> = OnceLock::new();
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn to_bool(value: bool) -> jboolean {
    if value {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

fn with_engine<R>(f: impl FnOnce(&Engine) -> R) -> Option<R> {
    let guard = engine_slot().lock().ok()?;
    let engine = guard.as_ref()?;
    Some(f(engine))
}

fn parse_resources(resources_json: &str) -> Vec<Resource> {
    if resources_json.trim().is_empty() {
        return Vec::new();
    }
    serde_json::from_str::<Vec<Resource>>(resources_json).unwrap_or_default()
}

fn parse_tags(enabled_tags_json: &str) -> Vec<String> {
    if enabled_tags_json.trim().is_empty() {
        return Vec::new();
    }
    serde_json::from_str::<Vec<String>>(enabled_tags_json).unwrap_or_default()
}

#[derive(Debug, Clone)]
struct CatalogSourceSpec {
    text: String,
    format: FilterFormat,
    permission_mask: PermissionMask,
}

fn parse_catalog_sources(catalog_sources_json: &str) -> Vec<CatalogSourceSpec> {
    if catalog_sources_json.trim().is_empty() {
        return Vec::new();
    }
    let parsed = serde_json::from_str::<Value>(catalog_sources_json).ok();
    let Some(Value::Array(entries)) = parsed else {
        return Vec::new();
    };

    let mut output = Vec::new();
    for entry in entries {
        let Value::Object(map) = entry else {
            continue;
        };
        let text = map
            .get("text")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        if text.trim().is_empty() {
            continue;
        }
        let format = map
            .get("format")
            .and_then(Value::as_str)
            .map(parse_filter_format)
            .unwrap_or(FilterFormat::Standard);
        let permission_mask = map
            .get("permission_mask")
            .and_then(Value::as_u64)
            .map(|value| PermissionMask::from_bits((value & 0xFF) as u8))
            .unwrap_or_else(PermissionMask::default);
        output.push(CatalogSourceSpec {
            text,
            format,
            permission_mask,
        });
    }

    output
}

fn parse_filter_format(raw: &str) -> FilterFormat {
    let normalized = raw.trim().to_ascii_lowercase();
    if normalized == "hosts" {
        FilterFormat::Hosts
    } else {
        FilterFormat::Standard
    }
}

fn parse_json_string_list(raw: &str) -> Vec<String> {
    if raw.trim().is_empty() {
        return Vec::new();
    }
    serde_json::from_str::<Vec<String>>(raw).unwrap_or_default()
}

fn decode_engine_snapshot(serialized_engine_b64: &str) -> Option<Vec<u8>> {
    let trimmed = serialized_engine_b64.trim();
    if trimmed.is_empty() {
        return None;
    }
    BASE64_STANDARD.decode(trimmed).ok()
}

fn load_engine_with_assets(
    filter_text: &str,
    resources_json: &str,
    enabled_tags_json: &str,
    catalog_sources_json: &str,
    serialized_engine_b64: &str,
) -> bool {
    let mut engine = if let Some(serialized) = decode_engine_snapshot(serialized_engine_b64) {
        let mut cached_engine = Engine::default();
        if cached_engine.deserialize(&serialized).is_ok() {
            cached_engine
        } else {
            let mut filter_set = FilterSet::new(false);
            let catalog_sources = parse_catalog_sources(catalog_sources_json);
            if catalog_sources.is_empty() {
                filter_set.add_filter_list(filter_text, ParseOptions::default());
            } else {
                for source in catalog_sources {
                    filter_set.add_filter_list(
                        &source.text,
                        ParseOptions {
                            format: source.format,
                            permissions: source.permission_mask,
                            ..ParseOptions::default()
                        },
                    );
                }
            }
            Engine::from_filter_set(filter_set, true)
        }
    } else {
        let mut filter_set = FilterSet::new(false);
        let catalog_sources = parse_catalog_sources(catalog_sources_json);
        if catalog_sources.is_empty() {
            filter_set.add_filter_list(filter_text, ParseOptions::default());
        } else {
            for source in catalog_sources {
                filter_set.add_filter_list(
                    &source.text,
                    ParseOptions {
                        format: source.format,
                        permissions: source.permission_mask,
                        ..ParseOptions::default()
                    },
                );
            }
        }
        Engine::from_filter_set(filter_set, true)
    };

    let resources = parse_resources(resources_json);
    if !resources.is_empty() {
        engine.use_resources(resources);
    }

    let tags = parse_tags(enabled_tags_json);
    if !tags.is_empty() {
        let refs: Vec<&str> = tags.iter().map(String::as_str).collect();
        engine.use_tags(&refs);
    }

    if let Ok(mut guard) = engine_slot().lock() {
        *guard = Some(engine);
        true
    } else {
        false
    }
}

fn should_block(url: &str, source_url: &str, resource_type: &str) -> bool {
    let fallback_source = if source_url.trim().is_empty() {
        url
    } else {
        source_url
    };

    let request = match Request::new(url, fallback_source, resource_type) {
        Ok(request) => request,
        Err(_) => return false,
    };

    with_engine(|engine| engine.check_network_request(&request).matched).unwrap_or(false)
}

fn evaluate_request(url: &str, source_url: &str, resource_type: &str) -> String {
    let fallback_source = if source_url.trim().is_empty() {
        url
    } else {
        source_url
    };

    let request = match Request::new(url, fallback_source, resource_type) {
        Ok(request) => request,
        Err(_) => return "{\"matched\":false}".to_string(),
    };

    with_engine(|engine| engine.check_network_request(&request))
        .and_then(|result| serde_json::to_string(&result).ok())
        .unwrap_or_else(|| "{\"matched\":false}".to_string())
}

fn get_cosmetic_resources(url: &str) -> String {
    with_engine(|engine| engine.url_cosmetic_resources(url))
        .and_then(|resources| serde_json::to_string(&resources).ok())
        .unwrap_or_else(|| "{}".to_string())
}

fn get_hidden_class_id_selectors(
    _page_url: &str,
    classes_json: &str,
    ids_json: &str,
    exceptions_json: &str,
) -> String {
    let classes = parse_json_string_list(classes_json);
    let ids = parse_json_string_list(ids_json);
    let exceptions = parse_json_string_list(exceptions_json)
        .into_iter()
        .map(|entry| entry.trim().to_string())
        .filter(|entry| !entry.is_empty())
        .collect::<HashSet<String>>();

    with_engine(|engine| {
        engine.hidden_class_id_selectors(
            classes.iter().map(String::as_str),
            ids.iter().map(String::as_str),
            &exceptions,
        )
    })
    .and_then(|selectors| serde_json::to_string(&selectors).ok())
    .unwrap_or_else(|| "[]".to_string())
}

fn get_csp_directives(url: &str, source_url: &str, resource_type: &str) -> String {
    let fallback_source = if source_url.trim().is_empty() {
        url
    } else {
        source_url
    };

    let request = match Request::new(url, fallback_source, resource_type) {
        Ok(request) => request,
        Err(_) => return String::new(),
    };

    with_engine(|engine| engine.get_csp_directives(&request))
        .flatten()
        .unwrap_or_default()
}

fn serialize_engine_snapshot() -> String {
    with_engine(|engine| {
        let serialized = engine.serialize();
        BASE64_STANDARD.encode(serialized)
    })
    .unwrap_or_default()
}

fn native_is_available_impl() -> jboolean {
    JNI_TRUE
}

fn native_initialize_engine_impl(mut env: JNIEnv, filter_text: JString) -> jboolean {
    let result = panic::catch_unwind(move || {
        let text: String = match env.get_string(&filter_text) {
            Ok(value) => value.into(),
            Err(_) => return false,
        };
        load_engine_with_assets(&text, "", "", "[]", "")
    })
    .unwrap_or(false);

    to_bool(result)
}

fn native_initialize_engine_v2_impl(
    mut env: JNIEnv,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
) -> jboolean {
    let result = panic::catch_unwind(move || {
        let text: String = match env.get_string(&filter_text) {
            Ok(value) => value.into(),
            Err(_) => return false,
        };
        let resources: String = match env.get_string(&resources_json) {
            Ok(value) => value.into(),
            Err(_) => String::new(),
        };
        let tags: String = match env.get_string(&enabled_tags_json) {
            Ok(value) => value.into(),
            Err(_) => "[]".to_string(),
        };

        load_engine_with_assets(&text, &resources, &tags, "[]", "")
    })
    .unwrap_or(false);

    to_bool(result)
}

fn native_initialize_engine_v3_impl(
    mut env: JNIEnv,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
    catalog_sources_json: JString,
    serialized_engine_b64: JString,
) -> jboolean {
    let result = panic::catch_unwind(move || {
        let text: String = match env.get_string(&filter_text) {
            Ok(value) => value.into(),
            Err(_) => return false,
        };
        let resources: String = match env.get_string(&resources_json) {
            Ok(value) => value.into(),
            Err(_) => String::new(),
        };
        let tags: String = match env.get_string(&enabled_tags_json) {
            Ok(value) => value.into(),
            Err(_) => "[]".to_string(),
        };
        let catalog_sources: String = match env.get_string(&catalog_sources_json) {
            Ok(value) => value.into(),
            Err(_) => "[]".to_string(),
        };
        let serialized_engine: String = match env.get_string(&serialized_engine_b64) {
            Ok(value) => value.into(),
            Err(_) => String::new(),
        };

        load_engine_with_assets(
            &text,
            &resources,
            &tags,
            &catalog_sources,
            &serialized_engine,
        )
    })
    .unwrap_or(false);

    to_bool(result)
}

fn native_should_block_request_impl(
    mut env: JNIEnv,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jboolean {
    let result = panic::catch_unwind(move || {
        let url: String = match env.get_string(&request_url) {
            Ok(value) => value.into(),
            Err(_) => return false,
        };
        let source: String = match env.get_string(&source_url) {
            Ok(value) => value.into(),
            Err(_) => String::new(),
        };
        let request_type: String = match env.get_string(&resource_type) {
            Ok(value) => value.into(),
            Err(_) => "other".to_string(),
        };

        should_block(&url, &source, &request_type)
    })
    .unwrap_or(false);

    to_bool(result)
}

fn native_evaluate_request_impl(
    mut env: JNIEnv,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    let url: String = match env.get_string(&request_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let source: String = match env.get_string(&source_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let request_type: String = match env.get_string(&resource_type) {
        Ok(value) => value.into(),
        Err(_) => "other".to_string(),
    };
    let payload = panic::catch_unwind(|| evaluate_request(&url, &source, &request_type))
        .unwrap_or_else(|_| "{\"matched\":false}".to_string());
    match env.new_string(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn native_get_cosmetic_resources_impl(mut env: JNIEnv, page_url: JString) -> jstring {
    let url: String = match env.get_string(&page_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let payload =
        panic::catch_unwind(|| get_cosmetic_resources(&url)).unwrap_or_else(|_| "{}".to_string());

    match env.new_string(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn native_get_hidden_class_id_selectors_impl(
    mut env: JNIEnv,
    page_url: JString,
    classes_json: JString,
    ids_json: JString,
    exceptions_json: JString,
) -> jstring {
    let url: String = match env.get_string(&page_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let classes: String = match env.get_string(&classes_json) {
        Ok(value) => value.into(),
        Err(_) => "[]".to_string(),
    };
    let ids: String = match env.get_string(&ids_json) {
        Ok(value) => value.into(),
        Err(_) => "[]".to_string(),
    };
    let exceptions: String = match env.get_string(&exceptions_json) {
        Ok(value) => value.into(),
        Err(_) => "[]".to_string(),
    };
    let payload =
        panic::catch_unwind(|| get_hidden_class_id_selectors(&url, &classes, &ids, &exceptions))
            .unwrap_or_else(|_| "[]".to_string());

    match env.new_string(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn native_get_csp_directives_impl(
    mut env: JNIEnv,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    let url: String = match env.get_string(&request_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let source: String = match env.get_string(&source_url) {
        Ok(value) => value.into(),
        Err(_) => String::new(),
    };
    let request_type: String = match env.get_string(&resource_type) {
        Ok(value) => value.into(),
        Err(_) => "other".to_string(),
    };
    let payload = panic::catch_unwind(|| get_csp_directives(&url, &source, &request_type))
        .unwrap_or_else(|_| String::new());
    match env.new_string(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn native_serialize_engine_impl(env: JNIEnv) -> jstring {
    let payload = panic::catch_unwind(|| serialize_engine_snapshot()).unwrap_or_default();
    match env.new_string(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn native_dispose_engine_impl() {
    if let Ok(mut guard) = engine_slot().lock() {
        *guard = None;
    }
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeIsAvailable(
    _env: JNIEnv,
    _object: JObject,
) -> jboolean {
    native_is_available_impl()
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeIsAvailable(
    _env: JNIEnv,
    _object: JObject,
) -> jboolean {
    native_is_available_impl()
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeInitializeEngine(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
) -> jboolean {
    native_initialize_engine_impl(env, filter_text)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeInitializeEngine(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
) -> jboolean {
    native_initialize_engine_impl(env, filter_text)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeInitializeEngineV2(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
) -> jboolean {
    native_initialize_engine_v2_impl(env, filter_text, resources_json, enabled_tags_json)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeInitializeEngineV2(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
) -> jboolean {
    native_initialize_engine_v2_impl(env, filter_text, resources_json, enabled_tags_json)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeInitializeEngineV3(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
    catalog_sources_json: JString,
    serialized_engine_b64: JString,
) -> jboolean {
    native_initialize_engine_v3_impl(
        env,
        filter_text,
        resources_json,
        enabled_tags_json,
        catalog_sources_json,
        serialized_engine_b64,
    )
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeInitializeEngineV3(
    env: JNIEnv,
    _object: JObject,
    filter_text: JString,
    resources_json: JString,
    enabled_tags_json: JString,
    catalog_sources_json: JString,
    serialized_engine_b64: JString,
) -> jboolean {
    native_initialize_engine_v3_impl(
        env,
        filter_text,
        resources_json,
        enabled_tags_json,
        catalog_sources_json,
        serialized_engine_b64,
    )
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeShouldBlockRequest(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jboolean {
    native_should_block_request_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeShouldBlockRequest(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jboolean {
    native_should_block_request_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeEvaluateRequest(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    native_evaluate_request_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeEvaluateRequest(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    native_evaluate_request_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeGetCosmeticResources(
    env: JNIEnv,
    _object: JObject,
    page_url: JString,
) -> jstring {
    native_get_cosmetic_resources_impl(env, page_url)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeGetCosmeticResources(
    env: JNIEnv,
    _object: JObject,
    page_url: JString,
) -> jstring {
    native_get_cosmetic_resources_impl(env, page_url)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeGetHiddenClassIdSelectors(
    env: JNIEnv,
    _object: JObject,
    page_url: JString,
    classes_json: JString,
    ids_json: JString,
    exceptions_json: JString,
) -> jstring {
    native_get_hidden_class_id_selectors_impl(
        env,
        page_url,
        classes_json,
        ids_json,
        exceptions_json,
    )
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeGetHiddenClassIdSelectors(
    env: JNIEnv,
    _object: JObject,
    page_url: JString,
    classes_json: JString,
    ids_json: JString,
    exceptions_json: JString,
) -> jstring {
    native_get_hidden_class_id_selectors_impl(
        env,
        page_url,
        classes_json,
        ids_json,
        exceptions_json,
    )
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeGetCspDirectives(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    native_get_csp_directives_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeGetCspDirectives(
    env: JNIEnv,
    _object: JObject,
    request_url: JString,
    source_url: JString,
    resource_type: JString,
) -> jstring {
    native_get_csp_directives_impl(env, request_url, source_url, resource_type)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeSerializeEngine(
    env: JNIEnv,
    _object: JObject,
) -> jstring {
    native_serialize_engine_impl(env)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeSerializeEngine(
    env: JNIEnv,
    _object: JObject,
) -> jstring {
    native_serialize_engine_impl(env)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_1play_RustAdblockBridge_nativeDisposeEngine(
    _env: JNIEnv,
    _object: JObject,
) {
    native_dispose_engine_impl();
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeDisposeEngine(
    _env: JNIEnv,
    _object: JObject,
) {
    native_dispose_engine_impl();
}
