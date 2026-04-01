/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_CHROMIUM_SRC_CHROME_BROWSER_PRELOADING_PRERENDER_PRERENDER_MANAGER_H_
#define BRAVE_CHROMIUM_SRC_CHROME_BROWSER_PRELOADING_PRERENDER_PRERENDER_MANAGER_H_

#define MaybeStartPrewarmSearchResult \
  MaybeStartPrewarmSearchResult_ChromiumImpl(); \
  bool MaybeStartPrewarmSearchResult
#define StopPrewarmSearchResultForTesting \
  StopPrewarmSearchResultForTesting_ChromiumImpl(); \
  void StopPrewarmSearchResultForTesting
#define SetPrewarmUrlForTesting \
  SetPrewarmUrlForTesting_ChromiumImpl(const GURL& url); \
  void SetPrewarmUrlForTesting
#define StartPrerenderSearchResult \
  StartPrerenderSearchResult_ChromiumImpl( \
      const GURL& canonical_search_url, \
      const GURL& prerendering_url, \
      base::WeakPtr<content::PreloadingAttempt> attempt); \
  void StartPrerenderSearchResult
#define StopPrerenderSearchResult \
  StopPrerenderSearchResult_ChromiumImpl(const GURL& canonical_search_url); \
  void StopPrerenderSearchResult
#define StartPrerenderDirectUrlInput \
  StartPrerenderDirectUrlInput_ChromiumImpl( \
      const GURL& prerendering_url, \
      content::PreloadingAttempt& preloading_attempt); \
  base::WeakPtr<content::PrerenderHandle> StartPrerenderDirectUrlInput
#define HasSearchResultPagePrerendered \
  HasSearchResultPagePrerendered_ChromiumImpl() const; \
  bool HasSearchResultPagePrerendered
#define GetPrerenderCanonicalSearchURLForTesting \
  GetPrerenderCanonicalSearchURLForTesting_ChromiumImpl() const; \
  const GURL GetPrerenderCanonicalSearchURLForTesting

#include <chrome/browser/preloading/prerender/prerender_manager.h>  // IWYU pragma: export

#undef GetPrerenderCanonicalSearchURLForTesting
#undef HasSearchResultPagePrerendered
#undef StartPrerenderDirectUrlInput
#undef StopPrerenderSearchResult
#undef StartPrerenderSearchResult
#undef SetPrewarmUrlForTesting
#undef StopPrewarmSearchResultForTesting
#undef MaybeStartPrewarmSearchResult

#endif  // BRAVE_CHROMIUM_SRC_CHROME_BROWSER_PRELOADING_PRERENDER_PRERENDER_MANAGER_H_
