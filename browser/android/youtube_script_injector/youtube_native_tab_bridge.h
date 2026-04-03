/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_ANDROID_YOUTUBE_SCRIPT_INJECTOR_YOUTUBE_NATIVE_TAB_BRIDGE_H_
#define BRAVE_BROWSER_ANDROID_YOUTUBE_SCRIPT_INJECTOR_YOUTUBE_NATIVE_TAB_BRIDGE_H_

namespace youtube_script_injector {

// Returns the media-element-first bridge script for active YouTube browser tabs.
const char16_t* GetYouTubeNativeTabBridgeScript();

}  // namespace youtube_script_injector

#endif  // BRAVE_BROWSER_ANDROID_YOUTUBE_SCRIPT_INJECTOR_YOUTUBE_NATIVE_TAB_BRIDGE_H_
