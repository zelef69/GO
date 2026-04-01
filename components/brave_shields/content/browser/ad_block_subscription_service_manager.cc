// Copyright (c) 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/brave_shields/content/browser/ad_block_subscription_service_manager.h"

#include <memory>
#include <limits>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

#include "base/base64url.h"
#include "base/check.h"
#include "base/containers/map_util.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_value_converter.h"
#include "base/logging.h"
#include "base/json/values_util.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "base/values.h"
#include "brave/components/brave_shields/content/browser/ad_block_subscription_filters_provider.h"
#include "brave/components/brave_shields/content/browser/ad_block_subscription_service_manager_observer.h"
#include "brave/components/brave_shields/core/browser/ad_block_filters_provider_manager.h"
#include "brave/components/brave_shields/core/browser/ad_block_list_p3a.h"
#include "brave/components/brave_shields/core/common/adblock/rs/src/lib.rs.h"
#include "brave/components/brave_shields/core/common/brave_shield_constants.h"
#include "brave/components/brave_shields/core/common/pref_names.h"
#include "brave/components/constants/brave_services_key.h"
#include "brave/components/onetabyt/buildflags/buildflags.h"
#include "build/build_config.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "crypto/sha2.h"
#include "net/base/net_errors.h"
#include "net/base/filename_util.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"

namespace brave_shields {

base::TimeDelta* g_testing_subscription_retry_interval = nullptr;

namespace {

constexpr uint16_t kSubscriptionMaxExpiresHours = 14 * 24;
constexpr base::TimeDelta kListRetryInterval = base::Hours(1);
constexpr base::TimeDelta kListCheckInitialDelay = base::Minutes(1);
constexpr base::TimeDelta kOneTabTubeSubscriptionReloadDebounce =
    base::Milliseconds(750);
constexpr int64_t kMaxFallbackSubscriptionDownloadBytes = 16 * 1024 * 1024;

const net::NetworkTrafficAnnotationTag
    kOneTabTubeFallbackSubscriptionTraffic =
        net::DefineNetworkTrafficAnnotation(
            "onetabtube_adblock_fallback_subscription",
            R"(
        semantics {
          sender: "OneTabTube Brave Shields fallback subscriptions"
          description:
            "Fetches public adblock filter list text files directly when the "
            "local OneTabTube build cannot authenticate against Brave's "
            "component updater-backed subscription download path."
          trigger:
            "Browser startup and periodic filter refreshes for OneTabTube "
            "local builds without a Brave service key."
          data:
            "Downloads public filter list text files from their published "
            "HTTPS URLs. No user information is sent."
          destination: WEBSITE
        }
        policy {
          cookies_allowed: NO
          setting:
            "This request is only used for OneTabTube local builds that do not "
            "have a BraveServiceKey. There is no user-facing toggle."
          policy_exception_justification: "Not yet implemented."
        })");

struct BuiltInSubscriptionDefinition {
  std::string_view url;
  std::string_view title;
  bool is_default_engine;
  uint8_t permission_mask;
  bool eager_on_startup;
};

constexpr BuiltInSubscriptionDefinition kOneTabTubeBuiltInSubscriptions[] = {
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
     "uBlock Origin Filters", true, 0, true},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2020.txt",
     "uBlock Origin 2020 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2021.txt",
     "uBlock Origin 2021 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2022.txt",
     "uBlock Origin 2022 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2023.txt",
     "uBlock Origin 2023 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2024.txt",
     "uBlock Origin 2024 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2025.txt",
     "uBlock Origin 2025 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-2026.txt",
     "uBlock Origin 2026 Filters", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-general.txt",
     "uBlock Origin Filters - General", true, 0, true},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt",
     "uBlock Origin Filters - Badware", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/resource-abuse.txt",
     "uBlock Origin Filters - Resource Abuse", true, 0, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt",
     "uBlock Origin Filters - Unbreak", true, 0, true},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt",
     "uBlock Origin Filters - Quick Fixes", true, 0, true},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/ubo-link-shorteners.txt",
     "uBlock Origin Filters - Link Shorteners", true, 0, false},
    {"https://easylist.to/easylist/easylist.txt", "EasyList", true, 0, true},
    {"https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-agh-online.txt",
     "URLhaus Malicious URL Blocklist", true, 0, false},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-unbreak.txt",
     "Brave Unbreak", true, 0, true},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-specific.txt",
     "Brave Specific", true, 0, true},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-social.txt",
     "Brave Social", true, 0, false},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-unbreak.txt",
     "Brave Unbreak (Lists)", true, 0, true},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-android-specific.txt",
     "Brave Android Specific", true, 0, true},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-sugarcoat.txt",
     "Brave SugarCoat Rules", true, 0, true},
    {"https://easylist.to/easylist/easyprivacy.txt", "EasyPrivacy", true, 0,
     true},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt",
     "uBlock Origin Filters - Privacy", true, 0, false},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-firstparty.txt",
     "Brave First-Party Specific Filters", false, 0, false},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-firstparty-regional.txt",
     "Brave First-Party Regional Filters", false, 0, false},
    {"https://secure.fanboy.co.nz/fanboy-cookiemonster_ubo.txt",
     "EasyList Cookie", false, 1, false},
    {"https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-cookies.txt",
     "uBlock Origin Filters - Cookie Notices", false, 1, false},
    {"https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists/brave-cookie-specific.txt",
     "Brave Cookie Specific", false, 1, false},
    {"https://secure.fanboy.co.nz/fanboy-mobile-notifications.txt",
     "Fanboy Mobile Notifications", false, 0, false},
};

