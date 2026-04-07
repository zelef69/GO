/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.h"

#include <memory>
#include <string>

#include "base/feature_list.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/supports_user_data.h"
#include "base/time/time.h"
#include "brave/browser/android/youtube_script_injector/brave_youtube_script_injector_native_helper.h"
#include "brave/browser/android/youtube_script_injector/features.h"
#include "brave/browser/android/youtube_script_injector/youtube_native_tab_bridge.h"
#include "brave/components/brave_shields/content/browser/brave_shields_util.h"
#include "brave/components/constants/pref_names.h"
#include "brave/content/public/browser/fullscreen_page_data.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "url/gurl.h"
#include "url/url_util.h"

namespace {
constexpr int32_t kMainWorldId = 0;

constexpr char16_t kYoutubeBackgroundPlayback[] =
    uR"(
(function() {
  if (document._addEventListener === undefined) {
    document._addEventListener = document.addEventListener;
    document.addEventListener = function(a, b, c) {
      if (a != 'visibilitychange') {
        document._addEventListener(a, b, c);
      }
    };
  }

  // Override document.visibilityState to always return 'visible'
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: function() { return 'visible'; }
  });
}());
)";

constexpr char16_t kYoutubeMediaSessionControls[] =
    uR"OTBMEDIA(
(function() {
  if (window.__onetabtubeMediaSessionControlsInstalled) {
    return;
  }
  window.__onetabtubeMediaSessionControlsInstalled = true;

  let updateTimer = 0;
  let lifecycleObserver = null;
  let observedVideo = null;

  function log(event, detail) {
    try {
      console.info(
          'OTB_MEDIA event=' + event + (detail ? ' ' + String(detail) : ''));
    } catch (e) {}
  }

  function updatePlaybackState(reason) {
    if (!navigator.mediaSession) {
      return;
    }
    const video = currentVideo();
    let playbackState = 'none';
    if (video) {
      playbackState = isVideoPlaying(video) ? 'playing' : 'paused';
    }
    try {
      navigator.mediaSession.playbackState = playbackState;
      log('playback_state', 'reason=' + reason + ' state=' + playbackState);
    } catch (e) {}
  }

  function currentVideo() {
    return document.querySelector('video');
  }

  function isVideoPaused(video) {
    return !!video && (video.paused || video.ended);
  }

  function isVideoPlaying(video) {
    return !!video && !video.paused && !video.ended;
  }

  function triggerPlay(source) {
    const video = currentVideo();
    if (!video || typeof video.play !== 'function') {
      return false;
    }
    if (isVideoPlaying(video)) {
      log('play_already', 'source=' + source);
      return true;
    }
    try {
      const result = video.play();
      if (result && typeof result.catch === 'function') {
        result.catch(() => {});
      }
      updatePlaybackState('play');
      log('play', 'source=' + source);
      return true;
    } catch (e) {
      return false;
    }
  }

  function triggerPause(source) {
    const video = currentVideo();
    if (!video || typeof video.pause !== 'function') {
      return false;
    }
    if (isVideoPaused(video)) {
      log('pause_already', 'source=' + source);
      return true;
    }
    try {
      video.pause();
      updatePlaybackState('pause');
      log('pause', 'source=' + source);
      return true;
    } catch (e) {
      return false;
    }
  }

  function triggerSeekBy(offsetSeconds, source) {
    const video = currentVideo();
    if (!video || !Number.isFinite(video.currentTime)) {
      return false;
    }
    try {
      const duration = Number.isFinite(video.duration) ? video.duration : null;
      const targetTime = Math.max(
          0,
          duration != null
              ? Math.min(duration, video.currentTime + offsetSeconds)
              : video.currentTime + offsetSeconds);
      video.currentTime = targetTime;
      updatePlaybackState('seek');
      log('seek', 'source=' + source + ' offset=' + offsetSeconds);
      return true;
    } catch (e) {
      return false;
    }
  }

  function triggerSeekTo(details, source) {
    const video = currentVideo();
    if (!video || !details || !Number.isFinite(details.seekTime)) {
      return false;
    }
    try {
      video.currentTime = Number(details.seekTime);
      updatePlaybackState('seek_to');
      updatePositionState('seek_to');
      log('seek_to', 'source=' + source + ' position=' + details.seekTime);
      return true;
    } catch (e) {
      return false;
    }
  }

  function setActionHandler(action, handler) {
    try {
      navigator.mediaSession.setActionHandler(action, handler);
    } catch (e) {}
  }

  function updatePositionState(reason) {
    if (!navigator.mediaSession
        || typeof navigator.mediaSession.setPositionState !== 'function') {
      return;
    }
    const video = currentVideo();
    if (!video || !Number.isFinite(video.duration) || video.duration <= 0
        || !Number.isFinite(video.currentTime)) {
      return;
    }
    try {
      navigator.mediaSession.setPositionState({
        duration: video.duration,
        playbackRate: Number.isFinite(video.playbackRate) ? video.playbackRate : 1,
        position: Math.min(video.duration, Math.max(0, video.currentTime)),
      });
      log('position_state', 'reason=' + reason);
    } catch (e) {}
  }

  function updateMediaSessionHandlers(reason) {
    if (!navigator.mediaSession
        || typeof navigator.mediaSession.setActionHandler !== 'function') {
      return;
    }

    observeVideo();
    // Standard path for browser-tab playback: map next/previous style
    // transport controls into 10-second seek jumps so Android surfaces expose
    // usable side buttons without relying on YouTube DOM selectors.
    setActionHandler('nexttrack', () => triggerSeekBy(10, 'media_session'));
    setActionHandler('previoustrack', () => triggerSeekBy(-10, 'media_session'));
    setActionHandler('play', () => triggerPlay('media_session'));
    setActionHandler('pause', () => triggerPause('media_session'));
    setActionHandler('seekforward', () => triggerSeekBy(10, 'media_session'));
    setActionHandler('seekbackward', () => triggerSeekBy(-10, 'media_session'));
    setActionHandler('seekto', (details) => triggerSeekTo(details, 'media_session'));
    updatePlaybackState(reason);
    updatePositionState(reason);
    log('handlers_updated',
        'reason=' + reason + ' actions=play,pause,next,previous,seek');
  }

  function scheduleUpdate(reason) {
    clearTimeout(updateTimer);
    updateTimer = setTimeout(() => updateMediaSessionHandlers(reason), 120);
  }

  function observeLifecycle() {
    if (lifecycleObserver || typeof MutationObserver !== 'function') {
      return;
    }
    const root = document.body || document.documentElement;
    if (!root) {
      return;
    }
    lifecycleObserver = new MutationObserver(() => {
      scheduleUpdate('mutation');
    });
    lifecycleObserver.observe(root, {childList: true, subtree: true});
  }

  function observeVideo() {
    const video = currentVideo();
    if (!video || video === observedVideo) {
      return;
    }
    observedVideo = video;
    video.addEventListener('playing', () => scheduleUpdate('video_playing'), true);
    video.addEventListener('pause', () => scheduleUpdate('video_pause'), true);
    video.addEventListener('loadeddata', () => scheduleUpdate('video_loaded'), true);
    video.addEventListener('loadedmetadata', () => scheduleUpdate('video_metadata'), true);
    video.addEventListener('durationchange', () => scheduleUpdate('video_duration'), true);
    video.addEventListener('timeupdate', () => updatePositionState('timeupdate'), true);
    video.addEventListener('ratechange', () => updatePositionState('ratechange'), true);
    video.addEventListener('seeking', () => updatePositionState('seeking'), true);
    video.addEventListener('ended', () => scheduleUpdate('video_ended'), true);
  }

  function bootstrap(reason) {
    observeLifecycle();
    observeVideo();
    scheduleUpdate(reason || 'bootstrap');
  }

  bootstrap('initial');
  document.addEventListener('DOMContentLoaded', () => bootstrap('dom_ready'), true);
  document.addEventListener('yt-navigate-finish', () => bootstrap('yt_navigate_finish'), true);
  window.addEventListener('pageshow', () => bootstrap('pageshow'), true);
  window.addEventListener('focus', () => bootstrap('focus'), true);
}());
)OTBMEDIA";

constexpr char16_t kYoutubePictureInPictureSupport[] =
    uR"(
(function() {
  // Function to modify the flags if the target object exists.
  function modifyYtcfgFlags() {
    const config = window.ytcfg.get("WEB_PLAYER_CONTEXT_CONFIGS")
      ?.WEB_PLAYER_CONTEXT_CONFIG_ID_MWEB_WATCH
    if (config && config.serializedExperimentFlags && typeof config
      .serializedExperimentFlags === 'string') {
      let flags = config.serializedExperimentFlags;

      // Replace target flags.
      flags = flags
        .replace(
          "html5_picture_in_picture_blocking_ontimeupdate=true",
          "html5_picture_in_picture_blocking_ontimeupdate=false")
        .replace("html5_picture_in_picture_blocking_onresize=true",
          "html5_picture_in_picture_blocking_onresize=false")
        .replace(
          "html5_picture_in_picture_blocking_document_fullscreen=true",
          "html5_picture_in_picture_blocking_document_fullscreen=false"
        )
        .replace(
          "html5_picture_in_picture_blocking_standard_api=true",
          "html5_picture_in_picture_blocking_standard_api=false")
        .replace("html5_picture_in_picture_logging_onresize=true",
          "html5_picture_in_picture_logging_onresize=false");

      // Assign updated flags back to config.
      config.serializedExperimentFlags = flags;
    }
  }

  if (window.ytcfg) {
    modifyYtcfgFlags();
  } else {
    document.addEventListener('load', (event) => {
      const target = event.target;
      if (target.tagName === 'SCRIPT' && window.ytcfg) {
        // Check and modify flags when a new script is added.
        modifyYtcfgFlags();
      }
    }, true);
  }
}());
)";

constexpr char16_t kYoutubeSearchInputContrast[] =
    uR"OTBSEARCH(
(function() {
  if (window.__onetabtubeSearchInputContrastInstalled) {
    return;
  }
  window.__onetabtubeSearchInputContrastInstalled = true;

  const STYLE_ID = 'onetabtube-search-input-contrast-style';
  const HOST_SELECTOR = [
    'ytm-searchbox',
    'ytm-searchbox-form',
    'yt-searchbox',
    'ytd-searchbox',
    '[role="search"]',
  ].join(', ');
  const INPUT_SELECTOR = [
    'ytm-searchbox input',
    'ytm-searchbox-form input',
    'yt-searchbox input',
    'ytd-searchbox input',
    'input#search',
    'input.ytSearchboxComponentInputBox',
    'input[type="search"][aria-label]',
  ].join(', ');

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = ''
        + HOST_SELECTOR + ' {'
        + ' --yt-spec-text-primary: #000000 !important;'
        + ' --yt-spec-text-secondary: #5f6368 !important;'
        + ' --yt-spec-text-disabled: #5f6368 !important;'
        + ' color: #000000 !important;'
        + '}'
        + INPUT_SELECTOR + ' {'
        + ' color: #000000 !important;'
        + ' -webkit-text-fill-color: #000000 !important;'
        + ' caret-color: #000000 !important;'
        + ' background-color: #ffffff !important;'
        + '}'
        + INPUT_SELECTOR + '::placeholder {'
        + ' color: #5f6368 !important;'
        + ' -webkit-text-fill-color: #5f6368 !important;'
        + ' opacity: 1 !important;'
        + '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function applyInlineStyles() {
    ensureStyle();
    for (const host of document.querySelectorAll(HOST_SELECTOR)) {
      if (!(host instanceof HTMLElement)) {
        continue;
      }
      host.style.setProperty('--yt-spec-text-primary', '#000000', 'important');
      host.style.setProperty('--yt-spec-text-secondary', '#5f6368', 'important');
      host.style.setProperty('--yt-spec-text-disabled', '#5f6368', 'important');
      host.style.setProperty('color', '#000000', 'important');
    }
    for (const input of document.querySelectorAll(INPUT_SELECTOR)) {
      if (!(input instanceof HTMLInputElement
            || input instanceof HTMLTextAreaElement)) {
        continue;
      }
      input.style.setProperty('color', '#000000', 'important');
      input.style.setProperty('-webkit-text-fill-color', '#000000', 'important');
      input.style.setProperty('caret-color', '#000000', 'important');
      input.style.setProperty('background-color', '#ffffff', 'important');
    }
  }

  let refreshTimer = 0;
  function scheduleApply() {
    if (refreshTimer) {
      clearTimeout(refreshTimer);
    }
    refreshTimer = setTimeout(() => {
      refreshTimer = 0;
      applyInlineStyles();
    }, 80);
  }

  if (typeof MutationObserver === 'function') {
    const root = document.body || document.documentElement;
    if (root) {
      const observer = new MutationObserver(() => scheduleApply());
      observer.observe(root, {childList: true, subtree: true, attributes: true});
    }
  }

  document.addEventListener('DOMContentLoaded', applyInlineStyles, true);
  document.addEventListener('yt-navigate-finish', applyInlineStyles, true);
  window.addEventListener('pageshow', applyInlineStyles, true);
  window.addEventListener('focus', scheduleApply, true);
  applyInlineStyles();
}());
)OTBSEARCH";

#if 0
constexpr char16_t kYoutubeFullscreenAmbientBackdrop[] =
    uR"OTBAMBIENT(
(function() {
  if (window.__onetabtubeFullscreenAmbientInstalled) {
    return;
  }
  window.__onetabtubeFullscreenAmbientInstalled = true;

  const ROOT_ATTR = 'data-onetabtube-ambient-root';
  const OVERLAY_ID = 'onetabtube-fullscreen-ambient';
  const STYLE_ID = 'onetabtube-fullscreen-ambient-style';
  let applyTimer = 0;
  let boundSourceVideo = null;
  let boundBackgroundVideo = null;
  let boundStream = null;

  function log(event, detail) {
    try {
      console.info(
          'OTB_FULLSCREEN_AMBIENT event=' + event
          + (detail ? ' ' + String(detail) : ''));
    } catch (e) {}
  }

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = ''
        + '[' + ROOT_ATTR + '] {'
        + ' background: #000 !important;'
        + ' overflow: hidden !important;'
        + '}'
        + '[' + ROOT_ATTR + '] > #' + OVERLAY_ID + ' {'
        + ' position: absolute !important;'
        + ' inset: 0 !important;'
        + ' overflow: hidden !important;'
        + ' pointer-events: none !important;'
        + ' z-index: 0 !important;'
        + ' background: #000 !important;'
        + '}'
        + '[' + ROOT_ATTR + '] > #' + OVERLAY_ID + ' > video {'
        + ' position: absolute !important;'
        + ' inset: -14% !important;'
        + ' width: 128% !important;'
        + ' height: 128% !important;'
        + ' object-fit: cover !important;'
        + ' transform: scale(1.08) !important;'
        + ' filter: blur(72px) saturate(1.18) brightness(0.82) !important;'
        + ' opacity: 0.88 !important;'
        + '}'
        + '[' + ROOT_ATTR + '] > :not(#' + OVERLAY_ID + ') {'
        + ' position: relative !important;'
        + ' z-index: 1 !important;'
        + '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function ambientRoot() {
    const fullscreenRoot = fullscreenElement();
    if (!fullscreenRoot || !(fullscreenRoot instanceof HTMLElement)) {
      return null;
    }
    if (fullscreenRoot instanceof HTMLVideoElement) {
      return null;
    }
    return fullscreenRoot;
  }

  function currentVideo(root) {
    if (root && typeof root.querySelector === 'function') {
      const scopedVideo = root.querySelector('video');
      if (scopedVideo instanceof HTMLVideoElement) {
        return scopedVideo;
      }
    }
    const fallbackVideo = document.querySelector('video');
    return fallbackVideo instanceof HTMLVideoElement ? fallbackVideo : null;
  }

  function releaseStream() {
    if (boundBackgroundVideo) {
      try {
        boundBackgroundVideo.pause();
      } catch (e) {}
      try {
        boundBackgroundVideo.srcObject = null;
      } catch (e) {}
    }
    if (boundStream) {
      try {
        for (const track of boundStream.getTracks()) {
          track.stop();
        }
      } catch (e) {}
    }
    boundSourceVideo = null;
    boundBackgroundVideo = null;
    boundStream = null;
  }

  function ensureOverlay(root) {
    ensureStyle();
    root.setAttribute(ROOT_ATTR, '1');
    if (!root.dataset.onetabtubeAmbientOriginalPosition) {
      const computedPosition = window.getComputedStyle(root).position;
      root.dataset.onetabtubeAmbientOriginalPosition = computedPosition || '';
      if (!computedPosition || computedPosition === 'static') {
        root.style.setProperty('position', 'relative', 'important');
      }
    }
    let overlay = root.querySelector('#' + OVERLAY_ID);
    if (overlay instanceof HTMLElement) {
      return overlay;
    }
    overlay = document.createElement('div');
    overlay.id = OVERLAY_ID;
    overlay.setAttribute('aria-hidden', 'true');

    const backdropVideo = document.createElement('video');
    backdropVideo.muted = true;
    backdropVideo.defaultMuted = true;
    backdropVideo.autoplay = true;
    backdropVideo.loop = true;
    backdropVideo.playsInline = true;
    backdropVideo.setAttribute('muted', '');
    backdropVideo.setAttribute('playsinline', '');
    backdropVideo.setAttribute('disableRemotePlayback', '');
    overlay.appendChild(backdropVideo);

    root.insertBefore(overlay, root.firstChild);
    return overlay;
  }

  function bindCapturedStream(backgroundVideo, sourceVideo) {
    if (!(backgroundVideo instanceof HTMLVideoElement)
        || !(sourceVideo instanceof HTMLVideoElement)) {
      releaseStream();
      return;
    }
    if (boundSourceVideo === sourceVideo
        && boundBackgroundVideo === backgroundVideo
        && boundStream) {
      return;
    }

    releaseStream();

    const captureStream =
        sourceVideo.captureStream || sourceVideo.mozCaptureStream;
    if (typeof captureStream !== 'function') {
      log('capture_unsupported');
      return;
    }

    try {
      const stream = captureStream.call(sourceVideo);
      if (!stream) {
        log('capture_empty');
        return;
      }
      boundSourceVideo = sourceVideo;
      boundBackgroundVideo = backgroundVideo;
      boundStream = stream;
      backgroundVideo.srcObject = stream;
      const maybePromise = backgroundVideo.play();
      if (maybePromise && typeof maybePromise.catch === 'function') {
        maybePromise.catch(() => {});
      }
      log('capture_bound');
    } catch (e) {
      releaseStream();
      log('capture_failed', e && e.message ? e.message : 'unknown');
    }
  }

  function teardownAmbient(reason) {
    clearTimeout(applyTimer);
    applyTimer = 0;
    const overlay = document.getElementById(OVERLAY_ID);
    if (overlay && overlay.parentElement) {
      const root = overlay.parentElement;
      overlay.remove();
      if (root instanceof HTMLElement && root.hasAttribute(ROOT_ATTR)) {
        const originalPosition =
            root.dataset.onetabtubeAmbientOriginalPosition || '';
        if (!originalPosition || originalPosition === 'static') {
          root.style.removeProperty('position');
        } else {
          root.style.setProperty('position', originalPosition);
        }
        delete root.dataset.onetabtubeAmbientOriginalPosition;
        root.removeAttribute(ROOT_ATTR);
      }
    }
    releaseStream();
    if (reason) {
      log('teardown', reason);
    }
  }

  function applyAmbient(reason) {
    const root = ambientRoot();
    const sourceVideo = currentVideo(root);
    if (!root || !sourceVideo) {
      teardownAmbient(reason || 'no_fullscreen_root');
      return;
    }

    const overlay = ensureOverlay(root);
    const backgroundVideo =
        overlay ? overlay.querySelector('video') : null;
    if (!(backgroundVideo instanceof HTMLVideoElement)) {
      teardownAmbient('missing_background_video');
      return;
    }

    bindCapturedStream(backgroundVideo, sourceVideo);
    log('apply', reason || 'unknown');
  }

  function scheduleApply(reason) {
    clearTimeout(applyTimer);
    applyTimer = setTimeout(() => applyAmbient(reason), 90);
  }

  document.addEventListener(
      'fullscreenchange', () => scheduleApply('fullscreenchange'), true);
  document.addEventListener(
      'webkitfullscreenchange',
      () => scheduleApply('webkitfullscreenchange'),
      true);
  document.addEventListener(
      'yt-navigate-finish', () => scheduleApply('yt_navigate_finish'), true);
  document.addEventListener(
      'playing', () => scheduleApply('playing'), true);
  document.addEventListener(
      'loadedmetadata', () => scheduleApply('loadedmetadata'), true);
  document.addEventListener(
      'emptied', () => scheduleApply('emptied'), true);
  window.addEventListener('pageshow', () => scheduleApply('pageshow'), true);
  window.addEventListener('focus', () => scheduleApply('focus'), true);

  if (typeof MutationObserver === 'function') {
    const root = document.body || document.documentElement;
    if (root) {
      const observer = new MutationObserver(() => {
        if (fullscreenElement()) {
          scheduleApply('mutation');
        }
      });
      observer.observe(root, {childList: true, subtree: true});
    }
  }

  scheduleApply('initial');
}());
)OTBAMBIENT";
#endif

