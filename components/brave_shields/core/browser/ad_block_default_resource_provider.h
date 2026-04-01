// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_AD_BLOCK_DEFAULT_RESOURCE_PROVIDER_H_
#define BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_AD_BLOCK_DEFAULT_RESOURCE_PROVIDER_H_

#include <memory>
#include <optional>
#include <string>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "brave/components/brave_shields/core/browser/ad_block_resource_provider.h"

namespace component_updater {
class ComponentUpdateService;
}  // namespace component_updater

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
}  // namespace network

class AdBlockServiceTest;

namespace brave_shields {

class AdBlockDefaultResourceProvider : public AdBlockResourceProvider {
 public:
  AdBlockDefaultResourceProvider(
      component_updater::ComponentUpdateService* cus,
      const base::FilePath& profile_dir,
      scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);
  ~AdBlockDefaultResourceProvider() override;
  AdBlockDefaultResourceProvider(const AdBlockDefaultResourceProvider&) =
      delete;
  AdBlockDefaultResourceProvider& operator=(
      const AdBlockDefaultResourceProvider&) = delete;

  /// Returns the path to the resources file.
  base::FilePath GetResourcesPath();

  void LoadResources(
      base::OnceCallback<void(AdblockResourceStorageBox)>) override;

 private:
  friend class ::AdBlockServiceTest;

  void OnComponentReady(const base::FilePath&);
  void MaybeStartFallbackDownload();
  void OnFallbackDownloadComplete(
      std::unique_ptr<network::SimpleURLLoader> url_loader,
      std::optional<std::string> body);
  void OnFallbackResourcesWritten(const std::string& resources_json,
                                  bool success);

  base::FilePath component_path_;
  base::FilePath fallback_resources_path_;
  scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory_;
  bool fallback_download_in_progress_ = false;

  base::WeakPtrFactory<AdBlockDefaultResourceProvider> weak_factory_{this};
};

}  // namespace brave_shields

#endif  // BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_AD_BLOCK_DEFAULT_RESOURCE_PROVIDER_H_