bool ShouldUseOneTabTubePublicListFallback() {
#if BUILDFLAG(IS_ANDROID)
  return BUILDFLAG(IS_ONETABYT) &&
         std::string_view(BUILDFLAG(BRAVE_SERVICES_KEY)).empty();
#else
  return false;
#endif
}

bool SkipGURLField(std::string_view value, GURL* field) {
  return true;
}

bool ParseTimeValue(const base::Value* value, base::Time* field) {
  auto time = base::ValueToTime(value);
  if (!time) {
    return false;
  }
  *field = *time;
  return true;
}

bool ParseOptionalStringField(const base::Value* value,
                              std::optional<std::string>* field) {
  if (value == nullptr) {
    *field = std::nullopt;
    return true;
  } else if (!value->is_string()) {
    return false;
  } else {
    *field = value->GetString();
    return true;
  }
}

bool ParseExpiresWithFallback(const base::Value* value, uint16_t* field) {
  if (value == nullptr) {
    *field = kSubscriptionDefaultExpiresHours;
    return true;
  } else if (!value->is_int()) {
    return false;
  } else {
    int64_t i = value->GetInt();
    if (i < 0 || i > kSubscriptionMaxExpiresHours) {
      return false;
    }
    *field = (uint16_t)i;
    return true;
  }
}

bool ParseOptionalBoolField(const base::Value* value, bool* field) {
  if (value == nullptr) {
    return true;
  }
  if (!value->is_bool()) {
    return false;
  }
  *field = value->GetBool();
  return true;
}

bool ParseOptionalUint8Field(const base::Value* value, uint8_t* field) {
  if (value == nullptr) {
    return true;
  }
  if (!value->is_int()) {
    return false;
  }
  int64_t i = value->GetInt();
  if (i < 0 || i > std::numeric_limits<uint8_t>::max()) {
    return false;
  }
  *field = static_cast<uint8_t>(i);
  return true;
}

bool EnsureDirectoryExists(const base::FilePath& dir) {
  return base::CreateDirectory(dir);
}

bool ReplaceDownloadedFile(const base::FilePath& source,
                           const base::FilePath& destination) {
  return base::ReplaceFile(source, destination, nullptr);
}

bool URLLoadedSuccessfully(const network::SimpleURLLoader& loader) {
  return loader.NetError() == net::OK;
}

SubscriptionInfo BuildInfoFromDict(const GURL& sub_url,
                                   const base::DictValue& dict) {
  SubscriptionInfo info;
  base::JSONValueConverter<SubscriptionInfo> converter;
  converter.Convert(base::Value(dict.Clone()), &info);

  info.subscription_url = sub_url;

  return info;
}

const base::FilePath::CharType kSubscriptionsDir[] =
    FILE_PATH_LITERAL("FilterListSubscriptionCache");

}  // namespace

