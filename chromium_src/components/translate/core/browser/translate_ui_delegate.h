/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_UI_DELEGATE_H_
#define BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_UI_DELEGATE_H_

#define ShouldShowAlwaysTranslateShortcut(...)                  \
  ShouldShowAlwaysTranslateShortcut_ChromiumImpl(__VA_ARGS__); \
  bool ShouldShowAlwaysTranslateShortcut(__VA_ARGS__)
#define ShouldAutoAlwaysTranslate(...)                  \
  ShouldAutoAlwaysTranslate_ChromiumImpl(__VA_ARGS__); \
  bool ShouldAutoAlwaysTranslate(__VA_ARGS__)
#include <components/translate/core/browser/translate_ui_delegate.h>  // IWYU pragma: export
#undef ShouldAutoAlwaysTranslate
#undef ShouldShowAlwaysTranslateShortcut

#endif  // BRAVE_CHROMIUM_SRC_COMPONENTS_TRANSLATE_CORE_BROWSER_TRANSLATE_UI_DELEGATE_H_