constexpr char16_t kYoutubeTransientOverlaySuppression[] =
    uR"OTBOVERLAY(
(function() {
  if (window.__onetabtubeTransientOverlaySuppressionInstalled) {
    return;
  }
  window.__onetabtubeTransientOverlaySuppressionInstalled = true;

  const STYLE_ID = 'onetabtube-transient-overlay-style';
  const CSS_TEXT = [
    '.ytp-bezel',
    '.ytp-bezel-text-wrapper',
    '.ytp-bezel-text',
    '.ytp-doubletap-ui',
    '.ytp-doubletap-ui-legacy'
  ].join(', ') + ' {'
      + ' display: none !important;'
      + ' opacity: 0 !important;'
      + ' visibility: hidden !important;'
      + '}';

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS_TEXT;
    (document.head || document.documentElement).appendChild(style);
  }

  document.addEventListener('DOMContentLoaded', ensureStyle, true);
  document.addEventListener('yt-navigate-finish', ensureStyle, true);
  window.addEventListener('pageshow', ensureStyle, true);
  ensureStyle();
}());
)OTBOVERLAY";

[[maybe_unused]] constexpr char16_t kYoutubeAdRequestGuard[] =
    uR"(
(function() {
  if (window.__onetabtubeAdGuardInstalled) {
    return;
  }
  window.__onetabtubeAdGuardInstalled = true;

  const blockedPatterns = [
    /^https:\/\/googleads\.g\.doubleclick\.net\/pagead\/id/i,
    /^https:\/\/googleads\.g\.doubleclick\.net\/ytcs\/adview/i,
    /^https:\/\/(?:www\.)?youtube\.com\/pagead\//i,
    /^https:\/\/(?:www\.)?google\.com\/pagead\/1p-user-list\//i,
    /^https:\/\/static\.doubleclick\.net\/instream\/ad_status\.js/i
  ];

  function isBlockedUrl(rawUrl) {
    if (!rawUrl) return false;
    let absoluteUrl = '';
    try {
      absoluteUrl = new URL(String(rawUrl), location.href).href;
    } catch (e) {
      return false;
    }
    return blockedPatterns.some(pattern => pattern.test(absoluteUrl));
  }

  const originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = function(resource, init) {
      const url = typeof resource === 'string' ? resource : resource?.url;
      if (isBlockedUrl(url)) {
        return Promise.reject(new TypeError('Blocked by OneTabTube ad guard'));
      }
      return originalFetch.call(this, resource, init);
    };
  }

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__onetabtubeBlocked = isBlockedUrl(url);
    return originalOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function(body) {
    if (this.__onetabtubeBlocked) {
      try {
        this.abort();
      } catch (e) {}
      return;
    }
    return originalSend.call(this, body);
  };

  if (typeof navigator.sendBeacon === 'function') {
    const originalSendBeacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      if (isBlockedUrl(url)) {
        return true;
      }
      return originalSendBeacon(url, data);
    };
  }

  const imageProto = window.HTMLImageElement?.prototype;
  const imageSrcDescriptor = imageProto
      ? Object.getOwnPropertyDescriptor(imageProto, 'src')
      : null;
  if (imageProto && imageSrcDescriptor?.set && imageSrcDescriptor?.get) {
    Object.defineProperty(imageProto, 'src', {
      configurable: true,
      enumerable: imageSrcDescriptor.enumerable,
      get() {
        return imageSrcDescriptor.get.call(this);
      },
      set(value) {
        if (isBlockedUrl(value)) {
          imageSrcDescriptor.set.call(this, 'data:image/gif;base64,R0lGODlhAQABAAAAACw=');
          return value;
        }
        return imageSrcDescriptor.set.call(this, value);
      }
    });
  }
}());
)";

[[maybe_unused]] constexpr char16_t kYoutubePlaybackStability[] =
    uR"OTBPLAY(