SubscriptionInfo::SubscriptionInfo() = default;
SubscriptionInfo::~SubscriptionInfo() = default;
SubscriptionInfo::SubscriptionInfo(const SubscriptionInfo&) = default;

void SubscriptionInfo::RegisterJSONConverter(
    base::JSONValueConverter<SubscriptionInfo>* converter) {
  // The `subscription_url` field is skipped, as it's not stored within the
  // JSON value and should be populated externally.
  converter->RegisterCustomField<GURL>(
      "subscription_url", &SubscriptionInfo::subscription_url, &SkipGURLField);
  converter->RegisterCustomValueField<base::Time>(
      "last_update_attempt", &SubscriptionInfo::last_update_attempt,
      &ParseTimeValue);
  converter->RegisterCustomValueField<base::Time>(
      "last_successful_update_attempt",
      &SubscriptionInfo::last_successful_update_attempt, &ParseTimeValue);
  converter->RegisterBoolField("enabled", &SubscriptionInfo::enabled);
  converter->RegisterCustomValueField<std::optional<std::string>>(
      "homepage", &SubscriptionInfo::homepage, &ParseOptionalStringField);
  converter->RegisterCustomValueField<std::optional<std::string>>(
      "title", &SubscriptionInfo::title, &ParseOptionalStringField);
  converter->RegisterCustomValueField<uint16_t>(
      "expires", &SubscriptionInfo::expires, &ParseExpiresWithFallback);
  converter->RegisterCustomValueField<bool>("hidden", &SubscriptionInfo::hidden,
                                            &ParseOptionalBoolField);
  converter->RegisterCustomValueField<bool>(
      "is_default_engine", &SubscriptionInfo::is_default_engine,
      &ParseOptionalBoolField);
  converter->RegisterCustomValueField<uint8_t>(
      "permission_mask", &SubscriptionInfo::permission_mask,
      &ParseOptionalUint8Field);
}

AdBlockSubscriptionServiceManager::AdBlockSubscriptionServiceManager(
    PrefService* local_state,
    AdBlockFiltersProviderManager* filters_provider_manager,
    AdBlockSubscriptionDownloadManager::DownloadManagerGetter
        download_manager_getter,
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory,
    const base::FilePath& profile_dir,
    AdBlockListP3A* list_p3a)
    : initialized_(false),
      local_state_(local_state),
      filters_provider_manager_(filters_provider_manager),
      url_loader_factory_(std::move(url_loader_factory)),
      subscription_path_(profile_dir.Append(kSubscriptionsDir)),
      subscription_update_timer_(
          std::make_unique<component_updater::TimerUpdateScheduler>()),
      list_p3a_(list_p3a) {
  std::move(download_manager_getter)
      .Run(base::BindOnce(
          &AdBlockSubscriptionServiceManager::OnGetDownloadManager,
          weak_ptr_factory_.GetWeakPtr()));
}

AdBlockSubscriptionServiceManager::~AdBlockSubscriptionServiceManager() =
    default;

base::FilePath AdBlockSubscriptionServiceManager::GetSubscriptionPath(
    const GURL& sub_url) const {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Subdirectories are generated by taking the SHA256 hash of the list URL
  // spec, then base64 encoding that hash. This generates paths that are:
  //     - deterministic
  //     - unique
  //     - constant length
  //     - path-safe
  //     - not too long (exactly 45 characters)
  const std::string hash = crypto::SHA256HashString(sub_url.spec());

  std::string pathsafe_hash;
  base::Base64UrlEncode(hash, base::Base64UrlEncodePolicy::INCLUDE_PADDING,
                        &pathsafe_hash);

  return subscription_path_.AppendASCII(pathsafe_hash);
}

GURL AdBlockSubscriptionServiceManager::GetListTextFileUrl(
    const GURL sub_url) const {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  base::FilePath cached_list_path = GetSubscriptionPath(sub_url).Append(
      brave_shields::kCustomSubscriptionListText);

  const GURL file_url = net::FilePathToFileURL(cached_list_path);

  return file_url;
}

