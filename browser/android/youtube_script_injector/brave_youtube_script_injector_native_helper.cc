/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/android/youtube_script_injector/brave_youtube_script_injector_native_helper.h"

#include "base/android/jni_android.h"
#include "brave/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.h"
#include "chrome/android/chrome_jni_headers/BraveYouTubeScriptInjectorNativeHelper_jni.h"
#include "content/public/browser/web_contents.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"

namespace youtube_script_injector {

// static
void JNI_BraveYouTubeScriptInjectorNativeHelper_SetFullscreen(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);
  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }

  helper->MaybeSetFullscreen();
}

// static
void JNI_BraveYouTubeScriptInjectorNativeHelper_ExitFullscreen(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);
  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }

  helper->MaybeExitFullscreen();
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_HasFullscreenBeenRequested(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return false;
  }

  return helper->HasFullscreenBeenRequested();
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_IsPictureInPictureAvailable(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->IsPictureInPictureAvailable();
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_Play(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->MaybePlayVideo();
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_Pause(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->MaybePauseVideo();
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_SeekBy(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents,
    jint offset_seconds) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->MaybeSeekBy(offset_seconds);
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_Next(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents,
    jboolean preserve_video_presentation) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->MaybeNextTrack(preserve_video_presentation);
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_Previous(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents,
    jboolean preserve_video_presentation) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->MaybePreviousTrack(preserve_video_presentation);
  }

  return false;
}

// static
jboolean JNI_BraveYouTubeScriptInjectorNativeHelper_RecoverPictureInPictureFocus(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents,
    jboolean require_visible) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->RecoverPictureInPictureFocus(require_visible);
  }

  return false;
}

// static
jboolean
JNI_BraveYouTubeScriptInjectorNativeHelper_SetPictureInPictureRecoveryVisualGuard(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jweb_contents,
    jboolean active) {
  content::WebContents* web_contents =
      content::WebContents::FromJavaWebContents(jweb_contents);

  YouTubeScriptInjectorTabHelper* helper =
      YouTubeScriptInjectorTabHelper::FromWebContents(web_contents);
  if (helper) {
    return helper->SetPictureInPictureRecoveryVisualGuard(active);
  }

  return false;
}

// static
void EnterPictureInPicture(content::WebContents* web_contents) {
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_BraveYouTubeScriptInjectorNativeHelper_enterPictureInPicture(
      env, web_contents->GetJavaWebContents());
}

void NotifyPictureInPictureRecoveryVisualGuardChanged(
    content::WebContents* web_contents,
    bool active) {
  if (!web_contents) {
    return;
  }

  JNIEnv* env = base::android::AttachCurrentThread();
  Java_BraveYouTubeScriptInjectorNativeHelper_onPictureInPictureRecoveryVisualGuardChanged(
      env, web_contents->GetJavaWebContents(), active);
}

bool ShouldPreserveVideoPresentationForPictureInPicture(
    content::WebContents* web_contents) {
  if (!web_contents) {
    return false;
  }

  JNIEnv* env = base::android::AttachCurrentThread();
  return Java_BraveYouTubeScriptInjectorNativeHelper_shouldPreserveVideoPresentationForPictureInPicture(
      env, web_contents->GetJavaWebContents());
}

}  // namespace youtube_script_injector

DEFINE_JNI(BraveYouTubeScriptInjectorNativeHelper)
