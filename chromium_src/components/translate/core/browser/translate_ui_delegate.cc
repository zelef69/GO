/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "components/translate/core/browser/translate_ui_delegate.h"

#include "brave/components/translate/core/common/brave_translate_features.h"

#define ShouldShowAlwaysTranslateShortcut \
  ShouldShowAlwaysTranslateShortcut_ChromiumImpl
#define ShouldAutoAlwaysTranslate ShouldAutoAlwaysTranslate_ChromiumImpl
#include <components/translate/core/browser/translate_ui_delegate.cc>
#undef ShouldAutoAlwaysTranslate
#undef ShouldShowAlwaysTranslateShortcut

namespace translate {

bool TranslateUIDelegate::ShouldShowAlwaysTranslateShortcut() const {
  if (!IsBraveAutoTranslateEnabled())
    return false;

  return ShouldShowAlwaysTranslateShortcut_ChromiumImpl();
}

#if BUILDFLAG(IS_ANDROID) || BUILDFLAG(IS_IOS)
bool TranslateUIDelegate::ShouldAutoAlwaysTranslate() {
  if (!IsBraveAutoTranslateEnabled())
    return false;

  return ShouldAutoAlwaysTranslate_ChromiumImpl();
}
#endif  // BUILDFLAG(IS_ANDROID) || BUILDFLAG(IS_IOS)

}  // namespace translate