void AdBlockSubscriptionServiceManager::OnUpdateTimer(
    component_updater::TimerUpdateScheduler::OnFinishedCallback on_finished) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!local_state_) {
    return;
  }

  subscriptions_ =
      local_state_->GetDict(prefs::kAdBlockListSubscriptions).Clone();

  for (const auto it : subscriptions_) {
    const std::string key = it.first;
    SubscriptionInfo info;
    const base::DictValue* list_subscription_dict =
        subscriptions_.FindDict(key);
    if (list_subscription_dict) {
      GURL sub_url(key);
      info = BuildInfoFromDict(sub_url, *list_subscription_dict);

      base::TimeDelta until_next_refresh =
          base::Hours(info.expires) -
          (base::Time::Now() - info.last_update_attempt);

      if (info.enabled &&
          ((info.last_update_attempt != info.last_successful_update_attempt) ||
           (until_next_refresh <= base::TimeDelta()))) {
        StartDownload(sub_url, false);
      }
    }
  }

  std::move(on_finished).Run();
}

void AdBlockSubscriptionServiceManager::StartDownload(const GURL& sub_url,
                                                      bool from_ui) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (ShouldUseOneTabTubePublicListFallback() && url_loader_factory_) {
    LOG(INFO) << "OTB_ADBLOCK event=list_download_start mode=fallback from_ui="
              << from_ui << " url=" << sub_url;
    StartFallbackDownload(sub_url);
    return;
  }

  // The download manager is tied to the lifetime of the profile, but
  // the AdBlockSubscriptionServiceManager lives as long as the browser process
  if (download_manager_) {
    bool download_service_available =
        download_manager_->IsAvailableForDownloads();
    if (download_service_available) {
      LOG(INFO) << "OTB_ADBLOCK event=list_download_start mode=component "
                << "from_ui=" << from_ui << " url=" << sub_url;
      download_manager_->StartDownload(sub_url, from_ui);
    }
  }
}

void AdBlockSubscriptionServiceManager::StartFallbackDownload(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!url_loader_factory_ || fallback_downloaders_.contains(sub_url)) {
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&EnsureDirectoryExists, GetSubscriptionPath(sub_url)),
      base::BindOnce(
          &AdBlockSubscriptionServiceManager::OnFallbackDownloadDirectoryReady,
          weak_ptr_factory_.GetWeakPtr(), sub_url));
}

void AdBlockSubscriptionServiceManager::OnFallbackDownloadDirectoryReady(
    const GURL& sub_url,
    bool created) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!created || !url_loader_factory_ || fallback_downloaders_.contains(sub_url)) {
    if (!created) {
      LOG(WARNING) << "OneTabTube adblock fallback list directory create failed: "
                   << sub_url;
      LOG(WARNING) << "OTB_ADBLOCK event=list_directory_create_failed url="
                   << sub_url;
      OnSubscriptionDownloadFailure(sub_url);
    }
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = sub_url;
  auto url_loader = network::SimpleURLLoader::Create(
      std::move(request), kOneTabTubeFallbackSubscriptionTraffic);
  url_loader->SetTimeoutDuration(base::Seconds(60));
  url_loader->SetRetryOptions(
      2, network::SimpleURLLoader::RETRY_ON_5XX |
             network::SimpleURLLoader::RETRY_ON_NETWORK_CHANGE);

  auto* url_loader_ptr = url_loader.get();
  fallback_downloaders_[sub_url] = std::move(url_loader);
  url_loader_ptr->DownloadToTempFile(
      url_loader_factory_.get(),
      base::BindOnce(
          &AdBlockSubscriptionServiceManager::OnFallbackDownloadComplete,
          weak_ptr_factory_.GetWeakPtr(), sub_url),
      kMaxFallbackSubscriptionDownloadBytes);
}