(function() {
  if (window.__onetabtubePlaybackGuardInstalled) {
    return;
  }
  window.__onetabtubePlaybackGuardInstalled = true;

  const FOREGROUND_RESUME_STORAGE_KEY = '__onetabtubeForegroundPlayback';
  const FOREGROUND_RESUME_TTL_MS = 30000;
  const PLAYABILITY_RECOVERY_STORAGE_KEY = '__onetabtubePlaybackRecovery';
  const PLAYABILITY_RECOVERY_TTL_MS = 15000;
  const PLAYABILITY_RECOVERY_ACTION_COOLDOWN_MS = 2200;
  const PLAYABILITY_RECOVERY_MAX_ATTEMPTS = 2;
  const PLAYBACK_RETRY_MAX_ATTEMPTS = 6;
  let playbackRetryTimer = 0;
  let playabilityRecoveryTimer = 0;

  const debugState = window.__onetabtubePlaybackDebug =
      window.__onetabtubePlaybackDebug || {
        events: [],
        lastEvent: null,
        lastPlaybackCheck: null,
        lastPlaybackResult: null,
        lastAutoplayCheck: null,
        lastAutoplayResult: null,
        playbackRetry: null,
        playabilityRecovery: null,
      };
  window.__onetabtubeTransitionDebug = debugState;

  function currentVideoId() {
    try {
      return new URL(location.href).searchParams.get('v');
    } catch (e) {
      return null;
    }
  }

  function isWatchPage() {
    try {
      const url = new URL(location.href);
      return url.pathname === '/watch' && !!url.searchParams.get('v');
    } catch (e) {
      return false;
    }
  }

  function safeParse(rawValue) {
    if (!rawValue) {
      return null;
    }
    try {
      return JSON.parse(rawValue);
    } catch (e) {
      return null;
    }
  }

  function recordDebug(event, detail) {
    try {
      const entry = {
        at: Date.now(),
        event,
        href: location.href,
        videoId: currentVideoId(),
        detail: detail || null,
      };
      debugState.events.push(entry);
      if (debugState.events.length > 80) {
        debugState.events.shift();
      }
      debugState.lastEvent = entry;
    } catch (e) {}
  }

  function textFromNode(node) {
    if (!node) {
      return '';
    }
    return String(node.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function isLikelyVisible(node) {
    if (!node || !node.isConnected) {
      return false;
    }
    try {
      const style = window.getComputedStyle(node);
      if (!style || style.display === 'none' || style.visibility === 'hidden'
          || style.opacity === '0') {
        return false;
      }
      const rect = node.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    } catch (e) {
      return true;
    }
  }

  function findPlayabilityErrorText() {
    const selectors = [
      'ytm-player-error-message-renderer',
      'ytd-player-error-message-renderer',
      '.yt-player-error-message-renderer',
      '.yt-playability-error-supported-renderers',
      '[data-layer="4"] .message',
    ];
    for (const selector of selectors) {
      for (const node of document.querySelectorAll(selector)) {
        if (!isLikelyVisible(node)) {
          continue;
        }
        const text = textFromNode(node);
        if (text) {
          return text;
        }
      }
    }
    return '';
  }

  function getPlayabilitySnapshot() {
    const status =
        String(window.ytInitialPlayerResponse?.playabilityStatus?.status || '');
    const reason = String(
        window.ytInitialPlayerResponse?.playabilityStatus?.reason
        || window.ytInitialPlayerResponse?.playabilityStatus?.messages?.[0]
        || '');
    const errorText = findPlayabilityErrorText();
    const video = document.querySelector('video');
    return {
      status,
      reason: reason.replace(/\s+/g, ' ').trim(),
      errorText,
      hasVideo: !!video,
      paused: !!video?.paused,
      readyState: Number(video?.readyState || 0),
    };
  }

  function clearPlaybackRetryTimer() {
    if (!playbackRetryTimer) {
      return;
    }
    clearTimeout(playbackRetryTimer);
    playbackRetryTimer = 0;
  }

  function clearPlayabilityRecoveryTimer() {
    if (!playabilityRecoveryTimer) {
      return;
    }
    clearTimeout(playabilityRecoveryTimer);
    playabilityRecoveryTimer = 0;
  }

  function resetPlayabilityRecoveryState() {
    clearPlayabilityRecoveryTimer();
    debugState.playabilityRecovery = null;
    try {
      sessionStorage.removeItem(PLAYABILITY_RECOVERY_STORAGE_KEY);
    } catch (e) {}
  }

  function loadPlayabilityRecoveryState() {
    const parsed =
        safeParse(sessionStorage.getItem(PLAYABILITY_RECOVERY_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const firstSeenAt = Number(parsed.firstSeenAt || 0);
    const lastBlockedAt = Number(parsed.lastBlockedAt || firstSeenAt || 0);
    const referenceAt = Math.max(firstSeenAt, lastBlockedAt);
    if (!referenceAt || Date.now() - referenceAt > PLAYABILITY_RECOVERY_TTL_MS) {
      resetPlayabilityRecoveryState();
      return null;
    }
    return parsed;
  }

  function persistPlayabilityRecoveryState(state) {
    if (!state) {
      return;
    }
    try {
      sessionStorage.setItem(
          PLAYABILITY_RECOVERY_STORAGE_KEY, JSON.stringify(state));
    } catch (e) {}
  }

  function clickFirst(selectors) {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (!element) {
        continue;
      }
      try {
        element.click();
        return selector;
      } catch (e) {}
    }
    return null;
  }

  function isPlaybackHealthy(video) {
    return !!video && !video.paused && Number(video.readyState || 0) >= 2
        && !video.muted && Number(video.volume || 0) > 0;
  }

  function shouldAttemptPlayback(video) {
    if (!video) {
      return true;
    }
    return video.paused || video.muted
        || !Number.isFinite(video.volume) || Number(video.volume || 0) < 0.95
        || Number(video.readyState || 0) < 2;
  }

  function schedulePlaybackRetry(reason) {
    if (!isWatchPage()) {
      return;
    }
    const currentId = currentVideoId();
    if (!currentId) {
      return;
    }
    const retryState = debugState.playbackRetry || {
      videoId: currentId,
      attempts: 0,
    };
    if (retryState.videoId !== currentId) {
      retryState.videoId = currentId;
      retryState.attempts = 0;
    }
    if (retryState.attempts >= PLAYBACK_RETRY_MAX_ATTEMPTS) {
      return;
    }
    retryState.attempts += 1;
    retryState.reason = reason || 'unknown';
    retryState.at = Date.now();
    debugState.playbackRetry = retryState;
    recordDebug('playback_retry_scheduled', retryState);
    clearPlaybackRetryTimer();
    playbackRetryTimer = setTimeout(() => {
      playbackRetryTimer = 0;
      ensureCurrentVideoPlayback('retry_' + (reason || 'unknown'));
    }, retryState.attempts < 3 ? 180 : 320);
  }

  function saveForegroundPlaybackState(reason) {
    if (!isWatchPage()) {
      return null;
    }
    const video = document.querySelector('video');
    const videoId = currentVideoId();
    if (!video || !videoId || video.paused || video.ended) {
      return null;
    }
    const state = {
      capturedAt: Date.now(),
      reason: reason || 'unknown',
      videoId,
      muted: !!video.muted,
      volume: Number.isFinite(video.volume) ? video.volume : 1,
    };
    try {
      sessionStorage.setItem(
          FOREGROUND_RESUME_STORAGE_KEY, JSON.stringify(state));
    } catch (e) {}
    recordDebug('foreground_state_saved', state);
    return state;
  }

  function clearForegroundPlaybackState() {
    try {
      sessionStorage.removeItem(FOREGROUND_RESUME_STORAGE_KEY);
    } catch (e) {}
  }

  function loadForegroundPlaybackState() {
    const parsed =
        safeParse(sessionStorage.getItem(FOREGROUND_RESUME_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const capturedAt = Number(parsed.capturedAt || 0);
    if (!capturedAt || Date.now() - capturedAt > FOREGROUND_RESUME_TTL_MS) {
      clearForegroundPlaybackState();
      return null;
    }
    return parsed;
  }

  function schedulePlayabilityRecovery(reason, snapshot) {
    if (!isWatchPage() || !snapshot) {
      return false;
    }
    if (!snapshot.errorText && (!snapshot.status || snapshot.status === 'OK')) {
      return false;
    }
    const currentId = currentVideoId();
    if (!currentId) {
      return false;
    }
    const recoveryState = (debugState.playabilityRecovery
        || loadPlayabilityRecoveryState() || {
             videoId: currentId,
             attempts: 0,
             firstSeenAt: Date.now(),
             lastNavigationAt: 0,
           });
    if (recoveryState.videoId !== currentId) {
      recoveryState.videoId = currentId;
      recoveryState.attempts = 0;
      recoveryState.firstSeenAt = Date.now();
      recoveryState.lastNavigationAt = 0;
    }
    recoveryState.reason = reason || 'unknown';
    recoveryState.lastBlockedAt = Date.now();
    recoveryState.lastStatus = snapshot.status || '';
    recoveryState.lastErrorText = snapshot.errorText || snapshot.reason || '';
    recoveryState.lastReadyState = Number(snapshot.readyState || 0);
    debugState.playabilityRecovery = recoveryState;
    persistPlayabilityRecoveryState(recoveryState);
    if (recoveryState.attempts >= PLAYABILITY_RECOVERY_MAX_ATTEMPTS) {
      recordDebug('playability_recovery_aborted', recoveryState);
      return false;
    }
    const lastNavigationAt = Number(recoveryState.lastNavigationAt || 0);
    if (lastNavigationAt
        && Date.now() - lastNavigationAt
            < PLAYABILITY_RECOVERY_ACTION_COOLDOWN_MS) {
      recordDebug('playability_recovery_cooldown', {
        reason: recoveryState.reason,
        videoId: recoveryState.videoId,
        attempts: recoveryState.attempts,
        delaySinceLastNavigationMs: Date.now() - lastNavigationAt,
      });
      return false;
    }
    if (playabilityRecoveryTimer) {
      return false;
    }
    recordDebug('playability_recovery_scheduled', {
      reason: recoveryState.reason,
      videoId: recoveryState.videoId,
      attempts: recoveryState.attempts,
      status: recoveryState.lastStatus,
      errorText: recoveryState.lastErrorText,
    });
    playabilityRecoveryTimer = setTimeout(() => {
      playabilityRecoveryTimer = 0;
      const activeState = debugState.playabilityRecovery;
      const activeVideoId = currentVideoId();
      if (!activeState || !activeVideoId || activeState.videoId !== activeVideoId) {
        resetPlayabilityRecoveryState();
        return;
      }
      const activeSnapshot = getPlayabilitySnapshot();
      if (!activeSnapshot.errorText
          && (!activeSnapshot.status || activeSnapshot.status === 'OK')) {
        resetPlayabilityRecoveryState();
        return;
      }
      activeState.attempts = Number(activeState.attempts || 0) + 1;
      activeState.lastAttemptAt = Date.now();
      activeState.lastBlockedAt = Date.now();
      activeState.lastNavigationAt = Date.now();
      activeState.lastStatus = activeSnapshot.status || '';
      activeState.lastErrorText =
          activeSnapshot.errorText || activeSnapshot.reason || '';
      activeState.lastReadyState = Number(activeSnapshot.readyState || 0);
      debugState.playabilityRecovery = activeState;
      persistPlayabilityRecoveryState(activeState);
      recordDebug('playability_recovery_manual_required', {
        reason: activeState.reason,
        videoId: activeState.videoId,
        attempts: activeState.attempts,
        status: activeState.lastStatus,
        errorText: activeState.lastErrorText,
      });
    }, 850);
    return true;
  }

  function ensureCurrentVideoPlayback(reason) {
    if (!isWatchPage()) {
      return false;
    }
    const currentId = currentVideoId();
    if (!currentId) {
      resetPlayabilityRecoveryState();
      return false;
    }
    const snapshot = getPlayabilitySnapshot();
    debugState.lastPlaybackCheck = {
      reason: reason || 'unknown',
      currentId,
      snapshot,
    };
    debugState.lastAutoplayCheck = debugState.lastPlaybackCheck;
    recordDebug('playback_check', debugState.lastPlaybackCheck);
    if ((snapshot.status && snapshot.status !== 'OK') || snapshot.errorText) {
      debugState.lastPlaybackResult = {
        action: 'blocked',
        reason: reason || 'unknown',
        currentId,
        snapshot,
      };
      debugState.lastAutoplayResult = debugState.lastPlaybackResult;
      recordDebug('playback_blocked', debugState.lastPlaybackResult);
      schedulePlayabilityRecovery(reason || 'playback_blocked', snapshot);
      return false;
    }
    resetPlayabilityRecoveryState();
    const video = document.querySelector('video');
    if (!video) {
      debugState.lastPlaybackResult = {
        action: 'retry_no_video',
        reason: reason || 'unknown',
        currentId,
      };
      debugState.lastAutoplayResult = debugState.lastPlaybackResult;
      recordDebug('playback_no_video', debugState.lastPlaybackResult);
      schedulePlaybackRetry(reason || 'no_video');
      return false;
    }
    if (!shouldAttemptPlayback(video)) {
      clearPlaybackRetryTimer();
      debugState.playbackRetry = null;
      debugState.lastPlaybackResult = {
        action: 'stable',
        reason: reason || 'unknown',
        currentId,
        readyState: video.readyState,
        muted: video.muted,
        volume: video.volume,
      };
      debugState.lastAutoplayResult = debugState.lastPlaybackResult;
      recordDebug('playback_stable', debugState.lastPlaybackResult);
      return true;
    }

    try {
      video.defaultMuted = false;
      video.muted = false;
      if (!Number.isFinite(video.volume) || video.volume < 0.95) {
        video.volume = 1;
      }
    } catch (e) {}

    clickFirst([
      '.ytp-unmute',
      '.ytp-mute-button[aria-label*="Unmute"]',
      'button[aria-label*="Unmute"]',
      'button[title*="Unmute"]',
    ]);

    try {
      video.defaultMuted = false;
      video.muted = false;
      if (!Number.isFinite(video.volume) || video.volume < 0.95) {
        video.volume = 1;
      }
    } catch (e) {}

    if (video.paused) {
      clickFirst([
        '.ytp-large-play-button',
        '.ytp-play-button',
        'button[aria-label*="Play"]',
        'button[aria-label*="play"]',
      ]);
    }

    try {
      const playResult =
          typeof video.play === 'function' ? video.play() : null;
      if (playResult && typeof playResult.catch === 'function') {
        playResult.catch(error => {
          recordDebug('playback_play_rejected', {
            reason: reason || 'unknown',
            currentId,
            error: String(error && error.message || error || ''),
          });
          schedulePlaybackRetry(reason || 'play_rejected');
        });
      }
    } catch (e) {
      recordDebug('playback_play_threw', {
        reason: reason || 'unknown',
        currentId,
        error: String(e && e.message || e || ''),
      });
      schedulePlaybackRetry(reason || 'play_threw');
      return false;
    }

    if (isPlaybackHealthy(video)) {
      clearPlaybackRetryTimer();
      debugState.playbackRetry = null;
      debugState.lastPlaybackResult = {
        action: 'ready',
        reason: reason || 'unknown',
        currentId,
        readyState: video.readyState,
        muted: video.muted,
        volume: video.volume,
      };
      debugState.lastAutoplayResult = debugState.lastPlaybackResult;
      recordDebug('playback_ready', debugState.lastPlaybackResult);
      return true;
    }

    debugState.lastPlaybackResult = {
      action: 'retry_not_ready',
      reason: reason || 'unknown',
      currentId,
      paused: video.paused,
      readyState: video.readyState,
      muted: video.muted,
      volume: video.volume,
    };
    debugState.lastAutoplayResult = debugState.lastPlaybackResult;
    recordDebug('playback_pending', debugState.lastPlaybackResult);
    schedulePlaybackRetry(reason || 'not_ready');
    return false;
  }

  function ensureForegroundPlayback(reason) {
    const state = loadForegroundPlaybackState();
    const currentId = currentVideoId();
    if (!state || !currentId || state.videoId !== currentId) {
      return false;
    }
    recordDebug('foreground_resume_attempt', {
      reason: reason || 'unknown',
      currentId,
    });
    const restored =
        ensureCurrentVideoPlayback((reason || 'unknown') + '_foreground');
    if (restored) {
      clearForegroundPlaybackState();
    }
    return restored;
  }

  function observeCurrentVideo() {
    if (!isWatchPage()) {
      return false;
    }
    const video = document.querySelector('video');
    if (!video) {
      return false;
    }
    if (video.__onetabtubePlaybackObserved) {
      return isPlaybackHealthy(video);
    }
    video.__onetabtubePlaybackObserved = true;

    const handleReady = () => {
      if (loadForegroundPlaybackState() || shouldAttemptPlayback(video)) {
        ensureCurrentVideoPlayback('video_event');
      }
    };

    video.addEventListener('loadeddata', handleReady, true);
    video.addEventListener('playing', () => {
      clearPlaybackRetryTimer();
      debugState.playbackRetry = null;
      resetPlayabilityRecoveryState();
      recordDebug('video_playing', {
        currentId: currentVideoId(),
        readyState: video.readyState,
        muted: video.muted,
        volume: video.volume,
      });
    }, true);

    return isPlaybackHealthy(video);
  }

  function maybeAssistCurrentPage(reason) {
    if (!isWatchPage()) {
      return false;
    }
    const videoHealthy = observeCurrentVideo();
    if (ensureForegroundPlayback(reason || 'resume')) {
      return true;
    }
    const video = document.querySelector('video');
    if (videoHealthy && video && !shouldAttemptPlayback(video)) {
      return true;
    }
    return ensureCurrentVideoPlayback(reason || 'page_ready');
  }

  maybeAssistCurrentPage('initial');
  window.__onetabtubeEnsurePlayback =
      reason => ensureCurrentVideoPlayback(reason || 'manual');
  window.__onetabtubeEnsureAudible =
      reason => ensureCurrentVideoPlayback(reason || 'manual');
  window.__onetabtubeEnsureAutoplay =
      reason => ensureCurrentVideoPlayback(reason || 'manual');
  window.__onetabtubeRecoverPlayability =
      reason => schedulePlayabilityRecovery(
          reason || 'manual', getPlayabilitySnapshot());

  document.addEventListener(
      'DOMContentLoaded', () => maybeAssistCurrentPage('dom_content_loaded'),
      true);
  document.addEventListener(
      'yt-navigate-finish', () => maybeAssistCurrentPage('yt_navigate_finish'),
      true);
  window.addEventListener(
      'pageshow', () => ensureForegroundPlayback('pageshow'), true);
  window.addEventListener('focus', () => ensureForegroundPlayback('focus'), true);
  window.addEventListener(
      'blur', () => saveForegroundPlaybackState('blur'), true);
  window.addEventListener(
      'pagehide', () => saveForegroundPlaybackState('pagehide'), true);
  (document._addEventListener || document.addEventListener).call(
      document,
      'freeze',
      () => saveForegroundPlaybackState('freeze'),
      true);
  (document._addEventListener || document.addEventListener).call(
      document,
      'resume',
      () => ensureForegroundPlayback('resume_event'),
      true);
}());
)OTBPLAY";

[[maybe_unused]] constexpr char16_t kYoutubeTransitionOptimization[] =
    uR"OTB(
(function() {
  if (window.__onetabtubeTransitionOptimizationInstalled) {
    return;
  }
  window.__onetabtubeTransitionOptimizationInstalled = true;

  const preconnected = new Set();
  const prefetched = new Set();
  const preloadedImages = new Set();
  const warmedMediaUrls = new Set();
  const warmedThumbnails = new Set();
  const prefetchedMediaByHref = new Map();
  const prefetchedShellByHref = new Map();
  const warmVideoHandles = new Map();
  const lastWarmAtByUrl = new Map();
  const fetchInFlightByHref = new Set();
  const AUTOPLAY_STORAGE_KEY = '__onetabtubeAutoplayIntent';
  const AUTOPLAY_INTENT_TTL_MS = 15000;
  const VIDEO_PRESENTATION_STORAGE_KEY = '__onetabtubeVideoPresentationIntent';
  const VIDEO_PRESENTATION_INTENT_TTL_MS = 15000;
  const VIDEO_PRESENTATION_CARRY_STORAGE_KEY =
      '__onetabtubeVideoPresentationCarry';
  const VIDEO_PRESENTATION_CARRY_TTL_MS = 15000;
  const FOREGROUND_RESUME_STORAGE_KEY = '__onetabtubeForegroundPlayback';
  const FOREGROUND_RESUME_TTL_MS = 30000;
  const PLAYABILITY_RECOVERY_STORAGE_KEY = '__onetabtubePlayabilityRecovery';
  const PLAYABILITY_RECOVERY_TTL_MS = 15000;
  const PLAYABILITY_RECOVERY_ACTION_COOLDOWN_MS = 2200;
  const PLAYABILITY_RECOVERY_MAX_ATTEMPTS = 2;
  const PREPARED_SHELL_STORAGE_KEY = '__onetabtubePreparedShell';
  const PREPARED_SHELL_TTL_MS = 15000;
  const PAGE_REVEAL_TIMEOUT_MS = 4200;
  const AUTOPLAY_CALL_COOLDOWN_MS = 280;
  // Re-enable only the page-acceleration warm path. Keep page-reveal and
  // playback/presentation helpers disabled so PiP/control behavior stays on
  // the currently stable path.
  const ENABLE_TRANSITION_WARM = true;
  const ENABLE_TRANSITION_PAGE_REVEAL = false;
  let warmTimer = 0;
  let autoplayRetryTimer = 0;
  let audibleRetryTimer = 0;
  let playabilityRecoveryTimer = 0;
  let pageRevealCheckTimer = 0;
  let pageRevealFallbackTimer = 0;
  let transitionInFlight = false;
  let activeVideoId = null;
  let speculationRulesScript = null;
  let warmObserver = null;
  let pageRevealObserver = null;
  let pageRevealOverlay = null;
  const warmState = window.__onetabtubeTransitionWarmState = {
    attempts: 0,
    successes: 0,
    lastReason: null,
    lastTargetHref: null,
    lastPrefetchAt: 0,
    lastMediaWarmAt: 0,
    lastWarmResult: "idle",
    lastMediaUrl: null,
    lastFetchResult: "idle",
    lastFetchAt: 0,
    lastFetchMediaCount: 0,
    lastFetchError: null,
  };
  const debugState = window.__onetabtubeTransitionDebug =
      window.__onetabtubeTransitionDebug || {
        events: [],
        lastEvent: null,
        lastAutoplayCheck: null,
        lastAutoplayDispatch: null,
        lastAutoplayResult: null,
        audibleRetry: null,
        playabilityRecovery: null,
        preparedShell: null,
        pageReveal: null,
      };
  const pageRevealState = window.__onetabtubePageRevealState =
      window.__onetabtubePageRevealState || {
        active: false,
        videoId: null,
        href: null,
        holdStartedAt: 0,
        holdStartedWallAt: 0,
        visualRevealAt: 0,
        visualRevealWallAt: 0,
        revealAt: 0,
        revealWallAt: 0,
        reason: null,
        fallback: false,
        lastReadiness: null,
        overlayReady: false,
      };

  function currentVideoId() {
    try {
      return new URL(location.href).searchParams.get('v');
    } catch (e) {
      return null;
    }
  }

  function recordDebug(event, detail) {
    try {
      const entry = {
        at: Date.now(),
        event,
        href: location.href,
        videoId: currentVideoId(),
        detail: detail || null,
      };
      debugState.events.push(entry);
      if (debugState.events.length > 80) {
        debugState.events.shift();
      }
      debugState.lastEvent = entry;
    } catch (e) {}
  }

  function safeParse(rawValue) {
    if (!rawValue) {
      return null;
    }
    try {
      return JSON.parse(rawValue);
    } catch (e) {
      return null;
    }
  }

  function toAbsolute(rawHref) {
    try {
      return new URL(String(rawHref), location.href).href;
    } catch (e) {
      return null;
    }
  }

  function canonicalizeWatchHref(rawHref) {
    const absoluteHref = toAbsolute(rawHref);
    if (!absoluteHref) {
      return null;
    }
    try {
      const url = new URL(absoluteHref);
      if (url.pathname !== '/watch') {
        return absoluteHref;
      }
      const videoId = url.searchParams.get('v');
      if (!videoId) {
        return absoluteHref;
      }
      const canonicalUrl = new URL('/watch', location.origin);
      canonicalUrl.searchParams.set('v', videoId);
      const preservedParams = [
        'list',
        'index',
        'start_radio',
        'pp',
        't',
        'time_continue',
        'feature',
        'si',
      ];
      for (const param of preservedParams) {
        const value = url.searchParams.get(param);
        if (value) {
          canonicalUrl.searchParams.set(param, value);
        }
      }
      try {
        const currentUrl = new URL(location.href);
        if (currentUrl.pathname === '/watch') {
          for (const param of ['list', 'start_radio', 'pp']) {
            if (canonicalUrl.searchParams.has(param)) {
              continue;
            }
            const currentValue = currentUrl.searchParams.get(param);
            if (currentValue) {
              canonicalUrl.searchParams.set(param, currentValue);
            }
          }
        }
      } catch (e) {}
      return canonicalUrl.href;
    } catch (e) {
      return absoluteHref;
    }
  }

  function extractVideoId(rawHref) {
    try {
      return new URL(String(rawHref), location.href).searchParams.get('v');
    } catch (e) {
      return null;
    }
  }

  function decodeHtmlEntities(value) {
    if (!value) {
      return '';
    }
    try {
      const textarea = document.createElement('textarea');
      textarea.innerHTML = String(value);
      return String(textarea.value || '');
    } catch (e) {
      return String(value || '');
    }
  }

  function normalizePreparedText(value) {
    return decodeHtmlEntities(String(value || ''))
        .replace(/\\"/g, '"')
        .replace(/\\u0026/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\s+/g, ' ')
        .trim();
  }

  function preloadImage(url) {
    if (!url || preloadedImages.has(url)) {
      return;
    }
    preloadedImages.add(url);
    try {
      const link = document.createElement('link');
      link.rel = 'preload';
      link.as = 'image';
      link.href = url;
      (document.head || document.documentElement).appendChild(link);
    } catch (e) {}
  }

  function extractPreparedShell(rawText, absoluteHref) {
    const videoId = extractVideoId(absoluteHref);
    if (!absoluteHref || !videoId) {
      return null;
    }
    const normalizedText = normalizeSerializedText(rawText);
    const pick = patterns => {
      for (const pattern of patterns) {
        const match = normalizedText.match(pattern);
        const value = normalizePreparedText(match?.[1] || '');
        if (value) {
          return value;
        }
      }
      return '';
    };
    const title = pick([
      /<meta[^>]+property=["']og:title["'][^>]+content=["']([^"]+)["']/i,
      /<meta[^>]+name=["']title["'][^>]+content=["']([^"]+)["']/i,
      /"title":"([^"]+)"/i,
    ]);
    const owner = pick([
      /"ownerChannelName":"([^"]+)"/i,
      /"author":"([^"]+)"/i,
      /"shortBylineText":\{"runs":\[\{"text":"([^"]+)"/i,
    ]);
    const thumbnailUrl = 'https://i.ytimg.com/vi/' + videoId + '/hq720.jpg';
    const shell = {
      href: absoluteHref,
      videoId,
      title: title || 'Loading video',
      owner: owner || 'YouTube',
      thumbnailUrl,
      preparedAt: Date.now(),
      source: 'prefetch_html',
    };
    return shell;
  }

  function primePreparedShell(shell) {
    if (!shell) {
      return;
    }
    if (shell.thumbnailUrl) {
      try {
        primeConnection(new URL(shell.thumbnailUrl, location.href).origin);
      } catch (e) {}
      preloadImage(shell.thumbnailUrl);
    }
  }

  function mergePreparedShell(baseShell, overrideShell) {
    if (!baseShell && !overrideShell) {
      return null;
    }
    return {
      ...(baseShell || {}),
      ...(overrideShell || {}),
      href: overrideShell?.href || baseShell?.href || null,
      videoId: overrideShell?.videoId || baseShell?.videoId || null,
      title: overrideShell?.title || baseShell?.title || '',
      owner: overrideShell?.owner || baseShell?.owner || '',
      thumbnailUrl:
          overrideShell?.thumbnailUrl || baseShell?.thumbnailUrl || null,
      preparedAt:
          Math.max(
              Number(baseShell?.preparedAt || 0),
              Number(overrideShell?.preparedAt || 0),
              Date.now()),
      source: overrideShell?.source || baseShell?.source || 'unknown',
    };
  }

  function persistPreparedShell(shell) {
    if (!shell || !shell.videoId || !shell.href) {
      return;
    }
    const storedShell = {
      href: shell.href,
      videoId: shell.videoId,
      title: shell.title || '',
      owner: shell.owner || '',
      thumbnailUrl: shell.thumbnailUrl || '',
      preparedAt: Number(shell.preparedAt || Date.now()),
      source: shell.source || 'unknown',
    };
    debugState.preparedShell = storedShell;
    prefetchedShellByHref.set(storedShell.href, storedShell);
    primePreparedShell(storedShell);
    try {
      sessionStorage.setItem(
          PREPARED_SHELL_STORAGE_KEY, JSON.stringify(storedShell));
    } catch (e) {}
    recordDebug('prepared_shell_saved', {
      href: storedShell.href,
      videoId: storedShell.videoId,
      title: storedShell.title,
      owner: storedShell.owner,
      source: storedShell.source,
    });
  }

  function clearPreparedShell() {
    debugState.preparedShell = null;
    try {
      sessionStorage.removeItem(PREPARED_SHELL_STORAGE_KEY);
    } catch (e) {}
  }

  function loadPreparedShell() {
    const parsed = safeParse(sessionStorage.getItem(PREPARED_SHELL_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const preparedAt = Number(parsed.preparedAt || 0);
    if (!preparedAt || Date.now() - preparedAt > PREPARED_SHELL_TTL_MS) {
      clearPreparedShell();
      return null;
    }
    return parsed;
  }

  function loadPlayabilityRecoveryState() {
    const parsed = safeParse(
        sessionStorage.getItem(PLAYABILITY_RECOVERY_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const firstSeenAt = Number(parsed.firstSeenAt || 0);
    const lastBlockedAt = Number(parsed.lastBlockedAt || 0);
    const referenceAt = Math.max(firstSeenAt, lastBlockedAt);
    if (!referenceAt || Date.now() - referenceAt > PLAYABILITY_RECOVERY_TTL_MS) {
      try {
        sessionStorage.removeItem(PLAYABILITY_RECOVERY_STORAGE_KEY);
      } catch (e) {}
      return null;
    }
    return parsed;
  }

  function persistPlayabilityRecoveryState(state) {
    if (!state) {
      return;
    }
    try {
      sessionStorage.setItem(
          PLAYABILITY_RECOVERY_STORAGE_KEY, JSON.stringify(state));
    } catch (e) {}
  }

  function isFastPathCandidate(rawHref) {
    const absoluteHref = canonicalizeWatchHref(rawHref);
    if (!absoluteHref) return false;
    const url = new URL(absoluteHref);
    if (!/^(www\.|m\.)?youtube\.com$/.test(url.host) && url.host !== 'youtube.com') {
      return false;
    }
    if (url.pathname !== '/watch') return false;
    const nextId = url.searchParams.get('v');
    if (!nextId) return false;
    if (url.searchParams.has('list')) return false;
    return nextId !== currentVideoId();
  }

  function primeConnection(origin) {
    if (!origin || preconnected.has(origin)) return;
    preconnected.add(origin);
    const link = document.createElement('link');
    link.rel = 'preconnect';
    link.href = origin;
    document.head.appendChild(link);
  }

  function primeCurrentMediaOrigin() {
    const video = document.querySelector('video');
    const mediaUrl = video?.currentSrc || video?.src;
    if (!mediaUrl) return;
    try {
      const url = new URL(mediaUrl, location.href);
      if (/googlevideo\.com$/i.test(url.host)) {
        primeConnection(url.origin);
      }
    } catch (e) {}
  }

  function normalizeSerializedText(rawText) {
    if (!rawText) return '';
    return String(rawText)
        .replace(/\\u0026/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\//g, '/');
  }

  function primeMediaOriginsFromText(rawText) {
    const normalizedText = normalizeSerializedText(rawText);
    if (!normalizedText) return;
    const seenHosts = new Set();
    const hostMatches =
        normalizedText.match(/[a-z0-9-]+---[a-z0-9-]+\.googlevideo\.com/gi) || [];
    for (const host of hostMatches) {
      const normalizedHost = String(host).toLowerCase();
      if (seenHosts.has(normalizedHost)) continue;
      seenHosts.add(normalizedHost);
      primeConnection('https://' + normalizedHost);
      if (seenHosts.size >= 4) break;
    }
  }

  function extractMediaUrls(rawText) {
    const normalizedText = normalizeSerializedText(rawText);
    if (!normalizedText) return [];
    const candidates = [];
    const seen = new Set();
    const matches =
        normalizedText.match(/https?:\/\/[^"'\s]+googlevideo\.com\/videoplayback[^"'\s]+/gi)
        || [];
    for (const match of matches) {
      try {
        const url = new URL(match);
        if (seen.has(url.href)) continue;
        seen.add(url.href);
        candidates.push(url.href);
      } catch (e) {}
      if (candidates.length >= 4) break;
    }
    return candidates;
  }

  function disposeWarmVideo(mediaUrl) {
    const handle = warmVideoHandles.get(mediaUrl);
    if (!handle) {
      return;
    }
    warmVideoHandles.delete(mediaUrl);
    clearTimeout(handle.cleanupTimer);
    try {
      handle.element.pause();
      handle.element.removeAttribute('src');
      handle.element.load();
      handle.element.remove();
    } catch (e) {}
  }

  function disposeAllWarmVideos() {
    for (const mediaUrl of Array.from(warmVideoHandles.keys())) {
      disposeWarmVideo(mediaUrl);
    }
  }

  function warmMediaUrl(mediaUrl, forceRefresh) {
    if (!mediaUrl) {
      return;
    }
    const now = Date.now();
    const lastWarmAt = lastWarmAtByUrl.get(mediaUrl) || 0;
    if (!forceRefresh && now - lastWarmAt < 1200) {
      return;
    }
    lastWarmAtByUrl.set(mediaUrl, now);
    warmedMediaUrls.add(mediaUrl);
    warmState.lastMediaWarmAt = now;
    warmState.lastMediaUrl = mediaUrl;
    disposeWarmVideo(mediaUrl);
    try {
      primeConnection(new URL(mediaUrl).origin);
    } catch (e) {}

    try {
      if (typeof fetch === 'function' && typeof AbortController === 'function') {
        const controller = new AbortController();
        fetch(mediaUrl, {
          mode: 'no-cors',
          credentials: 'omit',
          cache: 'force-cache',
          signal: controller.signal,
        }).catch(() => {});
        setTimeout(() => {
          try {
            controller.abort();
          } catch (e) {}
        }, 1400);
      }
    } catch (e) {}

    try {
      const warmVideo = document.createElement('video');
      warmVideo.muted = true;
      warmVideo.defaultMuted = true;
      warmVideo.autoplay = true;
      warmVideo.preload = 'auto';
      warmVideo.playsInline = true;
      warmVideo.style.cssText =
          'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;';
      warmVideo.setAttribute('aria-hidden', 'true');
      warmVideo.src = mediaUrl;
      (document.body || document.documentElement).appendChild(warmVideo);
      warmVideo.load();
      const playResult =
          typeof warmVideo.play === 'function' ? warmVideo.play() : null;
      if (playResult && typeof playResult.catch === 'function') {
        playResult.catch(() => {});
      }
      const cleanupTimer = setTimeout(() => {
        try {
          disposeWarmVideo(mediaUrl);
        } catch (e) {}
      }, 3200);
      warmVideoHandles.set(mediaUrl, {
        element: warmVideo,
        cleanupTimer,
      });
    } catch (e) {}
  }

  function warmCachedTarget(absoluteHref, forceRefresh) {
    if (!absoluteHref) {
      return false;
    }
    const cachedMediaUrls = prefetchedMediaByHref.get(absoluteHref) || [];
    if (!cachedMediaUrls.length) {
      return false;
    }
    for (const mediaUrl of cachedMediaUrls) {
      warmMediaUrl(mediaUrl, forceRefresh);
    }
    return true;
  }

  function fetchTargetPage(absoluteHref) {
    if (!absoluteHref || fetchInFlightByHref.has(absoluteHref)
        || typeof fetch !== 'function') {
      return false;
    }
    fetchInFlightByHref.add(absoluteHref);
    warmState.lastFetchAt = Date.now();
    warmState.lastFetchError = null;
    warmState.lastFetchResult = "fetch_started";
    let controller = null;
    try {
      if (typeof AbortController === 'function') {
        controller = new AbortController();
        setTimeout(() => {
          try {
            controller.abort();
          } catch (e) {}
        }, 2500);
      }
    } catch (e) {
      controller = null;
    }
    fetch(absoluteHref, {
      credentials: 'include',
      mode: 'same-origin',
      cache: 'force-cache',
      signal: controller ? controller.signal : undefined,
    }).then(response => response.text())
        .then(text => {
          primeMediaOriginsFromText(text);
          const preparedShell = extractPreparedShell(text, absoluteHref);
          if (preparedShell) {
            prefetchedShellByHref.set(absoluteHref, preparedShell);
            primePreparedShell(preparedShell);
            debugState.preparedShell = preparedShell;
          }
          const mediaUrls = extractMediaUrls(text);
          prefetchedMediaByHref.set(absoluteHref, mediaUrls);
          warmState.lastFetchMediaCount = mediaUrls.length;
          if (!mediaUrls.length) {
            warmState.lastFetchResult = "fetch_no_media";
            return;
          }
          warmState.lastFetchResult = "fetch_media_ready";
          warmState.successes += 1;
          for (const mediaUrl of mediaUrls) {
            warmMediaUrl(mediaUrl, false);
          }
        })
        .catch(error => {
          warmState.lastFetchResult = "fetch_error";
          warmState.lastFetchError = String(error && error.message || error || '');
        })
        .finally(() => {
          fetchInFlightByHref.delete(absoluteHref);
        });
    return true;
  }

  function runMainWorldWarm(absoluteHref) {
    if (!absoluteHref) {
      return;
    }
    try {
      const runner = document.createElement('script');
      const runnerSource = '(' + function(href) {
        try {
          const root = document.documentElement;
          const now = () => Date.now();
          const state = window.__onetabtubePageWarmState =
              window.__onetabtubePageWarmState || {
                attempts: 0,
                successes: 0,
                lastResult: 'idle',
                lastTargetHref: '',
                lastMediaCount: 0,
                lastMediaUrl: '',
                lastError: '',
                lastPrefetchAtByHref: {},
                lastWarmAtByUrl: {},
              };

          const syncState = () => {
            root.dataset.otbWarmAttempts = String(state.attempts || 0);
            root.dataset.otbWarmSuccesses = String(state.successes || 0);
            root.dataset.otbWarmLastResult = state.lastResult || '';
            root.dataset.otbWarmLastHref = state.lastTargetHref || '';
            root.dataset.otbWarmMediaCount = String(state.lastMediaCount || 0);
            root.dataset.otbWarmLastMediaUrl = state.lastMediaUrl || '';
            root.dataset.otbWarmLastError = String(state.lastError || '')
                .slice(0, 160);
          };

          const normalizeSerializedText = rawText => String(rawText || '')
              .replace(/\\u0026/g, '&')
              .replace(/\\\\u0026/g, '&')
              .replace(/\\\//g, '/');

          const extractMediaUrls = rawText => {
            const normalizedText = normalizeSerializedText(rawText);
            const candidates = [];
            const seen = new Set();
            const matches =
                normalizedText.match(
                    /https?:\/\/[^"'\s]+googlevideo\.com\/videoplayback[^"'\s]+/gi)
                || [];
            for (const match of matches) {
              try {
                const url = new URL(match);
                if (seen.has(url.href)) {
                  continue;
                }
                seen.add(url.href);
                candidates.push(url.href);
              } catch (e) {}
              if (candidates.length >= 4) {
                break;
              }
            }
            return candidates;
          };

          const primeConnection = origin => {
            if (!origin) {
              return;
            }
            const selector = 'link[rel="preconnect"][href="' + origin + '"]';
            if (document.querySelector(selector)) {
              return;
            }
            const link = document.createElement('link');
            link.rel = 'preconnect';
            link.href = origin;
            (document.head || document.documentElement).appendChild(link);
          };

          const warmMediaUrl = mediaUrl => {
            if (!mediaUrl) {
              return;
            }
            const lastWarmAt = state.lastWarmAtByUrl[mediaUrl] || 0;
            if (now() - lastWarmAt < 1200) {
              return;
            }
            state.lastWarmAtByUrl[mediaUrl] = now();
            state.lastMediaUrl = mediaUrl;
            try {
              primeConnection(new URL(mediaUrl).origin);
            } catch (e) {}
            try {
              if (typeof fetch === 'function'
                  && typeof AbortController === 'function') {
                const controller = new AbortController();
                fetch(mediaUrl, {
                  mode: 'no-cors',
                  credentials: 'omit',
                  cache: 'force-cache',
                  signal: controller.signal,
                }).catch(() => {});
                setTimeout(() => {
                  try {
                    controller.abort();
                  } catch (e) {}
                }, 1400);
              }
            } catch (e) {}
            try {
              const warmVideo = document.createElement('video');
              warmVideo.muted = true;
              warmVideo.defaultMuted = true;
              warmVideo.autoplay = true;
              warmVideo.preload = 'auto';
              warmVideo.playsInline = true;
              warmVideo.style.cssText =
                  'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;';
              warmVideo.setAttribute('aria-hidden', 'true');
              warmVideo.src = mediaUrl;
              (document.body || document.documentElement).appendChild(warmVideo);
              warmVideo.load();
              const playResult =
                  typeof warmVideo.play === 'function' ? warmVideo.play() : null;
              if (playResult && typeof playResult.catch === 'function') {
                playResult.catch(() => {});
              }
              setTimeout(() => {
                try {
                  warmVideo.pause();
                  warmVideo.removeAttribute('src');
                  warmVideo.load();
                  warmVideo.remove();
                } catch (e) {}
              }, 3200);
            } catch (e) {}
            syncState();
          };

          const lastPrefetchAt = state.lastPrefetchAtByHref[href] || 0;
          if (now() - lastPrefetchAt < 1200) {
            state.lastResult = 'page_skip_recent';
            syncState();
            return;
          }
          state.lastPrefetchAtByHref[href] = now();
          state.attempts += 1;
          state.lastTargetHref = href;
          state.lastError = '';
          state.lastResult = 'page_prefetch_started';
          syncState();

          fetch(href, {
            credentials: 'include',
            mode: 'same-origin',
            cache: 'force-cache',
          }).then(response => response.text())
              .then(text => {
                const mediaUrls = extractMediaUrls(text);
                state.lastMediaCount = mediaUrls.length;
                if (mediaUrls.length) {
                  state.successes += 1;
                  state.lastResult = 'page_fetched_media';
                } else {
                  state.lastResult = 'page_no_media';
                }
                syncState();
                for (const mediaUrl of mediaUrls) {
                  warmMediaUrl(mediaUrl);
                }
              })
              .catch(error => {
                state.lastResult = 'page_fetch_error';
                state.lastError = String(error && error.message || error || '');
                syncState();
              });
        } catch (error) {
          try {
            const root = document.documentElement;
            root.dataset.otbWarmLastResult = 'page_bridge_error';
            root.dataset.otbWarmLastError =
                String(error && error.message || error || '').slice(0, 160);
          } catch (e) {}
        }
      } + ')(' + JSON.stringify(absoluteHref) + ');';
      if (window.trustedTypes &&
          typeof window.trustedTypes.createPolicy === 'function') {
        const policyName = 'onetabtube-warm';
        let policy = window.__onetabtubeTrustedTypesPolicy || null;
        if (!policy && typeof window.trustedTypes.getPolicy === 'function') {
          try {
            policy = window.trustedTypes.getPolicy(policyName);
          } catch (e) {}
        }
        if (!policy) {
          try {
            policy = window.trustedTypes.createPolicy(policyName, {
              createScript: value => value,
            });
            window.__onetabtubeTrustedTypesPolicy = policy;
          } catch (e) {}
        }
        if (policy && typeof policy.createScript === 'function') {
          runner.textContent = policy.createScript(runnerSource);
        } else {
          runner.textContent = runnerSource;
        }
      } else {
        runner.textContent = runnerSource;
      }
      (document.head || document.documentElement).appendChild(runner);
      runner.remove();
    } catch (e) {
      warmState.lastFetchResult = 'page_bridge_error';
      warmState.lastFetchError = String(e && e.message || e || '');
      recordDebug('page_bridge_error', {
        href: absoluteHref,
        error: warmState.lastFetchError,
      });
    }
  }

  function primeThumbnail(videoId) {
    if (!videoId || warmedThumbnails.has(videoId)) {
      return;
    }
    warmedThumbnails.add(videoId);
    const link = document.createElement('link');
    link.rel = 'preload';
    link.as = 'image';
    link.href = 'https://i.ytimg.com/vi/' + videoId + '/hq720.jpg';
    document.head.appendChild(link);
  }

  function updateSpeculationRules(absoluteHref) {
    if (!absoluteHref || typeof HTMLScriptElement === 'undefined'
        || typeof HTMLScriptElement.supports !== 'function'
        || !HTMLScriptElement.supports('speculationrules')) {
      return;
    }

    const payload = JSON.stringify({
      prefetch: [{source: 'list', urls: [absoluteHref]}],
      prerender: [{source: 'list', urls: [absoluteHref]}],
    });

    if (!speculationRulesScript) {
      speculationRulesScript = document.createElement('script');
      speculationRulesScript.type = 'speculationrules';
      document.head.appendChild(speculationRulesScript);
    }
    if (speculationRulesScript.textContent !== payload) {
      speculationRulesScript.textContent = payload;
    }
  }

  function hasPreparedTarget(absoluteHref) {
    if (!absoluteHref) {
      return false;
    }
    return prefetched.has(absoluteHref) || prefetchedMediaByHref.has(absoluteHref);
  }

  function getInitialDataNextHrefs(limit) {
    const maxResults = Math.max(1, limit || 1);
    const hrefs = [];
    const seen = new Set();
    const currentId = currentVideoId();
    const pushCandidate = rawHref => {
      const absoluteHref = toAbsolute(rawHref);
      if (!absoluteHref || seen.has(absoluteHref) || !isFastPathCandidate(absoluteHref)) {
        return false;
      }
      const videoId = extractVideoId(absoluteHref);
      if (!videoId || videoId === currentId) {
        return false;
      }
      seen.add(absoluteHref);
      hrefs.push(absoluteHref);
      return hrefs.length >= maxResults;
    };

    const collectFromItems = items => {
      if (!Array.isArray(items)) {
        return false;
      }
      for (const item of items) {
        const renderer = item?.videoWithContextRenderer || item?.compactVideoRenderer;
        const rawHref =
            renderer?.navigationEndpoint?.commandMetadata?.webCommandMetadata?.url
            || renderer?.navigationEndpoint?.urlEndpoint?.url;
        if (pushCandidate(rawHref)) {
          return true;
        }
      }
      return false;
    };

    try {
      const contents =
          window.ytInitialData?.contents?.singleColumnWatchNextResults?.results?.results?.contents;
      if (Array.isArray(contents)) {
        for (const content of contents) {
          if (collectFromItems(content?.itemSectionRenderer?.contents)) {
            return hrefs;
          }
        }
      }
    } catch (e) {}

    try {
      const fallbackItems = [];
      const walk = value => {
        if (!value || fallbackItems.length >= maxResults * 3) {
          return;
        }
        if (Array.isArray(value)) {
          for (const item of value) {
            walk(item);
            if (fallbackItems.length >= maxResults * 3) {
              break;
            }
          }
          return;
        }
        if (typeof value !== 'object') {
          return;
        }
        if (value.videoWithContextRenderer || value.compactVideoRenderer) {
          fallbackItems.push(value);
        }
        for (const child of Object.values(value)) {
          walk(child);
          if (fallbackItems.length >= maxResults * 3) {
            break;
          }
        }
      };
      walk(window.ytInitialData);
      collectFromItems(fallbackItems);
    } catch (e) {}

    return hrefs;
  }

  function clearWarmTimer() {
    if (!warmTimer) return;
    clearTimeout(warmTimer);
    warmTimer = 0;
  }

  function clearAutoplayRetryTimer() {
    if (!autoplayRetryTimer) {
      return;
    }
    clearTimeout(autoplayRetryTimer);
    autoplayRetryTimer = 0;
  }

  function clearAudibleRetryTimer() {
    if (!audibleRetryTimer) {
      return;
    }
    clearTimeout(audibleRetryTimer);
    audibleRetryTimer = 0;
  }

  function clearPlayabilityRecoveryTimer() {
    if (!playabilityRecoveryTimer) {
      return;
    }
    clearTimeout(playabilityRecoveryTimer);
    playabilityRecoveryTimer = 0;
  }

  function saveAutoplayIntent(targetHref, reason) {
    const absoluteHref = canonicalizeWatchHref(targetHref);
    const targetVideoId = extractVideoId(absoluteHref);
    if (!absoluteHref || !targetVideoId) {
      return null;
    }
    const existingIntent = loadAutoplayIntent();
    const sameTarget = !!existingIntent
        && existingIntent.targetVideoId === targetVideoId
        && existingIntent.targetHref === absoluteHref;
    const now = Date.now();
    const intent = {
      armedAt: sameTarget ? Number(existingIntent.armedAt || now) : now,
      updatedAt: now,
      reason: reason || 'unknown',
      attemptCount: sameTarget ? Number(existingIntent.attemptCount || 0) : 0,
      targetHref: absoluteHref,
      targetVideoId,
    };
    try {
      sessionStorage.setItem(AUTOPLAY_STORAGE_KEY, JSON.stringify(intent));
    } catch (e) {}
    recordDebug('autoplay_intent_saved', {
      reason: intent.reason,
      targetHref: intent.targetHref,
      targetVideoId: intent.targetVideoId,
    });
    return intent;
  }

  function saveVideoPresentationIntent(targetHref, reason) {
    const absoluteHref = canonicalizeWatchHref(targetHref);
    const targetVideoId = extractVideoId(absoluteHref);
    if (!absoluteHref || !targetVideoId) {
      return null;
    }
    const now = Date.now();
    const intent = {
      armedAt: now,
      updatedAt: now,
      reason: reason || 'unknown',
      targetHref: absoluteHref,
      targetVideoId,
    };
    try {
      sessionStorage.setItem(
          VIDEO_PRESENTATION_STORAGE_KEY, JSON.stringify(intent));
    } catch (e) {}
    recordDebug('video_presentation_intent_saved', {
      reason: intent.reason,
      targetHref: intent.targetHref,
      targetVideoId: intent.targetVideoId,
    });
    return intent;
  }

  function clearAutoplayIntent() {
    clearAutoplayRetryTimer();
    try {
      sessionStorage.removeItem(AUTOPLAY_STORAGE_KEY);
    } catch (e) {}
  }

  function clearVideoPresentationIntent() {
    try {
      sessionStorage.removeItem(VIDEO_PRESENTATION_STORAGE_KEY);
    } catch (e) {}
  }

  function saveCarryForwardVideoPresentation(reason) {
    const video = document.querySelector('video.html5-main-video, video');
    const currentId = currentVideoId();
    if (!video || !currentId || !hasFullscreenPresentation(video)) {
      return null;
    }
    const now = Date.now();
    const intent = {
      armedAt: now,
      updatedAt: now,
      reason: reason || 'unknown',
      sourceHref: canonicalizeWatchHref(location.href),
      sourceVideoId: currentId,
    };
    try {
      sessionStorage.setItem(
          VIDEO_PRESENTATION_CARRY_STORAGE_KEY, JSON.stringify(intent));
    } catch (e) {}
    recordDebug('video_presentation_carry_saved', {
      reason: intent.reason,
      sourceHref: intent.sourceHref,
      sourceVideoId: intent.sourceVideoId,
    });
    return intent;
  }

  function clearCarryForwardVideoPresentation() {
    try {
      sessionStorage.removeItem(VIDEO_PRESENTATION_CARRY_STORAGE_KEY);
    } catch (e) {}
  }

  function loadAutoplayIntent() {
    const parsed = safeParse(sessionStorage.getItem(AUTOPLAY_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const armedAt = Number(parsed.armedAt || 0);
    const updatedAt = Number(parsed.updatedAt || armedAt || 0);
    const referenceAt = Math.max(armedAt, updatedAt);
    if (!armedAt || !referenceAt
        || Date.now() - referenceAt > AUTOPLAY_INTENT_TTL_MS) {
      clearAutoplayIntent();
      return null;
    }
    return parsed;
  }

  function loadVideoPresentationIntent() {
    const parsed = safeParse(sessionStorage.getItem(VIDEO_PRESENTATION_STORAGE_KEY));
    if (!parsed) {
      return null;
    }
    const armedAt = Number(parsed.armedAt || 0);
    const updatedAt = Number(parsed.updatedAt || armedAt || 0);
    const referenceAt = Math.max(armedAt, updatedAt);
    if (!armedAt || !referenceAt
        || Date.now() - referenceAt > VIDEO_PRESENTATION_INTENT_TTL_MS) {
      clearVideoPresentationIntent();
      return null;
    }
    return parsed;
  }

  function loadCarryForwardVideoPresentation() {
    const parsed = safeParse(
        sessionStorage.getItem(VIDEO_PRESENTATION_CARRY_STORAGE_KEY));
    if (!parsed) {
      return null;
    }
    const armedAt = Number(parsed.armedAt || 0);
    const updatedAt = Number(parsed.updatedAt || armedAt || 0);
    const referenceAt = Math.max(armedAt, updatedAt);
    if (!armedAt || !referenceAt
        || Date.now() - referenceAt > VIDEO_PRESENTATION_CARRY_TTL_MS) {
      clearCarryForwardVideoPresentation();
      return null;
    }
    return parsed;
  }

  function persistAutoplayIntent(intent) {
    if (!intent) {
      return;
    }
    intent.updatedAt = Date.now();
    try {
      sessionStorage.setItem(AUTOPLAY_STORAGE_KEY, JSON.stringify(intent));
    } catch (e) {}
  }

  function hasFullscreenPresentation(video) {
    return !!document.fullscreenElement
        || !!document.webkitFullscreenElement
        || !!(video && video.webkitDisplayingFullscreen);
  }

  function requestFocusedVideoPresentation(reason) {
    const video = document.querySelector('video.html5-main-video, video');
    if (!video) {
      return false;
    }
    if (hasFullscreenPresentation(video)) {
      return true;
    }

    const playerContainer = document.getElementById('player-container-id')
        || video.closest?.('#player-container-id, #player, #movie_player, .html5-video-player')
        || video;
    const fullscreenButton = document.querySelector(
        'button.fullscreen-icon, .ytp-fullscreen-button, .fullscreen-icon');
    const requestFullscreenApi =
        playerContainer?.requestFullscreen
        || playerContainer?.webkitRequestFullscreen
        || video.requestFullscreen
        || video.webkitRequestFullscreen
        || video.webkitEnterFullscreen;
    const invokeTarget =
        requestFullscreenApi === video.requestFullscreen
        || requestFullscreenApi === video.webkitRequestFullscreen
        || requestFullscreenApi === video.webkitEnterFullscreen
            ? video
            : playerContainer;
    try {
      if (typeof video.click === 'function') {
        video.click();
      }
    } catch (e) {}
    try {
      if (requestFullscreenApi) {
        const maybePromise = requestFullscreenApi.call(invokeTarget);
        if (maybePromise && typeof maybePromise.catch === 'function') {
          maybePromise.catch(() => {});
        }
        recordDebug('video_presentation_requested', {
          reason: reason || 'unknown',
          strategy: 'request_fullscreen',
        });
        return true;
      }
    } catch (e) {}
    if (isLikelyVisible(fullscreenButton)) {
      try {
        fullscreenButton.click();
        recordDebug('video_presentation_requested', {
          reason: reason || 'unknown',
          strategy: 'fullscreen_button',
        });
        return true;
      } catch (e) {}
    }
    recordDebug('video_presentation_request_failed', {
      reason: reason || 'unknown',
    });
    return false;
  }

  function ensureVideoPresentationForArmedTarget(reason) {
    const intent = loadVideoPresentationIntent();
    const currentId = currentVideoId();
    const video = document.querySelector('video.html5-main-video, video');
    if (intent && currentId && video && intent.targetVideoId === currentId) {
      if (hasFullscreenPresentation(video)) {
        clearVideoPresentationIntent();
        recordDebug('video_presentation_ready', {
          reason: reason || 'unknown',
          currentId,
        });
        return true;
      }
      return requestFocusedVideoPresentation(reason || 'video_presentation');
    }

    const carryIntent = loadCarryForwardVideoPresentation();
    if (!carryIntent || !currentId || !video
        || carryIntent.sourceVideoId === currentId) {
      return false;
    }
    if (hasFullscreenPresentation(video)) {
      clearCarryForwardVideoPresentation();
      recordDebug('video_presentation_carry_ready', {
        reason: reason || 'unknown',
        currentId,
        sourceVideoId: carryIntent.sourceVideoId,
      });
      return true;
    }
    return requestFocusedVideoPresentation(
        reason || 'video_presentation_carry');
  }

  function resetPlayabilityRecoveryState() {
    clearPlayabilityRecoveryTimer();
    debugState.playabilityRecovery = null;
    try {
      sessionStorage.removeItem(PLAYABILITY_RECOVERY_STORAGE_KEY);
    } catch (e) {}
  }

  function isBlockedPlayabilitySnapshot(snapshot) {
    if (!snapshot) {
      return false;
    }
    return !!snapshot.errorText || (!!snapshot.status && snapshot.status !== 'OK');
  }

  function commitCanonicalWatchNavigation(targetHref, reason, options) {
    const absoluteHref = canonicalizeWatchHref(targetHref);
    if (!absoluteHref) {
      return false;
    }
    const navigationOptions = options || {};
    const replaceHistory = !!navigationOptions.replaceHistory;
    const warmTarget = !!navigationOptions.warmTarget;
    const navigationReason = reason || (replaceHistory ? 'watch_replace' : 'watch_assign');
    const preparedShell = mergePreparedShell(
        prefetchedShellByHref.get(absoluteHref), navigationOptions.preparedShell);
    saveAutoplayIntent(absoluteHref, navigationReason);
    if (preparedShell) {
      persistPreparedShell(preparedShell);
    }
    if (warmTarget) {
      prefetchHref(absoluteHref, true);
    }
    transitionInFlight = true;
    clearWarmTimer();
    clearAutoplayRetryTimer();
    clearAudibleRetryTimer();
    resetPlayabilityRecoveryState();
    if (hasPreparedTarget(absoluteHref)) {
      warmState.lastReason = replaceHistory
          ? 'prepared_recovery_commit'
          : 'prepared_click_commit';
      try {
        console.info('OTB_PERF event=next_prepared_click href=' + absoluteHref);
      } catch (e) {}
    }
    warmState.lastReason = replaceHistory ? 'recovery_commit' : 'click_commit';
    recordDebug('watch_navigation_commit', {
      reason: navigationReason,
      href: absoluteHref,
      replaceHistory,
      warmTarget,
      preparedShell: preparedShell ? {
        title: preparedShell.title,
        owner: preparedShell.owner,
        source: preparedShell.source || 'unknown',
      } : null,
    });
    try {
      if (replaceHistory) {
        location.replace(absoluteHref);
      } else {
        location.assign(absoluteHref);
      }
      return true;
    } catch (e) {
      transitionInFlight = false;
      recordDebug('watch_navigation_failed', {
        reason: navigationReason,
        href: absoluteHref,
        replaceHistory,
        error: String(e && e.message || e || ''),
      });
      return false;
    }
  }

  function schedulePlayabilityRecovery(reason, snapshot) {
    const currentId = currentVideoId();
    if (!currentId || !isBlockedPlayabilitySnapshot(snapshot)) {
      return false;
    }
    const currentHref = toAbsolute(location.href) || location.href;
    const canonicalHref = canonicalizeWatchHref(currentHref) || currentHref;
    const persistedState = loadPlayabilityRecoveryState();
    const recoveryState = (debugState.playabilityRecovery
        || persistedState || {
             videoId: currentId,
             href: currentHref,
             canonicalHref,
             attempts: 0,
             firstSeenAt: Date.now(),
             lastNavigationAt: 0,
           });
    if (recoveryState.videoId !== currentId) {
      recoveryState.videoId = currentId;
      recoveryState.href = currentHref;
      recoveryState.canonicalHref = canonicalHref;
      recoveryState.attempts = 0;
      recoveryState.firstSeenAt = Date.now();
      recoveryState.lastNavigationAt = 0;
    }
    recoveryState.reason = reason || 'unknown';
    recoveryState.href = currentHref;
    recoveryState.canonicalHref = canonicalHref;
    recoveryState.lastBlockedAt = Date.now();
    recoveryState.lastStatus = snapshot.status || '';
    recoveryState.lastErrorText = snapshot.errorText || snapshot.reason || '';
    recoveryState.lastReadyState = Number(snapshot.readyState || 0);
    debugState.playabilityRecovery = recoveryState;
    persistPlayabilityRecoveryState(recoveryState);
    if (shouldDeferPlayabilityRecovery(reason, snapshot)) {
      recordDebug('playability_recovery_deferred', {
        reason: recoveryState.reason,
        videoId: recoveryState.videoId,
        attempts: recoveryState.attempts,
        status: recoveryState.lastStatus,
        errorText: recoveryState.lastErrorText,
        holdAgeMs: Math.max(
            0, Date.now() - Number(pageRevealState.holdStartedWallAt || 0)),
      });
      return false;
    }
    if (recoveryState.attempts >= PLAYABILITY_RECOVERY_MAX_ATTEMPTS) {
      recordDebug('playability_recovery_aborted', {
        reason: recoveryState.reason,
        videoId: recoveryState.videoId,
        attempts: recoveryState.attempts,
        status: recoveryState.lastStatus,
      });
      clearAutoplayIntent();
      return false;
    }
    const lastNavigationAt = Number(recoveryState.lastNavigationAt || 0);
    if (lastNavigationAt
        && Date.now() - lastNavigationAt < PLAYABILITY_RECOVERY_ACTION_COOLDOWN_MS) {
      recordDebug('playability_recovery_cooldown', {
        reason: recoveryState.reason,
        videoId: recoveryState.videoId,
        attempts: recoveryState.attempts,
        status: recoveryState.lastStatus,
        delaySinceLastNavigationMs: Date.now() - lastNavigationAt,
      });
      return false;
    }
    if (playabilityRecoveryTimer) {
      return false;
    }
    const delayMs = canonicalHref !== currentHref ? 140 : 850;
    recordDebug('playability_recovery_scheduled', {
      reason: recoveryState.reason,
      videoId: recoveryState.videoId,
      attempts: recoveryState.attempts,
      delayMs,
      currentHref,
      canonicalHref,
      status: recoveryState.lastStatus,
      errorText: recoveryState.lastErrorText,
    });
    playabilityRecoveryTimer = setTimeout(() => {
      playabilityRecoveryTimer = 0;
      const activeState = debugState.playabilityRecovery;
      const activeVideoId = currentVideoId();
      if (!activeState || !activeVideoId || activeState.videoId !== activeVideoId) {
        resetPlayabilityRecoveryState();
        return;
      }
      const activeSnapshot = getPlayabilitySnapshot();
      if (!isBlockedPlayabilitySnapshot(activeSnapshot)) {
        resetPlayabilityRecoveryState();
        return;
      }
      activeState.attempts = Number(activeState.attempts || 0) + 1;
      activeState.lastAttemptAt = Date.now();
      activeState.lastStatus = activeSnapshot.status || '';
      activeState.lastErrorText =
          activeSnapshot.errorText || activeSnapshot.reason || '';
      activeState.lastReadyState = Number(activeSnapshot.readyState || 0);
      activeState.lastNavigationAt = Date.now();
      debugState.playabilityRecovery = activeState;
      persistPlayabilityRecoveryState(activeState);
      const activeHref = toAbsolute(location.href) || location.href;
      const targetHref = canonicalizeWatchHref(activeHref) || activeHref;
      if (targetHref !== activeHref) {
        recordDebug('playability_recovery_replace', {
          reason: activeState.reason,
          videoId: activeState.videoId,
          attempts: activeState.attempts,
          href: activeHref,
          canonicalHref: targetHref,
        });
        commitCanonicalWatchNavigation(
            targetHref, 'playability_recover_replace', {
              replaceHistory: true,
              warmTarget: false,
            });
        return;
      }
      recordDebug('playability_recovery_reload', {
        reason: activeState.reason,
        videoId: activeState.videoId,
        attempts: activeState.attempts,
        href: activeHref,
      });
      saveAutoplayIntent(targetHref, 'playability_recover_reload');
      transitionInFlight = true;
      clearWarmTimer();
      clearAutoplayRetryTimer();
      clearAudibleRetryTimer();
      try {
        location.reload();
      } catch (e) {
        transitionInFlight = false;
        recordDebug('playability_recovery_reload_failed', {
          reason: activeState.reason,
          videoId: activeState.videoId,
          attempts: activeState.attempts,
          error: String(e && e.message || e || ''),
        });
      }
    }, delayMs);
    return true;
  }

  function saveForegroundPlaybackState(reason) {
    const video = document.querySelector('video');
    const videoId = currentVideoId();
    if (!video || !videoId || video.paused || video.ended) {
      return null;
    }
    const state = {
      capturedAt: Date.now(),
      reason: reason || 'unknown',
      videoId,
      muted: !!video.muted,
      volume: Number.isFinite(video.volume) ? video.volume : 1,
    };
    try {
      sessionStorage.setItem(
          FOREGROUND_RESUME_STORAGE_KEY, JSON.stringify(state));
    } catch (e) {}
    recordDebug('foreground_state_saved', state);
    return state;
  }

  function clearForegroundPlaybackState() {
    try {
      sessionStorage.removeItem(FOREGROUND_RESUME_STORAGE_KEY);
    } catch (e) {}
  }

  function loadForegroundPlaybackState() {
    const parsed =
        safeParse(sessionStorage.getItem(FOREGROUND_RESUME_STORAGE_KEY));
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    const capturedAt = Number(parsed.capturedAt || 0);
    if (!capturedAt || Date.now() - capturedAt > FOREGROUND_RESUME_TTL_MS) {
      clearForegroundPlaybackState();
      return null;
    }
    return parsed;
  }

  function ensureForegroundPlayback(reason) {
    const state = loadForegroundPlaybackState();
    const currentId = currentVideoId();
    if (!state || !currentId || state.videoId !== currentId) {
      return false;
    }
    const video = document.querySelector('video');
    if (!video) {
      recordDebug('foreground_resume_no_video', {
        reason: reason || 'unknown',
        currentId,
      });
      return false;
    }
    if (!video.paused) {
      clearForegroundPlaybackState();
      recordDebug('foreground_resume_not_needed', {
        reason: reason || 'unknown',
        currentId,
      });
      ensureAudiblePlayback((reason || 'unknown') + '_audible');
      return true;
    }
    try {
      if (!state.muted) {
        video.defaultMuted = false;
        video.muted = false;
        if (Number.isFinite(state.volume) && state.volume > 0) {
          video.volume = state.volume;
        }
        clickFirst([
          '.ytp-unmute',
          '.ytp-mute-button[aria-label*="Unmute"]',
          'button[aria-label*="Unmute"]',
        ]);
      }
    } catch (e) {}
    try {
      const playResult =
          typeof video.play === 'function' ? video.play() : null;
      if (playResult && typeof playResult.catch === 'function') {
        playResult.catch(error => {
          recordDebug('foreground_resume_rejected', {
            reason: reason || 'unknown',
            currentId,
            error: String(error && error.message || error || ''),
          });
        });
      }
    } catch (e) {
      recordDebug('foreground_resume_threw', {
        reason: reason || 'unknown',
        currentId,
        error: String(e && e.message || e || ''),
      });
      return false;
    }
    if (!video.paused) {
      clearForegroundPlaybackState();
      recordDebug('foreground_resume_ready', {
        reason: reason || 'unknown',
        currentId,
        muted: video.muted,
        volume: video.volume,
      });
      ensureAudiblePlayback((reason || 'unknown') + '_audible');
      return true;
    }
    recordDebug('foreground_resume_pending', {
      reason: reason || 'unknown',
      currentId,
      readyState: video.readyState,
    });
    return false;
  }

  function isPageRevealHoldActiveForCurrentVideo() {
    const currentId = currentVideoId();
    return !!currentId && !!pageRevealState.active
        && pageRevealState.videoId === currentId;
  }

  function shouldPreserveRetryBudget(reason) {
    if (!isPageRevealHoldActiveForCurrentVideo()) {
      return false;
    }
    return /(no_video|not_ready|playability_pending)/.test(
        String(reason || 'unknown'));
  }

  function shouldDeferPlayabilityRecovery(reason, snapshot) {
    if (!isPageRevealHoldActiveForCurrentVideo() || !snapshot) {
      return false;
    }
    const holdAgeMs = Math.max(
        0, Date.now() - Number(pageRevealState.holdStartedWallAt || 0));
    const normalizedReason = String(reason || 'unknown');
    const lifecycleTriggered =
        /(autoplay|audible|resume|playback|page_reveal|warm)/.test(
            normalizedReason);
    if (!lifecycleTriggered && snapshot.hasVideo) {
      return false;
    }
    if (!snapshot.hasVideo) {
      return holdAgeMs < 2200;
    }
    if (!!snapshot.errorText) {
      return holdAgeMs < 800;
    }
    if (!!snapshot.status && snapshot.status !== 'OK') {
      return holdAgeMs < 1200;
    }
    return false;
  }

  function scheduleAutoplayRetry(reason) {
    const intent = loadAutoplayIntent();
    if (!intent) {
      return;
    }
    const preserveBudget = shouldPreserveRetryBudget(reason);
    const attempts = Number(intent.attemptCount || 0);
    if (!preserveBudget && attempts >= 8) {
      return;
    }
    intent.attemptCount = preserveBudget ? attempts : attempts + 1;
    persistAutoplayIntent(intent);
    debugState.lastAutoplayResult = {
      action: preserveBudget ? 'retry_deferred' : 'retry_scheduled',
      reason: reason || 'unknown',
      attemptCount: intent.attemptCount,
      targetVideoId: intent.targetVideoId || null,
      pageRevealActive: isPageRevealHoldActiveForCurrentVideo(),
    };
    recordDebug('autoplay_retry_scheduled', debugState.lastAutoplayResult);
    clearAutoplayRetryTimer();
    autoplayRetryTimer = setTimeout(() => {
      autoplayRetryTimer = 0;
      ensureAutoplayForArmedTarget('retry_' + reason);
    }, preserveBudget ? 140 : (attempts < 2 ? 120 : 260));
  }

  function shouldSkipAutoplayDispatch(reason, currentId) {
    if (!currentId) {
      return false;
    }
    const normalizedReason = String(reason || 'unknown');
    if (normalizedReason.startsWith('retry_') || normalizedReason === 'manual') {
      debugState.lastAutoplayDispatch = {
        at: Date.now(),
        reason: normalizedReason,
        videoId: currentId,
      };
      return false;
    }
    const lastDispatch = debugState.lastAutoplayDispatch;
    const now = Date.now();
    if (lastDispatch && lastDispatch.videoId === currentId
        && now - Number(lastDispatch.at || 0) < AUTOPLAY_CALL_COOLDOWN_MS) {
      recordDebug('autoplay_dispatch_skipped', {
        reason: normalizedReason,
        currentId,
        previousReason: lastDispatch.reason || null,
        deltaMs: now - Number(lastDispatch.at || 0),
      });
      return true;
    }
    debugState.lastAutoplayDispatch = {
      at: now,
      reason: normalizedReason,
      videoId: currentId,
    };
    return false;
  }

  function textFromNode(node) {
    if (!node) {
      return '';
    }
    return String(node.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function isLikelyVisible(node) {
    if (!node || !node.isConnected) {
      return false;
    }
    try {
      const style = window.getComputedStyle(node);
      if (!style || style.display === 'none' || style.visibility === 'hidden'
          || style.opacity === '0') {
        return false;
      }
      const rect = node.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    } catch (e) {
      return true;
    }
  }

  function findPlayabilityErrorText() {
    const selectors = [
      'ytm-player-error-message-renderer',
      'ytd-player-error-message-renderer',
      '.yt-player-error-message-renderer',
      '.yt-playability-error-supported-renderers',
      '[data-layer="4"] .message',
    ];
    for (const selector of selectors) {
      for (const node of document.querySelectorAll(selector)) {
        if (!isLikelyVisible(node)) {
          continue;
        }
        const text = textFromNode(node);
        if (text) {
          return text;
        }
      }
    }
    return '';
  }

  function getPlayabilitySnapshot() {
    const status =
        String(window.ytInitialPlayerResponse?.playabilityStatus?.status || '');
    const reason = String(
        window.ytInitialPlayerResponse?.playabilityStatus?.reason
        || window.ytInitialPlayerResponse?.playabilityStatus?.messages?.[0]
        || '');
    const errorText = findPlayabilityErrorText();
    const video = document.querySelector('video');
    return {
      status,
      reason: reason.replace(/\s+/g, ' ').trim(),
      errorText,
      hasVideo: !!video,
      paused: !!video?.paused,
      readyState: Number(video?.readyState || 0),
    };
  }

  function clearPageRevealCheckTimer() {
    if (!pageRevealCheckTimer) {
      return;
    }
    clearTimeout(pageRevealCheckTimer);
    pageRevealCheckTimer = 0;
  }

  function clearPageRevealFallbackTimer() {
    if (!pageRevealFallbackTimer) {
      return;
    }
    clearTimeout(pageRevealFallbackTimer);
    pageRevealFallbackTimer = 0;
  }

  function syncPageRevealDebug(reason) {
    debugState.pageReveal = {
      active: !!pageRevealState.active,
      videoId: pageRevealState.videoId || null,
      href: pageRevealState.href || null,
      holdStartedAt: Number(pageRevealState.holdStartedAt || 0),
      visualRevealAt: Number(pageRevealState.visualRevealAt || 0),
      revealAt: Number(pageRevealState.revealAt || 0),
      reason: reason || pageRevealState.reason || null,
      fallback: !!pageRevealState.fallback,
      overlayReady: !!pageRevealState.overlayReady,
      lastReadiness: pageRevealState.lastReadiness || null,
    };
  }

  function ensurePageRevealOverlay(shell) {
    const host = document.body || document.documentElement;
    if (!host) {
      return null;
    }
    if (!pageRevealOverlay || !pageRevealOverlay.isConnected) {
      pageRevealOverlay = document.createElement('div');
      pageRevealOverlay.id = 'onetabtube-page-reveal-overlay';
      host.appendChild(pageRevealOverlay);
    }
    const thumbnailUrl = String(shell?.thumbnailUrl || '')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '%27');
    const title = normalizePreparedText(shell?.title || 'Loading video');
    const owner = normalizePreparedText(shell?.owner || 'YouTube');
    const currentId = currentVideoId();
    const videoPresentationIntent = loadVideoPresentationIntent();
    const useVideoPresentationShell =
        !!videoPresentationIntent
        && !!currentId
        && videoPresentationIntent.targetVideoId === currentId;
    const el = (tagName, className, textValue) => {
      const node = document.createElement(tagName);
      if (className) {
        node.className = className;
      }
      if (textValue != null) {
        node.textContent = textValue;
      }
      return node;
    };
    const shellRoot = el('div', 'otb-shell');
    const shellVideo = el('div', 'otb-shell-video');
    if (thumbnailUrl) {
      shellVideo.style.backgroundImage = 'url("' + thumbnailUrl + '")';
    }
    shellVideo.appendChild(el('div', 'otb-shell-video-scrim'));
    shellRoot.appendChild(shellVideo);

    if (useVideoPresentationShell) {
      shellRoot.classList.add('otb-shell-video-only');
      shellVideo.classList.add('otb-shell-video-only-frame');
    } else {
      const shellMeta = el('div', 'otb-shell-meta');
      shellMeta.appendChild(el('div', 'otb-shell-title', title || 'Loading video'));
      const ownerRow = el('div', 'otb-shell-owner-row');
      ownerRow.appendChild(el('div', 'otb-shell-owner-avatar'));
      ownerRow.appendChild(el('div', 'otb-shell-owner', owner || 'YouTube'));
      shellMeta.appendChild(ownerRow);

      const actions = el('div', 'otb-shell-actions');
      actions.appendChild(el('span'));
      actions.appendChild(el('span'));
      actions.appendChild(el('span'));
      shellMeta.appendChild(actions);

      const list = el('div', 'otb-shell-list');
      for (let index = 0; index < 3; index += 1) {
        const item = el('div', 'otb-shell-list-item');
        item.appendChild(el('i'));
        item.appendChild(el('b'));
        item.appendChild(el('b'));
        list.appendChild(item);
      }
      shellMeta.appendChild(list);
      shellRoot.appendChild(shellMeta);
    }
    pageRevealOverlay.replaceChildren(shellRoot);
    pageRevealOverlay.dataset.otbMode =
        useVideoPresentationShell ? 'video' : 'shell';
    pageRevealState.overlayReady = true;
    return pageRevealOverlay;
  }

  function ensurePageRevealStyle() {
    if (document.getElementById('onetabtube-page-reveal-style')) {
      return;
    }
    const style = document.createElement('style');
    style.id = 'onetabtube-page-reveal-style';
    style.textContent = ''
        + 'html[data-otb-page-reveal="hold"] body {'
        + '  background:#0f0f0f !important;'
        + '}'
        + 'html[data-otb-page-reveal="hold"] body > :not(#onetabtube-page-reveal-overlay) {'
        + '  opacity:0 !important;'
        + '  visibility:hidden !important;'
        + '}'
        + '#onetabtube-page-reveal-overlay {'
        + '  position:fixed;'
        + '  inset:0;'
        + '  z-index:2147483647;'
        + '  background:#0f0f0f;'
        + '  color:#f6f6f6;'
        + '  display:flex;'
        + '  align-items:flex-start;'
        + '  justify-content:center;'
        + '  overflow:auto;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell {'
        + '  width:min(100vw, 680px);'
        + '  min-height:100vh;'
        + '  background:linear-gradient(180deg, #111 0%, #171717 100%);'
        + '}'
        + '#onetabtube-page-reveal-overlay[data-otb-mode="video"] .otb-shell {'
        + '  width:100vw;'
        + '  min-height:100vh;'
        + '  background:#000;'
        + '  display:flex;'
        + '  align-items:center;'
        + '  justify-content:center;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-video {'
        + '  width:100%;'
        + '  aspect-ratio:16 / 9;'
        + '  background:#1d1d1d center / cover no-repeat;'
        + '  position:relative;'
        + '}'
        + '#onetabtube-page-reveal-overlay[data-otb-mode="video"] .otb-shell-video {'
        + '  width:100vw;'
        + '  max-height:100vh;'
        + '  aspect-ratio:16 / 9;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-video-scrim {'
        + '  position:absolute;'
        + '  inset:0;'
        + '  background:linear-gradient(180deg, rgba(0,0,0,0.12), rgba(0,0,0,0.36));'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-meta {'
        + '  padding:18px 16px 28px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-title {'
        + '  font-size:20px;'
        + '  font-weight:700;'
        + '  line-height:1.3;'
        + '  margin-bottom:14px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-owner-row {'
        + '  display:flex;'
        + '  align-items:center;'
        + '  gap:12px;'
        + '  margin-bottom:16px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-owner-avatar {'
        + '  width:36px;'
        + '  height:36px;'
        + '  border-radius:50%;'
        + '  background:#2f2f2f;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-owner {'
        + '  font-size:14px;'
        + '  color:#d4d4d4;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-actions {'
        + '  display:flex;'
        + '  gap:10px;'
        + '  margin-bottom:24px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-actions span {'
        + '  width:82px;'
        + '  height:34px;'
        + '  border-radius:999px;'
        + '  background:#252525;'
        + '  display:inline-block;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list {'
        + '  display:flex;'
        + '  flex-direction:column;'
        + '  gap:14px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list-item {'
        + '  display:grid;'
        + '  grid-template-columns:136px 1fr;'
        + '  gap:12px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list-item i {'
        + '  display:block;'
        + '  width:136px;'
        + '  height:76px;'
        + '  border-radius:12px;'
        + '  background:#242424;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list-item b {'
        + '  display:block;'
        + '  height:14px;'
        + '  border-radius:999px;'
        + '  background:#242424;'
        + '  margin-top:10px;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list-item b:first-of-type {'
        + '  width:84%;'
        + '}'
        + '#onetabtube-page-reveal-overlay .otb-shell-list-item b:last-of-type {'
        + '  width:58%;'
        + '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function currentWatchTitle() {
    const selectorTitle = [
      'h1',
      '.slim-video-metadata-title',
      '[aria-label][role="heading"]',
    ];
    for (const selector of selectorTitle) {
      for (const node of document.querySelectorAll(selector)) {
        const text = textFromNode(node);
        if (text) {
          return text;
        }
      }
    }
    return normalizePreparedText(
        window.ytInitialPlayerResponse?.videoDetails?.title || '');
  }

  function currentWatchOwner() {
    const selectors = [
      'ytm-slim-owner-renderer .channel-title',
      'ytm-slim-owner-renderer a',
      '#upload-info a',
      'a[href^="/@"]',
    ];
    for (const selector of selectors) {
      for (const node of document.querySelectorAll(selector)) {
        const text = textFromNode(node);
        if (text) {
          return text;
        }
      }
    }
    return normalizePreparedText(
        window.ytInitialPlayerResponse?.videoDetails?.author || '');
  }

  function collectPageRevealReadiness() {
    const snapshot = getPlayabilitySnapshot();
    const video = document.querySelector('video');
    const currentId = currentVideoId();
    const videoPresentationIntent = loadVideoPresentationIntent();
    const titleText = currentWatchTitle();
    const ownerText = currentWatchOwner();
    const actionButtons = [
      '.slim-video-action-bar-actions button',
      'ytm-menu-renderer button',
      '#menu button',
      'button[aria-label*="Like"]',
      'button[aria-label*="Share"]',
    ].some(selector => [...document.querySelectorAll(selector)].some(isLikelyVisible));
    const hasSecondary =
        !!findNextAnchor() || !!findFallbackNextHref()
        || !!document.querySelector(
            'ytm-item-section-renderer, ytm-watch-next-secondary-results-renderer');
    const videoReady = !!video
        && Number(video.readyState || 0) >= 2
        && (!video.paused || Number(video.currentTime || 0) > 0);
    const requireVideoPresentation =
        !!videoPresentationIntent
        && !!currentId
        && videoPresentationIntent.targetVideoId === currentId;
    const presentationReady =
        !requireVideoPresentation || hasFullscreenPresentation(video);
    const blocked = isBlockedPlayabilitySnapshot(snapshot);
    return {
      blocked,
      videoReady,
      requireVideoPresentation,
      presentationReady,
      titleReady: !!titleText,
      ownerReady: !!ownerText,
      actionButtons,
      secondaryReady: !!hasSecondary,
      titleText: titleText || null,
      ownerText: ownerText || null,
      ready:
          !blocked && videoReady && presentationReady
          && !!titleText && !!ownerText
          && (actionButtons || !!hasSecondary),
    };
  }

  function detachPageRevealObserver() {
    if (!pageRevealObserver) {
      return;
    }
    pageRevealObserver.disconnect();
    pageRevealObserver = null;
  }

  function finishPageReveal(reason, fallback) {
    if (!pageRevealState.active && !pageRevealState.overlayReady) {
      return;
    }
    const readiness = collectPageRevealReadiness();
    pageRevealState.active = false;
    pageRevealState.reason = reason || pageRevealState.reason || 'ready';
    pageRevealState.fallback = !!fallback;
    pageRevealState.lastReadiness = readiness;
    if (!pageRevealState.revealAt) {
      pageRevealState.revealAt = Math.round(performance.now());
      pageRevealState.revealWallAt = Date.now();
    }
    if (pageRevealOverlay) {
      try {
        pageRevealOverlay.remove();
      } catch (e) {}
      pageRevealOverlay = null;
    }
    pageRevealState.overlayReady = false;
    delete document.documentElement.dataset.otbPageReveal;
    clearPageRevealCheckTimer();
    clearPageRevealFallbackTimer();
    detachPageRevealObserver();
    syncPageRevealDebug(reason || 'ready');
    recordDebug(fallback ? 'page_reveal_fallback' : 'page_reveal_ready', {
      reason: pageRevealState.reason,
      fallback: !!fallback,
      readiness,
      videoId: pageRevealState.videoId,
    });
    try {
      console.info(
          'OTB_PERF event=page_reveal video='
          + (pageRevealState.videoId || currentVideoId() || 'none'));
    } catch (e) {}
    if (pageRevealState.videoId === currentVideoId()) {
      clearPreparedShell();
    }
  }

  function maybeResolvePageReveal(reason) {
    if (!pageRevealState.active) {
      return false;
    }
    const currentId = currentVideoId();
    if (!currentId || pageRevealState.videoId !== currentId) {
      finishPageReveal(reason || 'video_changed', true);
      return false;
    }
    const readiness = collectPageRevealReadiness();
    pageRevealState.lastReadiness = readiness;
    syncPageRevealDebug(reason || 'check');
    if (readiness.ready) {
      finishPageReveal(reason || 'ready', false);
      return true;
    }
    clearPageRevealCheckTimer();
    pageRevealCheckTimer = setTimeout(() => {
      pageRevealCheckTimer = 0;
      maybeResolvePageReveal('retry_' + (reason || 'check'));
    }, readiness.videoReady ? 90 : 150);
    return false;
  }

  function beginPageRevealHold(shell, reason) {
    try {
      const currentId = currentVideoId();
      if (!currentId) {
        return false;
      }
      const mergedShell = mergePreparedShell(loadPreparedShell(), shell) || {
        href: canonicalizeWatchHref(location.href) || location.href,
        videoId: currentId,
        title: normalizePreparedText(
            window.ytInitialPlayerResponse?.videoDetails?.title || ''),
        owner: normalizePreparedText(
            window.ytInitialPlayerResponse?.videoDetails?.author || ''),
        thumbnailUrl: 'https://i.ytimg.com/vi/' + currentId + '/hq720.jpg',
        preparedAt: Date.now(),
        source: 'bootstrap',
      };
      if (mergedShell.videoId !== currentId) {
        return false;
      }
      ensurePageRevealStyle();
      ensurePageRevealOverlay(mergedShell);
      document.documentElement.dataset.otbPageReveal = 'hold';
      pageRevealState.active = true;
      pageRevealState.videoId = currentId;
      pageRevealState.href = mergedShell.href || location.href;
      pageRevealState.reason = reason || 'transition_target';
      pageRevealState.holdStartedAt = Math.round(performance.now());
      pageRevealState.holdStartedWallAt = Date.now();
      pageRevealState.visualRevealAt = pageRevealState.holdStartedAt;
      pageRevealState.visualRevealWallAt = pageRevealState.holdStartedWallAt;
      pageRevealState.revealAt = 0;
      pageRevealState.revealWallAt = 0;
      pageRevealState.fallback = false;
      pageRevealState.lastReadiness = collectPageRevealReadiness();
      syncPageRevealDebug(reason || 'transition_target');
      recordDebug('page_reveal_hold', {
        reason: pageRevealState.reason,
        videoId: currentId,
        title: mergedShell.title,
        owner: mergedShell.owner,
        source: mergedShell.source || 'unknown',
      });
      try {
        console.info(
            'OTB_PERF event=visual_reveal video='
            + (pageRevealState.videoId || currentId));
      } catch (e) {}
      clearPageRevealFallbackTimer();
      pageRevealFallbackTimer = setTimeout(() => {
        pageRevealFallbackTimer = 0;
        finishPageReveal('timeout', true);
      }, PAGE_REVEAL_TIMEOUT_MS);
      if (!pageRevealObserver && typeof MutationObserver === 'function') {
        const root = document.documentElement || document;
        pageRevealObserver = new MutationObserver(() => {
          if (pageRevealState.active) {
            maybeResolvePageReveal('mutation');
          }
        });
        pageRevealObserver.observe(root, {
          childList: true,
          subtree: true,
          attributes: true,
        });
      }
      maybeResolvePageReveal('bootstrap');
      return true;
    } catch (e) {
      recordDebug('page_reveal_hold_failed', {
        reason: reason || 'transition_target',
        error: String(e && e.message || e || ''),
      });
      return false;
    }
  }

  function bootstrapPageRevealForCurrentPage(reason) {
    try {
      const currentId = currentVideoId();
      if (!currentId) {
        return false;
      }
      if (pageRevealState.active && pageRevealState.videoId === currentId) {
        maybeResolvePageReveal(reason || 'already_active');
        return true;
      }
      const intent = loadAutoplayIntent();
      const preparedShell = loadPreparedShell();
      const shouldHold = !!(intent && intent.targetVideoId === currentId);
      if (!shouldHold) {
        return false;
      }
      const fallbackShell = mergePreparedShell(preparedShell, {
        href: canonicalizeWatchHref(location.href) || location.href,
        videoId: currentId,
        title: normalizePreparedText(
            window.ytInitialPlayerResponse?.videoDetails?.title || ''),
        owner: normalizePreparedText(
            window.ytInitialPlayerResponse?.videoDetails?.author || ''),
        thumbnailUrl: 'https://i.ytimg.com/vi/' + currentId + '/hq720.jpg',
        preparedAt: Date.now(),
        source: 'bootstrap',
      });
      return beginPageRevealHold(fallbackShell, reason || 'transition_target');
    } catch (e) {
      recordDebug('page_reveal_bootstrap_error', {
        reason: reason || 'transition_target',
        error: String(e && e.message || e || ''),
      });
      return false;
    }
  }

  function shouldRetryBlockedAutoplay(intent, snapshot) {
    if (!intent || !snapshot) {
      return false;
    }
    const ageMs = Math.max(0, Date.now() - Number(intent.armedAt || 0));
    const attemptCount = Number(intent.attemptCount || 0);
    const revealHoldActive =
        isPageRevealHoldActiveForCurrentVideo()
        && intent.targetVideoId === currentVideoId();
    if (snapshot.status === 'OK') {
      return !!snapshot.errorText
          && ageMs < (revealHoldActive ? 5200 : 4000)
          && attemptCount < 8;
    }
    if (!snapshot.status) {
      return ageMs < (revealHoldActive ? PAGE_REVEAL_TIMEOUT_MS + 300 : 2500)
          && attemptCount < 8;
    }
    return ageMs < (revealHoldActive ? 5600 : 5000) && attemptCount < 6;
  }

  function clickFirst(selectors) {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (!element) {
        continue;
      }
      try {
        element.click();
        return selector;
      } catch (e) {}
    }
    return null;
  }

  function scheduleAudibleRetry(reason) {
    const currentId = currentVideoId();
    if (!currentId) {
      return;
    }
    const preserveBudget = shouldPreserveRetryBudget(reason);
    const retryState = debugState.audibleRetry || {
      videoId: currentId,
      attempts: 0,
    };
    if (retryState.videoId !== currentId) {
      retryState.videoId = currentId;
      retryState.attempts = 0;
    }
    if (!preserveBudget && retryState.attempts >= 8) {
      return;
    }
    if (!preserveBudget) {
      retryState.attempts += 1;
    }
    retryState.reason = reason || 'unknown';
    retryState.at = Date.now();
    retryState.pageRevealActive = isPageRevealHoldActiveForCurrentVideo();
    debugState.audibleRetry = retryState;
    recordDebug('audible_retry_scheduled', retryState);
    clearAudibleRetryTimer();
    audibleRetryTimer = setTimeout(() => {
      audibleRetryTimer = 0;
      ensureAudiblePlayback('retry_' + (reason || 'unknown'));
    }, preserveBudget ? 180 : (retryState.attempts < 3 ? 160 : 320));
  }

  function resetAudibleRetryState() {
    clearAudibleRetryTimer();
    debugState.audibleRetry = null;
  }

  function ensureAudiblePlayback(reason) {
    const currentId = currentVideoId();
    if (!currentId) {
      resetPlayabilityRecoveryState();
      return false;
    }
    const snapshot = getPlayabilitySnapshot();
    if ((snapshot.status && snapshot.status !== 'OK') || snapshot.errorText) {
      recordDebug('audible_blocked', {
        reason: reason || 'unknown',
        currentId,
        snapshot,
      });
      schedulePlayabilityRecovery(reason || 'audible_blocked', snapshot);
      if (snapshot.status === 'OK' || !snapshot.status) {
        scheduleAudibleRetry(reason || 'playability_pending');
      }
      return false;
    }
    resetPlayabilityRecoveryState();

    const video = document.querySelector('video');
    if (!video) {
      recordDebug('audible_no_video', {
        reason: reason || 'unknown',
        currentId,
        pageRevealActive: isPageRevealHoldActiveForCurrentVideo(),
      });
      scheduleAudibleRetry(reason || 'no_video');
      return false;
    }

    try {
      video.defaultMuted = false;
      video.muted = false;
      if (!Number.isFinite(video.volume) || video.volume < 0.95) {
        video.volume = 1;
      }
    } catch (e) {}

    clickFirst([
      '.ytp-unmute',
      '.ytp-mute-button[aria-label*="Unmute"]',
      'button[aria-label*="Unmute"]',
      'button[title*="Unmute"]',
    ]);

    try {
      video.defaultMuted = false;
      video.muted = false;
      if (!Number.isFinite(video.volume) || video.volume < 0.95) {
        video.volume = 1;
      }
    } catch (e) {}

    if (video.paused) {
      clickFirst([
        '.ytp-large-play-button',
        '.ytp-play-button',
        'button[aria-label*="Play"]',
        'button[aria-label*="play"]',
      ]);
    }

    try {
      const playResult =
          typeof video.play === 'function' ? video.play() : null;
      if (playResult && typeof playResult.catch === 'function') {
        playResult.catch(error => {
          recordDebug('audible_play_rejected', {
            reason: reason || 'unknown',
            currentId,
            error: String(error && error.message || error || ''),
          });
          scheduleAudibleRetry(reason || 'play_rejected');
        });
      }
    } catch (e) {
      recordDebug('audible_play_threw', {
        reason: reason || 'unknown',
        currentId,
        error: String(e && e.message || e || ''),
      });
      scheduleAudibleRetry(reason || 'play_threw');
      return false;
    }

    if (!video.paused && video.readyState >= 2 && !video.muted &&
        Number(video.volume || 0) > 0) {
      resetAudibleRetryState();
      recordDebug('audible_ready', {
        reason: reason || 'unknown',
        currentId,
        readyState: video.readyState,
        muted: video.muted,
        volume: video.volume,
      });
      return true;
    }

    recordDebug('audible_pending', {
      reason: reason || 'unknown',
      currentId,
      paused: video.paused,
      readyState: video.readyState,
      muted: video.muted,
      volume: video.volume,
    });
    scheduleAudibleRetry(reason || 'not_ready');
    return false;
  }

  function ensureAutoplayForArmedTarget(reason) {
    const intent = loadAutoplayIntent();
    const currentId = currentVideoId();
    if (!intent || !currentId || intent.targetVideoId !== currentId) {
      return false;
    }
    if (shouldSkipAutoplayDispatch(reason, currentId)) {
      return false;
    }
    const snapshot = getPlayabilitySnapshot();
    debugState.lastAutoplayCheck = {
      reason: reason || 'unknown',
      currentId,
      targetVideoId: intent.targetVideoId || null,
      attemptCount: Number(intent.attemptCount || 0),
      snapshot,
    };
    recordDebug('autoplay_check', debugState.lastAutoplayCheck);
    if ((snapshot.status && snapshot.status !== 'OK') || snapshot.errorText) {
      schedulePlayabilityRecovery(reason || 'autoplay_blocked', snapshot);
      if (shouldRetryBlockedAutoplay(intent, snapshot)) {
        warmState.lastReason = 'playability_pending';
        debugState.lastAutoplayResult = {
          action: 'retry_pending_playability',
          reason: reason || 'unknown',
          currentId,
          snapshot,
        };
        recordDebug('autoplay_blocked_pending', debugState.lastAutoplayResult);
        scheduleAutoplayRetry(reason || 'playability_pending');
        return false;
      }
      warmState.lastReason = 'playability_blocked';
      debugState.lastAutoplayResult = {
        action: 'blocked',
        reason: reason || 'unknown',
        currentId,
        snapshot,
      };
      recordDebug('autoplay_blocked', debugState.lastAutoplayResult);
      try {
        console.warn(
            'OTB_PERF event=autoplay_blocked video=' + currentId
            + ' status=' + snapshot.status
            + ' reason=' + (snapshot.errorText || snapshot.reason).slice(0, 120));
      } catch (e) {}
      return false;
    }
    resetPlayabilityRecoveryState();
    const video = document.querySelector('video');
    if (!video) {
      debugState.lastAutoplayResult = {
        action: isPageRevealHoldActiveForCurrentVideo() ? 'defer_no_video'
                                                        : 'retry_no_video',
        reason: reason || 'unknown',
        currentId,
        pageRevealActive: isPageRevealHoldActiveForCurrentVideo(),
      };
      recordDebug('autoplay_no_video', debugState.lastAutoplayResult);
      scheduleAutoplayRetry(
          isPageRevealHoldActiveForCurrentVideo() ? 'page_reveal_no_video'
                                                  : (reason || 'no_video'));
      return false;
    }

    try {
      video.defaultMuted = false;
      video.muted = false;
      if (!Number.isFinite(video.volume) || video.volume < 0.95) {
        video.volume = 1;
      }
    } catch (e) {}

    if (video.muted || video.volume === 0) {
      clickFirst([
        '.ytp-unmute',
        '.ytp-mute-button[aria-label*="Unmute"]',
        'button[aria-label*="Unmute"]',
      ]);
      try {
        video.defaultMuted = false;
        video.muted = false;
        if (!Number.isFinite(video.volume) || video.volume < 0.95) {
          video.volume = 1;
        }
      } catch (e) {}
    }

    if (video.paused) {
      clickFirst([
        '.ytp-large-play-button',
        '.ytp-play-button',
        'button[aria-label*="Play"]',
        'button[aria-label*="play"]',
      ]);
    }

    try {
      const playResult =
          typeof video.play === 'function' ? video.play() : null;
      if (playResult && typeof playResult.catch === 'function') {
        playResult.catch(error => {
          debugState.lastAutoplayResult = {
            action: 'retry_play_rejected',
            reason: reason || 'unknown',
            currentId,
            error: String(error && error.message || error || ''),
          };
          recordDebug('autoplay_play_rejected', debugState.lastAutoplayResult);
          scheduleAutoplayRetry(reason || 'play_rejected');
        });
      }
    } catch (e) {
      debugState.lastAutoplayResult = {
        action: 'retry_play_threw',
        reason: reason || 'unknown',
        currentId,
        error: String(e && e.message || e || ''),
      };
      recordDebug('autoplay_play_threw', debugState.lastAutoplayResult);
      scheduleAutoplayRetry(reason || 'play_threw');
      return false;
    }

    if (!video.paused && video.readyState >= 2) {
      clearAutoplayIntent();
      debugState.lastAutoplayResult = {
        action: 'ready',
        reason: reason || 'unknown',
        currentId,
        muted: video.muted,
        volume: video.volume,
      };
      recordDebug('autoplay_ready', debugState.lastAutoplayResult);
      try {
        console.info('OTB_PERF event=autoplay_ready video=' + currentId);
      } catch (e) {}
      return true;
    }

    debugState.lastAutoplayResult = {
      action: 'retry_not_ready',
      reason: reason || 'unknown',
      currentId,
      paused: video.paused,
      readyState: video.readyState,
      muted: video.muted,
      volume: video.volume,
    };
    recordDebug('autoplay_not_ready', debugState.lastAutoplayResult);
    scheduleAutoplayRetry(reason || 'video_not_ready');
    return false;
  }

  function suspendWarmPipeline(reason) {
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      saveForegroundPlaybackState(reason);
      clearAudibleRetryTimer();
      resetPlayabilityRecoveryState();
    }
    clearWarmTimer();
    disposeAllWarmVideos();
    if (warmObserver) {
      warmObserver.disconnect();
      warmObserver = null;
    }
    transitionInFlight = false;
    if (reason) {
      warmState.lastReason = reason;
    }
    recordDebug('pipeline_suspended', {reason: reason || 'unknown'});
  }

  function resumeWarmPipeline(reason) {
    if (reason) {
      warmState.lastReason = reason;
    }
    recordDebug('pipeline_resumed', {reason: reason || 'unknown'});
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      ensureForegroundPlayback(reason || 'resume');
      ensureAudiblePlayback((reason || 'resume') + '_audible');
      ensureAutoplayForArmedTarget('resume');
    }
    if (!ENABLE_TRANSITION_WARM && !ENABLE_TRANSITION_PAGE_REVEAL) {
      return;
    }
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      bootstrapPageRevealForCurrentPage((reason || 'resume') + '_reveal');
      maybeResolvePageReveal((reason || 'resume') + '_resolve');
    }
    if (ENABLE_TRANSITION_WARM) {
      maybeWarmForCurrentPage(700);
    }
  }

  function prefetchHref(rawHref, forceRefresh) {
    if (!ENABLE_TRANSITION_WARM) {
      warmState.lastWarmResult = "disabled";
      return false;
    }
    const absoluteHref = canonicalizeWatchHref(rawHref);
    if (!absoluteHref || !isFastPathCandidate(absoluteHref)) {
      warmState.lastWarmResult = "skip_invalid";
      return false;
    }
    warmState.attempts += 1;
    warmState.lastTargetHref = absoluteHref;
    warmState.lastPrefetchAt = Date.now();
    try {
      primeConnection(location.origin);
      primeConnection('https://i.ytimg.com');
      primeCurrentMediaOrigin();
      primeThumbnail(extractVideoId(absoluteHref));
      updateSpeculationRules(absoluteHref);
    } catch (e) {
      warmState.lastFetchError = String(e && e.message || e || '');
    }
    const startedPageFetch = fetchTargetPage(absoluteHref);

    const warmedCachedTarget = warmCachedTarget(absoluteHref, !!forceRefresh);
    if (prefetched.has(absoluteHref)) {
      warmState.lastWarmResult =
          (warmedCachedTarget || startedPageFetch)
          ? "cache_refresh"
          : "cache_hit";
      if (warmedCachedTarget || startedPageFetch) {
        warmState.successes += 1;
      }
      return warmedCachedTarget || startedPageFetch;
    }

    prefetched.add(absoluteHref);

    const prefetchLink = document.createElement('link');
    prefetchLink.rel = 'prefetch';
    prefetchLink.as = 'document';
    prefetchLink.href = absoluteHref;
    (document.head || document.documentElement).appendChild(prefetchLink);

    warmState.lastFetchAt = Date.now();
    warmState.lastFetchMediaCount = 0;
    warmState.lastFetchError = null;
    runMainWorldWarm(absoluteHref);
    try {
      console.info('OTB_PERF event=next_prefetch href=' + absoluteHref);
    } catch (e) {}
    if (!warmedCachedTarget) {
      warmState.lastWarmResult = "prefetch_started";
    }
    return true;
  }

  function findNextAnchor() {
    const selectors = [
      'a.compact-media-item-image[href^="/watch?v="]',
      'a.media-item-thumbnail-container[href^="/watch?v="]',
      'a[href^="/watch?v="]',
    ];
    for (const selector of selectors) {
      const anchors = [...document.querySelectorAll(selector)].filter(anchor => {
        const href = anchor.getAttribute('href') || '';
        return isFastPathCandidate(href);
      });
      if (anchors.length) {
        return anchors[0];
      }
    }
    return null;
  }

  function findFallbackNextHref() {
    const hrefs = getInitialDataNextHrefs(3);
    return hrefs.length ? hrefs[0] : null;
  }

  function warmNextAnchor(forceRefresh, reason) {
    if (!ENABLE_TRANSITION_WARM) {
      warmState.lastReason = reason || "disabled";
      warmState.lastWarmResult = "disabled";
      return false;
    }
    const nextAnchor = findNextAnchor();
    if (!nextAnchor) {
      const fallbackHref = findFallbackNextHref();
      if (fallbackHref) {
        warmState.lastReason = reason || "initial_data";
        return prefetchHref(fallbackHref, !!forceRefresh);
      }
      warmState.lastReason = reason || "no_anchor";
      warmState.lastWarmResult = "no_anchor";
      return false;
    }
    warmState.lastReason = reason || "scheduled";
    return prefetchHref(nextAnchor.href, !!forceRefresh);
  }

  function scheduleWarmNextAnchor(delayMs) {
    if (!ENABLE_TRANSITION_WARM || transitionInFlight) {
      return;
    }
    clearWarmTimer();
    warmTimer = setTimeout(() => {
      warmTimer = 0;
      if (transitionInFlight) {
        return;
      }
      const warmed = warmNextAnchor(false, "timer");
      if (!warmed) {
        scheduleWarmNextAnchor(Math.min(1400, Math.max(250, delayMs + 150)));
        return;
      }
      scheduleWarmNextAnchor(900);
    }, delayMs);
  }

  function ensureWarmObserver() {
    if (!ENABLE_TRANSITION_WARM
        || warmObserver || typeof MutationObserver !== 'function') {
      return;
    }
    const root = document.body || document.documentElement;
    if (!root) {
      return;
    }
    warmObserver = new MutationObserver(() => {
      if (transitionInFlight) {
        return;
      }
      scheduleWarmNextAnchor(120);
    });
    warmObserver.observe(root, {
      childList: true,
      subtree: true,
    });
  }

  function onPlaybackStable(delayMs) {
    const videoId = currentVideoId();
    if (videoId) {
      activeVideoId = videoId;
    }
    transitionInFlight = false;
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      resetPlayabilityRecoveryState();
      ensureAudiblePlayback('playback_stable_audible');
      ensureAutoplayForArmedTarget('playback_stable');
      ensureVideoPresentationForArmedTarget('playback_stable');
      maybeResolvePageReveal('playback_stable');
    }
    primeCurrentMediaOrigin();
    if (ENABLE_TRANSITION_WARM) {
      scheduleWarmNextAnchor(delayMs);
    }
  }

  function observeVideoLifecycle() {
    const video = document.querySelector('video');
    if (!video) {
      return false;
    }
    if (video.__onetabtubeWarmObserved) {
      return !video.paused && video.readyState >= 2;
    }
    video.__onetabtubeWarmObserved = true;

    const markStable = () => {
      const currentId = currentVideoId();
      if (!transitionInFlight && currentId && activeVideoId === currentId) {
        return;
      }
      onPlaybackStable(transitionInFlight ? 1300 : 450);
    };

    video.addEventListener('loadeddata', markStable, true);
    video.addEventListener('playing', markStable, true);
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      video.addEventListener(
          'ended',
          () => saveCarryForwardVideoPresentation('video_ended'),
          true);
    }
    if (typeof video.requestVideoFrameCallback === 'function') {
      const waitForFrame = () => {
        video.requestVideoFrameCallback(() => {
          markStable();
        });
      };
      waitForFrame();
      video.addEventListener('loadeddata', waitForFrame, {once: true});
    } else if (!video.paused && video.readyState >= 2) {
      markStable();
      return true;
    }
    return false;
  }

  function maybeWarmForCurrentPage(delayMs) {
    const currentId = currentVideoId();
    if (!currentId) {
      return false;
    }
    const videoAlreadyStable = observeVideoLifecycle();
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      ensureAudiblePlayback('page_ready_audible');
      ensureAutoplayForArmedTarget('page_ready');
      ensureVideoPresentationForArmedTarget('page_ready');
    }
    if (!ENABLE_TRANSITION_WARM && !ENABLE_TRANSITION_PAGE_REVEAL) {
      if (videoAlreadyStable) {
        primeCurrentMediaOrigin();
      }
      return;
    }
    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      bootstrapPageRevealForCurrentPage('page_ready');
      maybeResolvePageReveal('page_ready');
    }
    if (ENABLE_TRANSITION_WARM) {
      ensureWarmObserver();
    }
    if (transitionInFlight) {
      return;
    }
    if (videoAlreadyStable) {
      primeCurrentMediaOrigin();
    }
    if (!ENABLE_TRANSITION_WARM) {
      return;
    }
    warmNextAnchor(
        videoAlreadyStable, videoAlreadyStable ? "stable_immediate"
                                               : "initial_immediate");
    scheduleWarmNextAnchor(videoAlreadyStable ? Math.min(350, delayMs) : delayMs);
  }

  maybeWarmForCurrentPage(900);
  if (ENABLE_TRANSITION_PAGE_REVEAL) {
    window.__onetabtubeNavigateWatch = (targetHref, reason, options) =>
        commitCanonicalWatchNavigation(
            targetHref, reason || 'external_navigation', options || {});
    window.__onetabtubeArmVideoPresentation = (targetHref, reason) =>
        saveVideoPresentationIntent(
            targetHref, reason || 'manual_video_presentation');
    window.__onetabtubeEnsureAudible =
        reason => ensureAudiblePlayback(reason || 'manual');
    window.__onetabtubeEnsureAutoplay =
        reason => ensureAutoplayForArmedTarget(reason || 'manual');
    window.__onetabtubeRecoverPlayability =
        reason => schedulePlayabilityRecovery(
            reason || 'manual', getPlayabilitySnapshot());
    window.__onetabtubeSuspendWarmPipeline =
        reason => suspendWarmPipeline(reason || 'manual');
    window.__onetabtubeResumeWarmPipeline =
        reason => resumeWarmPipeline(reason || 'manual');
  }
  document.addEventListener('DOMContentLoaded', () => maybeWarmForCurrentPage(700), true);
  window.addEventListener('pageshow', () => resumeWarmPipeline('pageshow'), true);
  document.addEventListener('yt-navigate-finish', () => maybeWarmForCurrentPage(900), true);
  if (ENABLE_TRANSITION_PAGE_REVEAL) {
    document.addEventListener(
        'fullscreenchange', () => maybeResolvePageReveal('fullscreenchange'),
        true);
    document.addEventListener(
        'webkitfullscreenchange',
        () => maybeResolvePageReveal('webkitfullscreenchange'),
        true);
  }
  window.addEventListener('focus', () => resumeWarmPipeline('focus'), true);
  window.addEventListener('blur', () => suspendWarmPipeline('blur'), true);
  window.addEventListener('pagehide', () => suspendWarmPipeline('pagehide'), true);
  (document._addEventListener || document.addEventListener).call(
      document,
      'freeze',
      () => suspendWarmPipeline('freeze'),
      true);
  (document._addEventListener || document.addEventListener).call(
      document,
      'resume',
      () => resumeWarmPipeline('resume_event'),
      true);

  if (ENABLE_TRANSITION_WARM) {
    document.addEventListener(
        'pointerdown',
          event => {
            const anchor = event.target?.closest?.('a[href*="/watch?v="]');
            if (!anchor || !isFastPathCandidate(anchor.href)) {
              return;
            }
            prefetchHref(anchor.href, false);
          },
          true);

    document.addEventListener(
        'touchstart',
          event => {
            const anchor = event.target?.closest?.('a[href*="/watch?v="]');
            if (!anchor || !isFastPathCandidate(anchor.href)) {
              return;
            }
            prefetchHref(anchor.href, false);
          },
          {capture: true, passive: true});

    document.addEventListener(
        'focusin',
        event => {
          const anchor = event.target?.closest?.('a[href*="/watch?v="]');
          if (!anchor || !isFastPathCandidate(anchor.href)) {
            return;
          }
          prefetchHref(anchor.href, false);
        },
        true);

    if (ENABLE_TRANSITION_PAGE_REVEAL) {
      document.addEventListener(
          'click',
          event => {
            if (event.defaultPrevented || event.button !== 0
                || event.metaKey || event.ctrlKey || event.shiftKey
                || event.altKey) {
              return;
            }
            const anchor = event.target?.closest?.('a[href*="/watch?v="]');
            if (!anchor || !isFastPathCandidate(anchor.href)) {
              return;
            }
            const targetHref = canonicalizeWatchHref(anchor.href);
            if (!targetHref) {
              return;
            }
            if (anchor.href !== targetHref) {
              anchor.href = targetHref;
            }
            if (event.cancelable) {
              event.preventDefault();
            }
            event.stopImmediatePropagation();
            event.stopPropagation();
            const anchorShell = (() => {
              const container = anchor.closest(
                  'ytm-compact-video-renderer, ytm-video-with-context-renderer,'
                  + ' ytd-compact-video-renderer, ytd-video-renderer,'
                  + ' .compact-media-item, .media-item, li');
              const titleNode = container?.querySelector(
                  'h3, h4, .media-item-headline, .compact-media-item-headline,'
                  + ' .video-title, .yt-core-attributed-string');
              const ownerNode = container?.querySelector(
                  '.channel-name, .video-byline, .compact-media-item-byline,'
                  + ' a[href^="/@"]');
              const img =
                  anchor.querySelector('img') || container?.querySelector('img');
              return {
                href: targetHref,
                videoId: extractVideoId(targetHref),
                title: normalizePreparedText(
                    textFromNode(titleNode)
                    || anchor.getAttribute('aria-label')
                    || ''),
                owner: normalizePreparedText(textFromNode(ownerNode) || ''),
                thumbnailUrl: img?.currentSrc || img?.src
                    || ('https://i.ytimg.com/vi/'
                        + (extractVideoId(targetHref) || '') + '/hq720.jpg'),
                preparedAt: Date.now(),
                source: 'anchor_dom',
              };
            })();
            commitCanonicalWatchNavigation(targetHref, 'watch_click', {
              replaceHistory: false,
              warmTarget: true,
              preparedShell: anchorShell,
            });
          },
          true);
    }
  }
}());
)OTB";

constexpr char16_t kYoutubeFullscreen[] =
    uR"(
(function() {
  return new Promise((resolve) => {
    const videoPlaySelector = "video.html5-main-video";
    const fullscreenSelector = "button.fullscreen-icon";
    function requestPlaybackResume(videoPlayer, reason) {
      if (!videoPlayer) {
        return;
      }
      const resume = () => {
        try {
          videoPlayer.defaultMuted = false;
          videoPlayer.muted = false;
          if (!Number.isFinite(videoPlayer.volume) || videoPlayer.volume < 0.95) {
            videoPlayer.volume = 1;
          }
        } catch (e) {}
        try {
          const playResult =
              typeof videoPlayer.play === 'function' ? videoPlayer.play() : null;
          if (playResult && typeof playResult.catch === 'function') {
            playResult.catch(() => {});
          }
        } catch (e) {}
        try {
          if (typeof window.__onetabtubeEnsurePlayback === 'function') {
            window.__onetabtubeEnsurePlayback(reason || 'pip_fullscreen');
          }
        } catch (e) {}
        try {
          if (typeof window.__onetabtubeEnsureAudible === 'function') {
            window.__onetabtubeEnsureAudible(reason || 'pip_fullscreen');
          }
        } catch (e) {}
        try {
          if (typeof window.__onetabtubeEnsureAutoplay === 'function') {
            window.__onetabtubeEnsureAutoplay(reason || 'pip_fullscreen');
          }
        } catch (e) {}
      };
      setTimeout(resume, 0);
      setTimeout(resume, 180);
      setTimeout(resume, 420);
    }
    function hasFullscreenPresentation(videoPlayer) {
      return !!document.fullscreenElement
          || !!document.webkitFullscreenElement
          || !!(videoPlayer && videoPlayer.webkitDisplayingFullscreen);
    }
    function startWaitingForFullscreenButton(playerContainer, resolve, videoPlayer) {
      let observerTimeout;
      const observer = new MutationObserver(
      (_mutationsList, observer) => {
        var fullscreenBtn = document.querySelector(fullscreenSelector);
        var videoPlayer = document.querySelector(videoPlaySelector);
        if (fullscreenBtn && videoPlayer) {
          clearTimeout(observerTimeout);
          observer.disconnect()
          requestFullscreen(fullscreenBtn, resolve, videoPlayer);
        }
      });
      observerTimeout = setTimeout(() => {
        observer.disconnect();
        resolve('timeout');
      }, 30000);
      observer.observe(playerContainer, {
        childList: true, subtree: true
      });
      try {
        (playerContainer || videoPlayer).click();
      } catch (e) {}
    }
    function tryDirectFullscreen(playerContainer, videoPlayer, resolve) {
      const target =
          playerContainer || videoPlayer?.closest?.('#player, #player-container-id')
          || videoPlayer;
      if (!target) {
        return false;
      }
      const requestFullscreenApi =
          target.requestFullscreen
          || target.webkitRequestFullscreen
          || videoPlayer?.requestFullscreen
          || videoPlayer?.webkitRequestFullscreen
          || videoPlayer?.webkitEnterFullscreen;
      if (!requestFullscreenApi) {
        return false;
      }
      const invokeTarget =
          requestFullscreenApi === videoPlayer?.requestFullscreen
          || requestFullscreenApi === videoPlayer?.webkitRequestFullscreen
          || requestFullscreenApi === videoPlayer?.webkitEnterFullscreen
              ? videoPlayer
              : target;
      const finishCheck = () => {
        if (hasFullscreenPresentation(videoPlayer)) {
          requestPlaybackResume(videoPlayer, 'pip_fullscreen_direct');
          resolve('fullscreen_triggered');
        } else if (playerContainer && videoPlayer) {
          startWaitingForFullscreenButton(playerContainer, resolve, videoPlayer);
        } else {
          resolve('requestFullscreen_failed');
        }
      };
      try {
        const maybePromise = requestFullscreenApi.call(invokeTarget);
        if (maybePromise && typeof maybePromise.then === 'function') {
          maybePromise.then(() => {
            setTimeout(finishCheck, 250);
          }).catch(() => {
            finishCheck();
          });
        } else {
          setTimeout(finishCheck, 250);
        }
        return true;
      } catch (e) {
        return false;
      }
    }
    function triggerFullscreen() {
      // Check if the video is not in fullscreen mode already.
      if (!document.fullscreenElement) {
        var fullscreenBtn = document.querySelector(fullscreenSelector);
        var videoPlayer = document.querySelector(videoPlaySelector);
        // Check if fullscreen button and video are available.
        if (fullscreenBtn && videoPlayer) {
         requestFullscreen(fullscreenBtn, resolve, videoPlayer);
        } else {
          // When fullscreen button is not available
          // clicking the movie player resume the UI.
          var playerContainer = document.getElementById("player-container-id");
          if (videoPlayer && playerContainer) {
            if (!tryDirectFullscreen(playerContainer, videoPlayer, resolve)) {
              startWaitingForFullscreenButton(playerContainer, resolve, videoPlayer);
            }
          } else {
            // No fullscreen elements found, resolve immediately
            resolve('no_elements');
          }
        }
      } else {
        // Already in fullscreen, resolve immediately
        requestPlaybackResume(document.querySelector(videoPlaySelector),
                              'pip_fullscreen_already');
        resolve('already_fullscreen');
      }
    }
    // Attempts to request fullscreen mode for the given movie player element.
    // Resolves with 'fullscreen_triggered' if successful, or
    // 'requestFullscreen_failed' if the request fails.
    function requestFullscreen(fullscreenBtn, resolve, videoPlayer) {
      if (videoPlayer.readyState >= 3) {
        clickFullscreenButton(fullscreenBtn, resolve);
      } else {
        videoPlayer.addEventListener("canplay", () => {
          clickFullscreenButton(fullscreenBtn, resolve);
        }, { once: true });
      }
    }
    function clickFullscreenButton(fullscreenBtn, resolve) {
      const effectivelyHidden =
          document.hidden && document.visibilityState === 'hidden';
      if (fullscreenBtn && !effectivelyHidden) {
        fullscreenBtn.click();
        requestPlaybackResume(document.querySelector(videoPlaySelector),
                              'pip_fullscreen_button');
        resolve('fullscreen_triggered');
      } else {
        resolve('requestFullscreen_failed');
      }
    }
    if (document.readyState === "loading") {
      // Loading hasn't finished yet.
      document.addEventListener("DOMContentLoaded",
      triggerFullscreen, { once: true });
    } else {
      // `DOMContentLoaded` has already fired.
      triggerFullscreen();
    }
  });
}());
)";

constexpr char16_t kYoutubeExitFullscreen[] =
    uR"(
(function() {
  return new Promise((resolve) => {
    const video = document.querySelector("video.html5-main-video");
    const finish = result => setTimeout(() => resolve(result), 150);
    const handleMaybePromise = maybePromise => {
      if (maybePromise && typeof maybePromise.then === 'function') {
        maybePromise.then(
            () => finish('fullscreen_exited'),
            () => finish('exit_failed'));
      } else {
        finish('fullscreen_exited');
      }
    };

    try {
      const hasDocumentFullscreen =
          !!document.fullscreenElement || !!document.webkitFullscreenElement;
      if (hasDocumentFullscreen) {
        const exitApi =
            document.exitFullscreen || document.webkitExitFullscreen;
        if (!exitApi) {
          finish('exit_api_missing');
          return;
        }
        handleMaybePromise(exitApi.call(document));
        return;
      }

      if (video && video.webkitDisplayingFullscreen
          && typeof video.webkitExitFullscreen === 'function') {
        handleMaybePromise(video.webkitExitFullscreen());
        return;
      }

      finish('not_fullscreen');
    } catch (e) {
      finish('exit_exception');
    }
  });
}());
)";

bool IsBackgroundVideoPlaybackEnabled(content::WebContents* contents) {
  PrefService* prefs =
      static_cast<Profile*>(contents->GetBrowserContext())->GetPrefs();

  return (base::FeatureList::IsEnabled(
              ::preferences::features::kBraveBackgroundVideoPlayback) &&
          prefs->GetBoolean(kBackgroundVideoPlaybackEnabled));
}

}  // namespace

YouTubeScriptInjectorTabHelper::YouTubeScriptInjectorTabHelper(
    content::WebContents* contents)
    : WebContentsObserver(contents),
      content::WebContentsUserData<YouTubeScriptInjectorTabHelper>(*contents) {}

YouTubeScriptInjectorTabHelper::~YouTubeScriptInjectorTabHelper() {}

void YouTubeScriptInjectorTabHelper::PrimaryPageChanged(content::Page& page) {
  script_injector_remote_.reset();
  bound_rfh_id_ = {};
  fullscreen_request_retry_pending_ = false;
  if (!restore_video_presentation_after_track_navigation_) {
    SetFullscreenRequested(false);
  }
}

void YouTubeScriptInjectorTabHelper::RenderFrameDeleted(
    content::RenderFrameHost* rfh) {
  if (rfh->GetGlobalId() == bound_rfh_id_) {
    script_injector_remote_.reset();
    bound_rfh_id_ = {};
    fullscreen_request_retry_pending_ = false;
    if (!restore_video_presentation_after_track_navigation_) {
      SetFullscreenRequested(false);
    }
  }
}

void YouTubeScriptInjectorTabHelper::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  if (navigation_handle->IsSameDocument() &&
      navigation_handle->IsInMainFrame() && navigation_handle->HasCommitted()) {
    fullscreen_request_retry_pending_ = false;
    if (restore_video_presentation_after_track_navigation_ &&
        IsYouTubeDomain()) {
      restore_video_presentation_after_track_navigation_ = false;
      LOG(INFO) << "OTB_PIP event=restore_video_presentation_same_document";
      SetFullscreenRequested(false);
      MaybeSetFullscreen();
      return;
    }
    SetFullscreenRequested(false);
  }
}

void YouTubeScriptInjectorTabHelper::PrimaryMainDocumentElementAvailable() {
  fullscreen_request_retry_pending_ = false;
  content::WebContents* contents = web_contents();
  // Filter only YouTube videos.
  if (!IsYouTubeDomain()) {
    restore_video_presentation_after_track_navigation_ = false;
    SetFullscreenRequested(false);
    return;
  }
  content::RenderFrameHost::AllowInjectingJavaScript();
  const char16_t* media_session_bridge =
      base::FeatureList::IsEnabled(
          ::preferences::features::kBraveYouTubeNativeTabBridge)
          ? youtube_script_injector::GetYouTubeNativeTabBridgeScript()
          : kYoutubeMediaSessionControls;
  contents->GetPrimaryMainFrame()->ExecuteJavaScript(kYoutubeSearchInputContrast,
                                                     base::NullCallback());
  contents->GetPrimaryMainFrame()->ExecuteJavaScript(
      kYoutubeTransientOverlaySuppression, base::NullCallback());
  contents->GetPrimaryMainFrame()->ExecuteJavaScript(kYoutubePlaybackStability,
                                                     base::NullCallback());
  contents->GetPrimaryMainFrame()->ExecuteJavaScript(
      kYoutubeTransitionOptimization, base::NullCallback());
  contents->GetPrimaryMainFrame()->ExecuteJavaScript(media_session_bridge,
                                                     base::NullCallback());
  if (IsBackgroundVideoPlaybackEnabled(contents)) {
    contents->GetPrimaryMainFrame()->ExecuteJavaScript(
        kYoutubeBackgroundPlayback, base::NullCallback());
  }
  if (base::FeatureList::IsEnabled(
          ::preferences::features::kBravePictureInPictureForYouTubeVideos)) {
    contents->GetPrimaryMainFrame()->ExecuteJavaScript(
        kYoutubePictureInPictureSupport, base::NullCallback());
  }
  if (restore_video_presentation_after_track_navigation_) {
    restore_video_presentation_after_track_navigation_ = false;
    LOG(INFO) << "OTB_PIP event=restore_video_presentation_new_page";
    SetFullscreenRequested(false);
    MaybeSetFullscreen();
    return;
  }
  SetFullscreenRequested(false);
}

void YouTubeScriptInjectorTabHelper::MediaEffectivelyFullscreenChanged(
    bool is_fullscreen) {
  LOG(INFO) << "OTB_PIP event=media_effectively_fullscreen_changed"
            << " fullscreen=" << is_fullscreen
            << " requested=" << HasFullscreenBeenRequested()
            << " visibility=" << static_cast<int>(web_contents()->GetVisibility());
  if (is_fullscreen && HasFullscreenBeenRequested()) {
    fullscreen_request_retry_pending_ = false;
    SetFullscreenRequested(false);
    if (web_contents()->GetVisibility() == content::Visibility::VISIBLE) {
      LOG(INFO) << "OTB_PIP event=enter_picture_in_picture_from_fullscreen";
      ::youtube_script_injector::EnterPictureInPicture(web_contents());
    }
  }
}

void YouTubeScriptInjectorTabHelper::MaybeSetFullscreen() {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  // Check if fullscreen has already been requested for this page.
  if (!rfh || !rfh->IsRenderFrameLive() || HasFullscreenBeenRequested()) {
    return;
  }

  // Mark fullscreen as requested for this page
  SetFullscreenRequested(true);
  EnsureBound(rfh);
  script_injector_remote_->RequestAsyncExecuteScript(
      ISOLATED_WORLD_ID_BRAVE_INTERNAL, kYoutubeFullscreen,
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnFullscreenScriptComplete,
          weak_factory_.GetWeakPtr(), rfh->GetGlobalFrameToken()));
}

void YouTubeScriptInjectorTabHelper::MaybeExitFullscreen() {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive()) {
    return;
  }

  // PiP expand should return to the watch page, not keep any stale fullscreen latch.
  fullscreen_request_retry_pending_ = false;
  SetFullscreenRequested(false);
  EnsureBound(rfh);
  script_injector_remote_->RequestAsyncExecuteScript(
      ISOLATED_WORLD_ID_BRAVE_INTERNAL, kYoutubeExitFullscreen,
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnExitFullscreenScriptComplete,
          weak_factory_.GetWeakPtr(), rfh->GetGlobalFrameToken()));
}

bool YouTubeScriptInjectorTabHelper::MaybePlayVideo() {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive() || !IsYouTubeDomain()) {
    return false;
  }

  EnsureBound(rfh);
  static constexpr char16_t kPlayCommand[] = uR"OTBPLAY(
(async function() {
  const bridge = window.__oneTabTubeNativeTabBridge;
  if (!bridge || !(await bridge.isAvailable())) return 'unavailable';
  return (await bridge.play()) ? 'ok' : 'failed';
}());
)OTBPLAY";
  script_injector_remote_->RequestAsyncExecuteScript(
      kMainWorldId, kPlayCommand,
      // Media notification / PiP controls are user-initiated actions.
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete,
          weak_factory_.GetWeakPtr(), "play"));
  return true;
}

