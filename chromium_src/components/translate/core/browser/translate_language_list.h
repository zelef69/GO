// Copyright (c) 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_LANGUAGE_LIST_H_
#define BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_LANGUAGE_LIST_H_

#define SetResourceRequestsAllowed(...)                  \
  SetResourceRequestsAllowed_ChromiumImpl(__VA_ARGS__); \
  void SetResourceRequestsAllowed(__VA_ARGS__)
#include <components/translate/core/browser/translate_language_list.h>  // IWYU pragma: export
#undef SetResourceRequestsAllowed

#endif  // BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_LANGUAGE_LIST_H_
