// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/brave_shields/core/browser/ad_block_default_resource_provider.h"

#include <optional>
#include <string>
#include <string_view>
#include <utility>

#include "base/files/file_util.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "base/files/file_path.h"
#include "base/task/thread_pool.h"
#include "brave/components/brave_component_updater/browser/dat_file_util.h"
#include "brave/components/brave_shields/core/browser/ad_block_component_installer.h"
#include "brave/components/constants/brave_services_key.h"
#include "brave/components/onetabyt/buildflags/buildflags.h"
#include "build/build_config.h"
#include "net/base/net_errors.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"

namespace {

constexpr char kAdBlockResourcesFilename[] = "resources.json";
constexpr char kOneTabTubeFallbackResourcesUrl[] =
    "https://raw.githubusercontent.com/brave/brave-core/master/ios/brave-ios/Tests/ClientTests/Resources/ad-block-resources/resources.json";
constexpr size_t kMaxFallbackResourcesDownloadBytes = 1024 * 1024;
constexpr base::FilePath::CharType kFallbackResourcesDir[] =
    FILE_PATH_LITERAL("OneTabTubeAdBlockResources");

const net::NetworkTrafficAnnotationTag kOneTabTubeFallbackResourcesTraffic =
    net::DefineNetworkTrafficAnnotation(
        "onetabtube_adblock_fallback_resources",
        R"(
        semantics {
          sender: "OneTabTube Brave Shields fallback resources"
          description:
            "Fetches a public Brave adblock resources bundle with the "
            "scriptlet set needed by OneTabTube local builds when the local "
            "build cannot authenticate against Brave's component updater."
          trigger:
            "Browser startup for OneTabTube local builds, and later on demand "
            "when adblock resources are requested before the authenticated "
            "component updater can provide them."
          data:
            "Downloads a public resources.json file from Brave's public "
            "GitHub-hosted brave-core repository."
          destination: WEBSITE
        }
        policy {
          cookies_allowed: NO
          setting:
            "This request is only used for OneTabTube local builds that do not "
            "have a BraveServiceKey. There is no user-facing toggle."
          policy_exception_justification: "Not yet implemented."
        })");

bool ShouldUseOneTabTubeFallbackResources() {
#if BUILDFLAG(IS_ANDROID)
  return BUILDFLAG(IS_ONETABYT) &&
         std::string_view(BUILDFLAG(BRAVE_SERVICES_KEY)).empty();
#else
  return false;
#endif
}

bool PersistFallbackResources(const base::FilePath& path,
                              const std::string& resources_json) {
  return base::CreateDirectory(path.DirName()) &&
         base::WriteFile(path, resources_json);
}

bool HasRequiredOneTabTubeScriptletResources(
    std::string_view resources_json) {
  return resources_json.find("\"json-prune.js\"") != std::string_view::npos &&
         resources_json.find("\"set-constant.js\"") !=
             std::string_view::npos;
}

bool URLLoadedSuccessfully(const network::SimpleURLLoader& loader) {
  if (loader.NetError() != net::OK) {
    return false;
  }

  const auto* response_info = loader.ResponseInfo();
  if (!response_info || !response_info->headers) {
    return false;
  }

  const int response_code = response_info->headers->response_code();
  return response_code >= 200 && response_code < 300;
}

}  // namespace

namespace brave_shields {

AdBlockDefaultResourceProvider::AdBlockDefaultResourceProvider(
    component_updater::ComponentUpdateService* cus,
    const base::FilePath& profile_dir,
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory)
    : url_loader_factory_(std::move(url_loader_factory)) {
  // Can be nullptr in unit tests
  if (cus) {
    RegisterAdBlockDefaultResourceComponent(
        cus,
        base::BindRepeating(&AdBlockDefaultResourceProvider::OnComponentReady,
                            weak_factory_.GetWeakPtr()));
  }

  if (ShouldUseOneTabTubeFallbackResources()) {
    fallback_resources_path_ =
        profile_dir.Append(kFallbackResourcesDir).AppendASCII(
            kAdBlockResourcesFilename);
    LOG(INFO) << "OTB_ADBLOCK event=resource_provider fallback_mode=1";
    MaybeStartFallbackDownload();
  }
}

AdBlockDefaultResourceProvider::~AdBlockDefaultResourceProvider() = default;

base::FilePath AdBlockDefaultResourceProvider::GetResourcesPath() {
  if (component_path_.empty()) {
    return fallback_resources_path_;
  }

  return component_path_.AppendASCII(kAdBlockResourcesFilename);
}

void AdBlockDefaultResourceProvider::OnComponentReady(
    const base::FilePath& path) {
  component_path_ = path;
  LOG(INFO) << "OTB_ADBLOCK event=resources_component_ready";
  base::FilePath resources_path = GetResourcesPath();

  if (resources_path.empty()) {
    // This should not happen, but if it does, we should not proceed.
    return;
  }

  // Load the resources (as ResourceStorage)
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     resources_path),
      base::BindOnce(
          [](base::WeakPtr<AdBlockDefaultResourceProvider> provider,
             const std::string& resources_json) {
            if (!provider) {
              return;
            }
            auto storage = adblock::new_resource_storage(resources_json);
            provider->NotifyResourcesLoaded(std::move(storage));
          },
          weak_factory_.GetWeakPtr()));
}