bool YouTubeScriptInjectorTabHelper::MaybePauseVideo() {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive() || !IsYouTubeDomain()) {
    return false;
  }

  EnsureBound(rfh);
  static constexpr char16_t kPauseCommand[] = uR"OTBPAUSE(
(async function() {
  const bridge = window.__oneTabTubeNativeTabBridge;
  if (!bridge || !(await bridge.isAvailable())) return 'unavailable';
  return (await bridge.pause()) ? 'ok' : 'failed';
}());
)OTBPAUSE";
  script_injector_remote_->RequestAsyncExecuteScript(
      kMainWorldId, kPauseCommand,
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete,
          weak_factory_.GetWeakPtr(), "pause"));
  return true;
}

bool YouTubeScriptInjectorTabHelper::MaybeSeekBy(int offset_seconds) {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive() || !IsYouTubeDomain()) {
    return false;
  }

  EnsureBound(rfh);
  const std::u16string command = base::StrCat(
      {uR"OTBSEEK(
(async function() {
  const bridge = window.__oneTabTubeNativeTabBridge;
  if (!bridge || !(await bridge.isAvailable())) return 'unavailable';
  return (await bridge.seekBy()OTBSEEK",
       base::NumberToString16(offset_seconds),
       uR"OTBSEEK()) ? 'ok' : 'failed';
}());
)OTBSEEK"});
  script_injector_remote_->RequestAsyncExecuteScript(
      kMainWorldId, command,
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete,
          weak_factory_.GetWeakPtr(),
          offset_seconds >= 0 ? "seek_forward" : "seek_backward"));
  return true;
}

