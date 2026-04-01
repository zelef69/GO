/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "chrome/browser/preloading/prerender/prerender_manager.h"

#define MaybeStartPrewarmSearchResult MaybeStartPrewarmSearchResult_ChromiumImpl
#define StopPrewarmSearchResultForTesting \
  StopPrewarmSearchResultForTesting_ChromiumImpl
#define SetPrewarmUrlForTesting SetPrewarmUrlForTesting_ChromiumImpl
#define StartPrerenderSearchResult StartPrerenderSearchResult_ChromiumImpl
#define StopPrerenderSearchResult StopPrerenderSearchResult_ChromiumImpl
#define StartPrerenderDirectUrlInput StartPrerenderDirectUrlInput_ChromiumImpl
#define HasSearchResultPagePrerendered HasSearchResultPagePrerendered_ChromiumImpl
#define GetPrerenderCanonicalSearchURLForTesting \
  GetPrerenderCanonicalSearchURLForTesting_ChromiumImpl

#include <chrome/browser/preloading/prerender/prerender_manager.cc>

#undef GetPrerenderCanonicalSearchURLForTesting
#undef HasSearchResultPagePrerendered
#undef StartPrerenderDirectUrlInput
#undef StopPrerenderSearchResult
#undef StartPrerenderSearchResult
#undef SetPrewarmUrlForTesting
#undef StopPrewarmSearchResultForTesting
#undef MaybeStartPrewarmSearchResult

bool PrerenderManager::MaybeStartPrewarmSearchResult() {
  return false;
}

void PrerenderManager::StopPrewarmSearchResultForTesting() {}

void PrerenderManager::SetPrewarmUrlForTesting(const GURL& url) {}

void PrerenderManager::StartPrerenderSearchResult(
    const GURL& canonical_search_url,
    const GURL& prerendering_url,
    base::WeakPtr<content::PreloadingAttempt> attempt) {}

void PrerenderManager::StopPrerenderSearchResult(
    const GURL& canonical_search_url) {}

base::WeakPtr<content::PrerenderHandle>
PrerenderManager::StartPrerenderDirectUrlInput(
    const GURL& prerendering_url,
    content::PreloadingAttempt& preloading_attempt) {
  return nullptr;
}

bool PrerenderManager::HasSearchResultPagePrerendered() const {
  return false;
}

const GURL PrerenderManager::GetPrerenderCanonicalSearchURLForTesting() const {
  return GURL();
}