void AdBlockDefaultResourceProvider::MaybeStartFallbackDownload() {
  if (!ShouldUseOneTabTubeFallbackResources() || fallback_resources_path_.empty() ||
      !url_loader_factory_ || fallback_download_in_progress_) {
    return;
  }

  fallback_download_in_progress_ = true;
  LOG(INFO) << "OTB_ADBLOCK event=fallback_resources_download_start";

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(kOneTabTubeFallbackResourcesUrl);
  auto url_loader =
      network::SimpleURLLoader::Create(std::move(request),
                                       kOneTabTubeFallbackResourcesTraffic);
  url_loader->SetTimeoutDuration(base::Seconds(30));
  url_loader->SetRetryOptions(
      2, network::SimpleURLLoader::RETRY_ON_5XX |
             network::SimpleURLLoader::RETRY_ON_NETWORK_CHANGE);

  auto* url_loader_ptr = url_loader.get();
  url_loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdBlockDefaultResourceProvider::OnFallbackDownloadComplete,
                     weak_factory_.GetWeakPtr(), std::move(url_loader)),
      kMaxFallbackResourcesDownloadBytes);
}

void AdBlockDefaultResourceProvider::OnFallbackDownloadComplete(
    std::unique_ptr<network::SimpleURLLoader> url_loader,
    std::optional<std::string> body) {
  fallback_download_in_progress_ = false;

  if (!body || !URLLoadedSuccessfully(*url_loader)) {
    LOG(WARNING) << "OneTabTube adblock fallback resources download failed";
    LOG(WARNING) << "OTB_ADBLOCK event=fallback_resources_download_failed";
    return;
  }

  const std::string resources_json = *body;
  if (!HasRequiredOneTabTubeScriptletResources(resources_json)) {
    LOG(WARNING)
        << "OneTabTube adblock fallback resources bundle missing required "
           "scriptlets";
    LOG(WARNING)
        << "OTB_ADBLOCK event=fallback_resources_invalid missing_scriptlets=1";
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&PersistFallbackResources, fallback_resources_path_,
                     resources_json),
      base::BindOnce(
          &AdBlockDefaultResourceProvider::OnFallbackResourcesWritten,
          weak_factory_.GetWeakPtr(), resources_json));
}

void AdBlockDefaultResourceProvider::OnFallbackResourcesWritten(
    const std::string& resources_json,
    bool success) {
  if (!success) {
    LOG(WARNING) << "OneTabTube adblock fallback resources cache write failed";
    LOG(WARNING) << "OTB_ADBLOCK event=fallback_resources_write_failed";
    return;
  }

  LOG(INFO) << "OneTabTube adblock fallback resources ready";
  LOG(INFO) << "OTB_ADBLOCK event=fallback_resources_ready";
  NotifyResourcesLoaded(adblock::new_resource_storage(resources_json));
}

void AdBlockDefaultResourceProvider::LoadResources(
    base::OnceCallback<void(AdblockResourceStorageBox)> cb) {
  base::FilePath resources_path = component_path_.empty()
                                      ? fallback_resources_path_
                                      : component_path_.AppendASCII(
                                            kAdBlockResourcesFilename);
  if (resources_path.empty()) {
    // If the path is not ready yet, run the callback with empty resources to
    // avoid blocking filter data loads.
    MaybeStartFallbackDownload();
    LOG(INFO) << "OTB_ADBLOCK event=load_resources source=empty";
    auto empty_storage = adblock::new_empty_resource_storage();
    std::move(cb).Run(std::move(empty_storage));
    return;
  }

  MaybeStartFallbackDownload();
  LOG(INFO) << "OTB_ADBLOCK event=load_resources source="
            << (component_path_.empty() ? "fallback" : "component");

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     resources_path),
      base::BindOnce(
          [](base::OnceCallback<void(AdblockResourceStorageBox)> cb,
             bool using_fallback_resources,
             const std::string& resources_json) {
            if (using_fallback_resources &&
                !HasRequiredOneTabTubeScriptletResources(resources_json)) {
              LOG(WARNING)
                  << "OTB_ADBLOCK event=load_resources_invalid_fallback";
              auto empty_storage = adblock::new_empty_resource_storage();
              std::move(cb).Run(std::move(empty_storage));
              return;
            }

            auto storage = resources_json.empty()
                               ? adblock::new_empty_resource_storage()
                               : adblock::new_resource_storage(resources_json);
            std::move(cb).Run(std::move(storage));
          },
          std::move(cb), component_path_.empty()));
}

}  // namespace brave_shields
