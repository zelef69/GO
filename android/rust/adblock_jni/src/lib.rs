use adblock::lists::ParseOptions;
use adblock::request::Request;
use adblock::Engine;
use jni::objects::{JObject, JString};
use jni::sys::{jboolean, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;
use std::panic;
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

fn load_engine(filter_text: &str) -> bool {
    let rules = filter_text.lines().filter(|line| !line.trim().is_empty());
    let engine = Engine::from_rules(rules, ParseOptions::default());
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

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeIsAvailable(
    _env: JNIEnv,
    _object: JObject,
) -> jboolean {
    JNI_TRUE
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeInitializeEngine(
    mut env: JNIEnv,
    _object: JObject,
    filter_text: JString,
) -> jboolean {
    let result = panic::catch_unwind(move || {
        let text: String = match env.get_string(&filter_text) {
            Ok(value) => value.into(),
            Err(_) => return false,
        };
        load_engine(&text)
    })
    .unwrap_or(false);

    to_bool(result)
}

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeShouldBlockRequest(
    mut env: JNIEnv,
    _object: JObject,
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

#[no_mangle]
pub extern "system" fn Java_com_example_go_play_RustAdblockBridge_nativeDisposeEngine(
    _env: JNIEnv,
    _object: JObject,
) {
    if let Ok(mut guard) = engine_slot().lock() {
        *guard = None;
    }
}
