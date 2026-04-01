/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_PREFS_H_
#define BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_PREFS_H_

#include <string_view>

#define ShouldAutoTranslate(...)                    \
  ShouldAutoTranslate_ChromiumImpl(__VA_ARGS__);   \
  bool ShouldAutoTranslate(__VA_ARGS__)
#include <components/translate/core/browser/translate_prefs.h>  // IWYU pragma: export
#undef ShouldAutoTranslate

#endif  // BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_PREFS_H_