bool YouTubeScriptInjectorTabHelper::MaybeNextTrack(
    bool preserve_video_presentation) {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive() || !IsYouTubeDomain()) {
    return false;
  }

  EnsureBound(rfh);
  restore_video_presentation_after_track_navigation_ =
      preserve_video_presentation;
  if (preserve_video_presentation) {
    LOG(INFO) << "OTB_PIP event=arm_track_navigation_keepalive command=next_track";
    SetFullscreenRequested(true);
  }
  const std::u16string command = base::StrCat(
      {uR"OTBNEXT(
(async function() {
  const bridge = window.__oneTabTubeNativeTabBridge;
  if (!bridge || !(await bridge.isAvailable())) return 'unavailable';
  const result = await bridge.next({preserveVideoPresentation: )OTBNEXT",
       preserve_video_presentation ? u"true" : u"false",
       uR"OTBNEXT(});
  try {
    return JSON.stringify(result);
  } catch (e) {
    return (result && result.ok) ? 'ok' : 'failed';
  }
}());
)OTBNEXT"});
  script_injector_remote_->RequestAsyncExecuteScript(
      kMainWorldId, command,
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete,
          weak_factory_.GetWeakPtr(), "next_track"));
  return true;
}

bool YouTubeScriptInjectorTabHelper::MaybePreviousTrack(
    bool preserve_video_presentation) {
  content::RenderFrameHost* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh || !rfh->IsRenderFrameLive() || !IsYouTubeDomain()) {
    return false;
  }

  EnsureBound(rfh);
  restore_video_presentation_after_track_navigation_ =
      preserve_video_presentation;
  if (preserve_video_presentation) {
    LOG(INFO)
        << "OTB_PIP event=arm_track_navigation_keepalive command=previous_track";
    SetFullscreenRequested(true);
  }
  const std::u16string command = base::StrCat(
      {uR"OTBPREVIOUS(
(async function() {
  const bridge = window.__oneTabTubeNativeTabBridge;
  if (!bridge || !(await bridge.isAvailable())) return 'unavailable';
  const result = await bridge.previous({preserveVideoPresentation: )OTBPREVIOUS",
       preserve_video_presentation ? u"true" : u"false",
       uR"OTBPREVIOUS(});
  try {
    return JSON.stringify(result);
  } catch (e) {
    return (result && result.ok) ? 'ok' : 'failed';
  }
}());
)OTBPREVIOUS"});
  script_injector_remote_->RequestAsyncExecuteScript(
      kMainWorldId, command,
      blink::mojom::UserActivationOption::kActivate,
      blink::mojom::PromiseResultOption::kAwait,
      base::BindOnce(
          &YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete,
          weak_factory_.GetWeakPtr(), "previous_track"));
  return true;
}

bool YouTubeScriptInjectorTabHelper::IsYouTubeDomain(bool mobileOnly) const {
  const GURL& url = web_contents()->GetLastCommittedURL();
  if (!url.is_valid() || url.is_empty()) {
    return false;
  }

  // Check if domain is youtube.com (including subdomains).
  if (!net::registry_controlled_domains::SameDomainOrHost(
          url, GURL("https://www.youtube.com"),
          net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES)) {
    return false;
  }

  // If mobileOnly is true, require host to be exactly "m.youtube.com"
  // (case-insensitive).
  if (mobileOnly) {
    if (!base::EqualsCaseInsensitiveASCII(url.host(), "m.youtube.com")) {
      return false;
    }
  }

  return true;
}

bool YouTubeScriptInjectorTabHelper::IsYouTubeVideo(bool mobileOnly) const {
  if (!IsYouTubeDomain(mobileOnly)) {
    return false;
  }

  const GURL& url = web_contents()->GetLastCommittedURL();

  // Check if path is exactly "/watch" (case sensitive).
  std::string_view path = url.path();
  constexpr std::string_view watch_path = "/watch";
  if (path != watch_path) {
    return false;
  }

  // Check if query exists and contains a non-empty "v" parameter.
  std::string_view query = url.query();
  if (query.empty()) {
    return false;
  }

  // Key-value pairs are '&' delimited and the keys/values are '=' delimited.
  // Example: "https://www.youtube.com/watch?v=abcdefg&somethingElse=12345".
  std::string video_id;
  url::Component query_component(0, static_cast<int>(query.size()));
  url::Component key, value;
  while (url::ExtractQueryKeyValue(query, &query_component, &key, &value)) {
    if (query.substr(key.begin, key.len) == "v") {
      video_id = std::string(query.substr(value.begin, value.len));
      base::TrimWhitespaceASCII(video_id, base::TRIM_ALL, &video_id);
      break;
    }
  }

  return !video_id.empty();
}

bool YouTubeScriptInjectorTabHelper::HasFullscreenBeenRequested() const {
  content::NavigationEntry* entry =
      web_contents()->GetController().GetLastCommittedEntry();
  if (!entry) {
    return false;
  }

  auto* data = static_cast<content::FullscreenPageData*>(
      entry->GetUserData(content::kFullscreenPageDataKey));
  return data && data->fullscreen_requested();
}

void YouTubeScriptInjectorTabHelper::SetFullscreenRequested(bool requested) {
  content::NavigationEntry* entry =
      web_contents()->GetController().GetLastCommittedEntry();
  if (!entry) {
    return;
  }

  auto* data = static_cast<content::FullscreenPageData*>(
      entry->GetUserData(content::kFullscreenPageDataKey));
  if (data) {
    data->set_fullscreen_requested(requested);
  } else {
    entry->SetUserData(
        content::kFullscreenPageDataKey,
        std::make_unique<content::FullscreenPageData>(requested));
  }
}

void YouTubeScriptInjectorTabHelper::OnFullscreenScriptComplete(
    content::GlobalRenderFrameHostToken token,
    base::Value value) {
  std::string result =
      value.is_string() ? value.GetString() : std::string("<non-string>");
  LOG(INFO) << "OTB_PIP event=fullscreen_script_complete"
            << " result=" << result
            << " visibility=" << static_cast<int>(web_contents()->GetVisibility());
  // If the tab is visible, the script result indicates fullscreen is already
  // active or has just been triggered, and the callback is for the current
  // main frame, keep the fullscreen request armed and let the follow-up PiP
  // check decide whether fullscreen-backed presentation is actually ready.
  if (value.is_string() &&
      (value.GetString() == "fullscreen_triggered" ||
       value.GetString() == "already_fullscreen") &&
      token == web_contents()->GetPrimaryMainFrame()->GetGlobalFrameToken() &&
      web_contents()->GetVisibility() == content::Visibility::VISIBLE) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(
            &YouTubeScriptInjectorTabHelper::
                MaybeEnterPictureInPictureAfterFullscreenRequest,
            weak_factory_.GetWeakPtr(), token),
        base::Milliseconds(1200));
    return;
  }

  fullscreen_request_retry_pending_ = false;
  SetFullscreenRequested(false);
}