void AdBlockSubscriptionServiceManager::OnFallbackDownloadComplete(
    const GURL& sub_url,
    base::FilePath temporary_file) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  auto it = fallback_downloaders_.find(sub_url);
  if (it == fallback_downloaders_.end()) {
    return;
  }

  const bool loaded_successfully =
      !temporary_file.empty() && URLLoadedSuccessfully(*it->second);
  fallback_downloaders_.erase(it);

  if (!loaded_successfully) {
    LOG(WARNING) << "OneTabTube adblock fallback list download failed: "
                 << sub_url;
    LOG(WARNING) << "OTB_ADBLOCK event=list_download_failed url=" << sub_url;
    OnSubscriptionDownloadFailure(sub_url);
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&ReplaceDownloadedFile, temporary_file,
                     GetSubscriptionPath(sub_url).Append(
                         kCustomSubscriptionListText)),
      base::BindOnce(
          &AdBlockSubscriptionServiceManager::OnFallbackDownloadReplaced,
          weak_ptr_factory_.GetWeakPtr(), sub_url));
}

void AdBlockSubscriptionServiceManager::OnFallbackDownloadReplaced(
    const GURL& sub_url,
    bool success) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!success) {
    LOG(WARNING) << "OneTabTube adblock fallback list cache write failed: "
                 << sub_url;
    LOG(WARNING) << "OTB_ADBLOCK event=list_cache_write_failed url=" << sub_url;
    OnSubscriptionDownloadFailure(sub_url);
    return;
  }

  LOG(INFO) << "OneTabTube adblock fallback list ready: " << sub_url;
  LOG(INFO) << "OTB_ADBLOCK event=list_ready url=" << sub_url;
  OnSubscriptionDownloaded(sub_url);
}

AdBlockSubscriptionFiltersProvider*
AdBlockSubscriptionServiceManager::FindAnyEnabledSubscriptionProvider(
    bool is_default_engine) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  for (const auto& [sub_url, provider] : subscription_filters_providers_) {
    auto info = GetInfo(sub_url);
    if (info && info->enabled &&
        info->is_default_engine == is_default_engine) {
      return provider.get();
    }
  }

  return nullptr;
}

void AdBlockSubscriptionServiceManager::ScheduleSubscriptionEngineReload(
    bool is_default_engine) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!ShouldUseOneTabTubePublicListFallback()) {
    if (auto* provider = FindAnyEnabledSubscriptionProvider(is_default_engine)) {
      provider->OnListAvailable();
    }
    return;
  }

  if (is_default_engine) {
    pending_default_engine_reload_ = true;
  } else {
    pending_additional_engine_reload_ = true;
  }

  if (!pending_subscription_reload_timer_.IsRunning()) {
    pending_subscription_reload_timer_.Start(
        FROM_HERE, kOneTabTubeSubscriptionReloadDebounce, this,
        &AdBlockSubscriptionServiceManager::FlushPendingSubscriptionEngineReloads);
  }
}

void AdBlockSubscriptionServiceManager::FlushPendingSubscriptionEngineReloads() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (pending_default_engine_reload_) {
    pending_default_engine_reload_ = false;
    if (auto* provider = FindAnyEnabledSubscriptionProvider(true)) {
      provider->OnListAvailable();
    }
  }

  if (pending_additional_engine_reload_) {
    pending_additional_engine_reload_ = false;
    if (auto* provider = FindAnyEnabledSubscriptionProvider(false)) {
      provider->OnListAvailable();
    }
  }
}

void AdBlockSubscriptionServiceManager::CreateSubscription(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (subscription_filters_providers_.contains(sub_url)) {
    return;
  }

  SubscriptionInfo info;
  info.subscription_url = sub_url;
  info.last_update_attempt = base::Time();
  info.last_successful_update_attempt = base::Time();
  info.enabled = true;

  UpdateSubscriptionPrefs(sub_url, info);

  auto subscription_filters_provider =
      CreateSubscriptionProvider(info);
  subscription_filters_providers_.insert(
      std::make_pair(sub_url, std::move(subscription_filters_provider)));

  StartDownload(sub_url, true);
}

std::vector<SubscriptionInfo>
AdBlockSubscriptionServiceManager::GetSubscriptions() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  auto infos = std::vector<SubscriptionInfo>();

  for (const auto subscription : subscriptions_) {
    auto info = GetInfo(GURL(subscription.first));
    DCHECK(info);
    infos.push_back(*info);
  }

  return infos;
}

