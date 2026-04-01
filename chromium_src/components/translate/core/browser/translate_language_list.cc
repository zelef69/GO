// Copyright (c) 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "components/translate/core/browser/translate_language_list.h"

#include "brave/components/translate/core/common/brave_translate_features.h"

#define SetResourceRequestsAllowed SetResourceRequestsAllowed_ChromiumImpl
#include <components/translate/core/browser/translate_language_list.cc>
#undef SetResourceRequestsAllowed

namespace translate {

void TranslateLanguageList::SetResourceRequestsAllowed(bool allowed) {
  if (!ShouldUpdateLanguagesList()) {
    allowed = false;
  }
  SetResourceRequestsAllowed_ChromiumImpl(allowed);
}

}  // namespace translate