void YouTubeScriptInjectorTabHelper::MaybeEnterPictureInPictureAfterFullscreenRequest(
    content::GlobalRenderFrameHostToken token) {
  if (!web_contents() || !web_contents()->GetPrimaryMainFrame() ||
      token != web_contents()->GetPrimaryMainFrame()->GetGlobalFrameToken()) {
    return;
  }

  if (!HasFullscreenBeenRequested()) {
    return;
  }

  if (web_contents()->GetVisibility() != content::Visibility::VISIBLE) {
    return;
  }

  const bool active_fullscreen =
      web_contents()->HasActiveEffectivelyFullscreenVideo();
  if (!active_fullscreen && !fullscreen_request_retry_pending_) {
    fullscreen_request_retry_pending_ = true;
    LOG(INFO) << "OTB_PIP event=enter_picture_in_picture_fullscreen_timeout_retry";
    SetFullscreenRequested(false);
    MaybeSetFullscreen();
    return;
  }

  if (!active_fullscreen) {
    LOG(INFO)
        << "OTB_PIP event=enter_picture_in_picture_fullscreen_timeout_delegate_to_java_helper";
    fullscreen_request_retry_pending_ = false;
    SetFullscreenRequested(false);
    ::youtube_script_injector::EnterPictureInPicture(web_contents());
    return;
  }

  LOG(INFO) << "OTB_PIP event=enter_picture_in_picture_fullscreen_timeout_fallback"
            << " active_fullscreen=" << active_fullscreen
            << " retry_pending=" << fullscreen_request_retry_pending_;
  fullscreen_request_retry_pending_ = false;
  SetFullscreenRequested(false);
  ::youtube_script_injector::EnterPictureInPicture(web_contents());
}