void AdBlockSubscriptionServiceManager::EnableSubscription(const GURL& sub_url,
                                                           bool enabled) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  std::optional<SubscriptionInfo> info = GetInfo(sub_url);

  DCHECK(info);

  info->enabled = enabled;

  auto it = subscription_filters_providers_.find(sub_url);
  if (enabled) {
    DCHECK(it == subscription_filters_providers_.end());
    auto subscription_filters_provider =
        CreateSubscriptionProvider(*info);
    subscription_filters_provider->OnListAvailable();
    subscription_filters_providers_.insert(
        {sub_url, std::move(subscription_filters_provider)});
  } else {
    DCHECK(it != subscription_filters_providers_.end());
    subscription_filters_providers_.erase(it);
  }

  UpdateSubscriptionPrefs(sub_url, *info);
}

void AdBlockSubscriptionServiceManager::DeleteSubscription(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto it = subscription_filters_providers_.find(sub_url);
  if (it != subscription_filters_providers_.end()) {
    subscription_filters_providers_.erase(it);
  }
  ClearSubscriptionPrefs(sub_url);

  base::ThreadPool::PostTask(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::BEST_EFFORT,
       base::TaskShutdownBehavior::BLOCK_SHUTDOWN},
      base::BindOnce(base::IgnoreResult(&base::DeletePathRecursively),
                     GetSubscriptionPath(sub_url)));
}

void AdBlockSubscriptionServiceManager::RefreshSubscription(const GURL& sub_url,
                                                            bool from_ui) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  StartDownload(sub_url, from_ui);
}

std::unique_ptr<AdBlockSubscriptionFiltersProvider>
AdBlockSubscriptionServiceManager::CreateSubscriptionProvider(
    const SubscriptionInfo& info) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  return std::make_unique<AdBlockSubscriptionFiltersProvider>(
      local_state_, filters_provider_manager_,
      GetSubscriptionPath(info.subscription_url).Append(
          kCustomSubscriptionListText),
      info.is_default_engine, info.permission_mask,
      base::BindRepeating(&AdBlockSubscriptionServiceManager::OnListMetadata,
                          weak_ptr_factory_.GetWeakPtr(),
                          info.subscription_url));
}

void AdBlockSubscriptionServiceManager::OnGetDownloadManager(
    AdBlockSubscriptionDownloadManager* download_manager) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  download_manager_ = download_manager->AsWeakPtr();
  // base::Unretained is ok here because AdBlockSubscriptionServiceManager will
  // outlive AdBlockSubscriptionDownloadManager
  download_manager_->set_subscription_path_callback(base::BindRepeating(
      &AdBlockSubscriptionServiceManager::GetSubscriptionPath,
      base::Unretained(this)));
  download_manager_->set_on_download_succeeded_callback(base::BindRepeating(
      &AdBlockSubscriptionServiceManager::OnSubscriptionDownloaded,
      base::Unretained(this)));
  download_manager_->set_on_download_failed_callback(base::BindRepeating(
      &AdBlockSubscriptionServiceManager::OnSubscriptionDownloadFailure,
      base::Unretained(this)));

  download_manager_->CancelAllPendingDownloads();
  LoadSubscriptionServices();

  subscription_update_timer_->Schedule(
      kListCheckInitialDelay, kListRetryInterval,
      base::BindRepeating(&AdBlockSubscriptionServiceManager::OnUpdateTimer,
                          weak_ptr_factory_.GetWeakPtr()),
      base::DoNothing());
}

void AdBlockSubscriptionServiceManager::OnListMetadata(
    const GURL& sub_url,
    const adblock::FilterListMetadata& metadata) {
  // The engine will have loaded new list metadata; read it and update local
  // preferences with the new values.

  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  std::optional<SubscriptionInfo> info = GetInfo(sub_url);

  if (!info) {
    return;
  }

  // Title can only be set once - only set it if an existing title does not
  // exist
  if (!info->title && metadata.title.has_value) {
    info->title = std::make_optional(std::string(metadata.title.value));
  }

  if (metadata.homepage.has_value) {
    info->homepage = std::make_optional(std::string(metadata.homepage.value));
  } else {
    info->homepage = std::nullopt;
  }

  if (metadata.expires_hours.has_value) {
    info->expires = metadata.expires_hours.value;
  } else {
    info->expires = kSubscriptionDefaultExpiresHours;
  }

  UpdateSubscriptionPrefs(sub_url, *info);

  NotifyObserversOfServiceEvent();
}

void AdBlockSubscriptionServiceManager::SetUpdateIntervalsForTesting(
    base::TimeDelta* initial_delay,
    base::TimeDelta* retry_interval) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  g_testing_subscription_retry_interval = retry_interval;
  subscription_update_timer_->Schedule(
      *initial_delay, *retry_interval,
      base::BindRepeating(&AdBlockSubscriptionServiceManager::OnUpdateTimer,
                          weak_ptr_factory_.GetWeakPtr()),
      base::DoNothing());
}

// static
std::optional<SubscriptionInfo> AdBlockSubscriptionServiceManager::GetInfo(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto* list_subscription_dict = subscriptions_.FindDict(sub_url.spec());
  if (!list_subscription_dict) {
    return std::nullopt;
  }

  return std::make_optional<SubscriptionInfo>(
      BuildInfoFromDict(sub_url, *list_subscription_dict));
}

void AdBlockSubscriptionServiceManager::LoadSubscriptionServices() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!local_state_) {
    return;
  }

  subscriptions_ =
      local_state_->GetDict(prefs::kAdBlockListSubscriptions).Clone();
  EnsureBuiltInSubscriptions();
  LOG(INFO) << "OTB_ADBLOCK event=subscription_services_loaded count="
            << subscriptions_.size();

  AdBlockSubscriptionFiltersProvider* cached_default_engine_provider = nullptr;
  AdBlockSubscriptionFiltersProvider* cached_additional_engine_provider =
      nullptr;

  for (const auto it : subscriptions_) {
    const std::string key = it.first;
    SubscriptionInfo info;
    const base::DictValue* list_subscription_dict =
        subscriptions_.FindDict(key);
    if (list_subscription_dict) {
      GURL sub_url(key);
      info = BuildInfoFromDict(sub_url, *list_subscription_dict);

      if (info.enabled) {
        auto subscription_filters_provider =
            CreateSubscriptionProvider(info);
        auto* provider_ptr = subscription_filters_provider.get();
        subscription_filters_providers_.insert(
            std::make_pair(sub_url, std::move(subscription_filters_provider)));

        if (!info.last_successful_update_attempt.is_null()) {
          if (info.is_default_engine && !cached_default_engine_provider) {
            cached_default_engine_provider = provider_ptr;
          } else if (!info.is_default_engine &&
                     !cached_additional_engine_provider) {
            cached_additional_engine_provider = provider_ptr;
          }
        }
      }
    }
  }

  if (cached_default_engine_provider) {
    cached_default_engine_provider->OnListAvailable();
  }
  if (cached_additional_engine_provider) {
    cached_additional_engine_provider->OnListAvailable();
  }
}

void AdBlockSubscriptionServiceManager::EnsureBuiltInSubscriptions() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  if (!ShouldUseOneTabTubePublicListFallback()) {
    return;
  }

  int total_subscriptions = 0;
  int eager_downloads_started = 0;
  int prefs_updates = 0;

  for (const auto& built_in : kOneTabTubeBuiltInSubscriptions) {
    ++total_subscriptions;
    const GURL sub_url(std::string(built_in.url));
    if (!sub_url.is_valid()) {
      continue;
    }

    auto info = GetInfo(sub_url);
    const bool needs_initial_download =
        !info || info->last_successful_update_attempt.is_null();
    bool should_update_prefs = false;

    if (!info) {
      info.emplace();
      info->subscription_url = sub_url;
      info->last_update_attempt = base::Time();
      info->last_successful_update_attempt = base::Time();
      should_update_prefs = true;
    }

    if (!info->enabled || !info->hidden ||
        info->is_default_engine != built_in.is_default_engine ||
        info->permission_mask != built_in.permission_mask ||
        info->title != std::optional<std::string>(std::string(built_in.title))) {
      info->enabled = true;
      info->hidden = true;
      info->is_default_engine = built_in.is_default_engine;
      info->permission_mask = built_in.permission_mask;
      info->title = std::string(built_in.title);
      should_update_prefs = true;
    }

    if (should_update_prefs) {
      UpdateSubscriptionPrefs(sub_url, *info);
      ++prefs_updates;
    }

    if (needs_initial_download && built_in.eager_on_startup) {
      StartDownload(sub_url, true);
      ++eager_downloads_started;
    }
  }

  LOG(INFO) << "OTB_ADBLOCK event=built_in_subscriptions_ready total="
            << total_subscriptions
            << " prefs_updates=" << prefs_updates
            << " eager_downloads=" << eager_downloads_started;
}