void YouTubeScriptInjectorTabHelper::OnExitFullscreenScriptComplete(
    content::GlobalRenderFrameHostToken token,
    base::Value value) {
  std::string result =
      value.is_string() ? value.GetString() : std::string("<non-string>");
  LOG(INFO) << "OTB_PIP event=exit_fullscreen_script_complete"
            << " result=" << result
            << " visibility=" << static_cast<int>(web_contents()->GetVisibility());
  if (token != web_contents()->GetPrimaryMainFrame()->GetGlobalFrameToken()) {
    return;
  }
  fullscreen_request_retry_pending_ = false;
  SetFullscreenRequested(false);
}

void YouTubeScriptInjectorTabHelper::OnNativeTabBridgeCommandComplete(
    const std::string& command_name,
    base::Value value) {
  const std::string* result = value.GetIfString();
  if (command_name == "next_track" || command_name == "previous_track") {
    const bool keep_restore_flag =
        result && result->find("\"ok\":true") != std::string::npos &&
        result->find("restart-current") == std::string::npos;
    if (!keep_restore_flag) {
      restore_video_presentation_after_track_navigation_ = false;
      fullscreen_request_retry_pending_ = false;
      SetFullscreenRequested(false);
    }
  }
  LOG(INFO) << "OTB_MEDIA event=native_tab_bridge_command"
            << " command=" << command_name
            << " result=" << (result ? *result : "non_string_result");
}


bool YouTubeScriptInjectorTabHelper::IsPictureInPictureAvailable() const {
  return base::FeatureList::IsEnabled(
             preferences::features::kBravePictureInPictureForYouTubeVideos) &&
         IsYouTubeVideo(true) && web_contents() &&
         web_contents()->IsDocumentOnLoadCompletedInPrimaryMainFrame();
}

void YouTubeScriptInjectorTabHelper::EnsureBound(
    content::RenderFrameHost* rfh) {
  DCHECK(rfh);
  DCHECK(rfh->IsRenderFrameLive());

  if (!script_injector_remote_.is_bound() ||
      !script_injector_remote_.is_connected() ||
      bound_rfh_id_ != rfh->GetGlobalId()) {
    script_injector_remote_.reset();
    bound_rfh_id_ = rfh->GetGlobalId();
    rfh->GetRemoteAssociatedInterfaces()->GetInterface(
        &script_injector_remote_);
    script_injector_remote_.reset_on_disconnect();
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(YouTubeScriptInjectorTabHelper);