// Updates preferences to reflect a new state for the specified filter list
// subscription. Creates the entry if it does not yet exist.
void AdBlockSubscriptionServiceManager::UpdateSubscriptionPrefs(
    const GURL& sub_url,
    const SubscriptionInfo& info) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!local_state_) {
    return;
  }

  {
    ScopedDictPrefUpdate update(local_state_, prefs::kAdBlockListSubscriptions);
    base::DictValue& subscriptions = update.Get();
    base::DictValue subscription_dict;
    subscription_dict.Set("enabled", info.enabled);
    subscription_dict.Set("last_update_attempt",
                          base::TimeToValue(info.last_update_attempt));
    subscription_dict.Set(
        "last_successful_update_attempt",
        base::TimeToValue(info.last_successful_update_attempt));
    if (info.homepage) {
      subscription_dict.Set("homepage", *info.homepage);
    }
    if (info.title) {
      subscription_dict.Set("title", *info.title);
    }
    subscription_dict.Set("expires", info.expires);
    subscription_dict.Set("hidden", info.hidden);
    subscription_dict.Set("is_default_engine", info.is_default_engine);
    subscription_dict.Set("permission_mask",
                          static_cast<int>(info.permission_mask));
    subscriptions.Set(sub_url.spec(), std::move(subscription_dict));

    // TODO(bridiver) - change to pref registrar
    subscriptions_ = subscriptions.Clone();
  }
  list_p3a_->ReportFilterListUsage();
}

// Updates preferences to remove all state for the specified filter list
// subscription.
void AdBlockSubscriptionServiceManager::ClearSubscriptionPrefs(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!local_state_) {
    return;
  }

  ScopedDictPrefUpdate update(local_state_, prefs::kAdBlockListSubscriptions);
  base::DictValue& subscriptions = update.Get();
  subscriptions.Remove(sub_url.spec());

  // TODO(bridiver) - change to pref registrar
  subscriptions_ = subscriptions.Clone();
}

void AdBlockSubscriptionServiceManager::OnSubscriptionDownloaded(
    const GURL& sub_url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);

  std::optional<SubscriptionInfo> info = GetInfo(sub_url);

  if (!info) {
    return;
  }

  info->last_update_attempt = base::Time::Now();
  info->last_successful_update_attempt = info->last_update_attempt;
  UpdateSubscriptionPrefs(sub_url, *info);
  LOG(INFO) << "OTB_ADBLOCK event=list_downloaded url=" << sub_url
            << " default_engine=" << info->is_default_engine;

  ScheduleSubscriptionEngineReload(info->is_default_engine);

  NotifyObserversOfServiceEvent();
}

void AdBlockSubscriptionServiceManager::OnSubscriptionDownloadFailure(
    const GURL& sub_url) {
  std::optional<SubscriptionInfo> info = GetInfo(sub_url);

  if (!info) {
    return;
  }

  info->last_update_attempt = base::Time::Now();
  UpdateSubscriptionPrefs(sub_url, *info);
  LOG(INFO) << "OTB_ADBLOCK event=list_download_failure url=" << sub_url;

  NotifyObserversOfServiceEvent();
}

void AdBlockSubscriptionServiceManager::NotifyObserversOfServiceEvent() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  for (auto& observer : observers_) {
    observer.OnServiceUpdateEvent();
  }
}

void AdBlockSubscriptionServiceManager::AddObserver(
    AdBlockSubscriptionServiceManagerObserver* observer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  observers_.AddObserver(observer);
}

void AdBlockSubscriptionServiceManager::RemoveObserver(
    AdBlockSubscriptionServiceManagerObserver* observer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  observers_.RemoveObserver(observer);
}

}  // namespace brave_shields
