/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/android/youtube_script_injector/youtube_native_tab_bridge.h"

namespace youtube_script_injector {

namespace {

constexpr char16_t kYouTubeNativeTabBridgeScript[] =
    uR"OTB_YT_BRIDGE(
(function() {
  if (window.__oneTabTubeNativeTabBridgeInstalled) {
    return;
  }
  window.__oneTabTubeNativeTabBridgeInstalled = true;

  let observedVideo = null;
  let lifecycleObserver = null;
  let refreshTimer = 0;
  let positionRefreshTimer = 0;
  let keepAliveTimer = 0;
  let trackFallbackState = null;
  let trackSettleState = null;
  let lastReliablePlaylistContext = null;
  let lastMediaSessionActionSignature = '';
  let lastPlaybackStateSignature = '';
  let lastPositionStateSignature = '';
  let lastTrackFallbackAt = 0;
  let lastTrackFallbackKind = '';
  let lastTrackFallbackSucceeded = false;
  const kTrackFallbackCooldownMs = 250;
  const kMediaSessionKeepAliveMs = 1500;
  const kReliablePlaylistContextReuseMs = 5000;
  const kPositionUpdateDebounceMs = 250;
  const kYouTubeHosts =
      new Set(['www.youtube.com', 'youtube.com', 'm.youtube.com',
               'music.youtube.com']);
  const kYouTubeMusicHosts = new Set(['music.youtube.com']);
  const kNextLabelTokens = ['next', 'next video', 'next track', 'skip next',
                            'track suivante', 'ถัดไป', 'เพลงถัดไป'];
  const kPreviousLabelTokens =
      ['previous', 'prev', 'previous video', 'previous track',
       'skip previous', 'ก่อนหน้า', 'ย้อนกลับ', 'เพลงก่อนหน้า'];
  const kLastResortNextSelectors = [
    '.ytp-next-button',
    'ytmusic-player-bar .next-button',
    'tp-yt-paper-icon-button.next-button',
  ];
  const kLastResortPreviousSelectors = [
    '.ytp-prev-button',
    'ytmusic-player-bar .previous-button',
    'tp-yt-paper-icon-button.previous-button',
  ];
  const kBridgeRelevantMutationSelector =
      'video, #movie_player, .html5-video-player, .ytp-chrome-controls, '
      + '.ytp-next-button, .ytp-prev-button, ytd-player, ytd-watch-flexy, '
      + 'ytm-watch, ytd-playlist-panel-renderer, ytmusic-player, '
      + 'ytmusic-player-bar, ytmusic-player-page, ytmusic-player-queue, '
      + 'ytmusic-queue';

  function currentVideo() {
    return document.querySelector('video');
  }

  function currentPageUrl() {
    return parseCandidateUrl(location.href);
  }

  function isYouTubeHost() {
    return kYouTubeHosts.has(String(location.hostname || '').toLowerCase());
  }

  function isYouTubeMusicHost() {
    return kYouTubeMusicHosts.has(String(location.hostname || '').toLowerCase());
  }

  function isPlaylistContext() {
    try {
      const params = new URLSearchParams(location.search || '');
      return params.has('list')
          || !!document.querySelector(
              'ytd-playlist-panel-renderer, ytmusic-player-queue, '
              + 'ytmusic-player-page, ytmusic-queue');
    } catch (e) {
      return false;
    }
  }

  function shouldObserveBridgeLifecycle() {
    return !!playerLikeRoot(currentVideo())
        || isPlaylistContext()
        || isYouTubeWatchLikeUrl(currentPageUrl());
  }

  function shouldResolveReliablePlaylistContext(video) {
    return !!video
        && (!!playerLikeRoot(video)
            || isPlaylistContext()
            || isYouTubeWatchLikeUrl(currentPageUrl()));
  }

  function playlistContextKeyFromUrlLike(rawHref) {
    try {
      const url = new URL(String(rawHref || location.href || ''), location.origin);
      const params = url.searchParams;
      if (params.has('list')) {
        return 'list:' + params.get('list');
      }
      if (params.has('start_radio')) {
        return 'radio:' + params.get('start_radio')
            + '|pp:' + String(params.get('pp') || '');
      }
      if (params.has('pp')) {
        return 'pp:' + params.get('pp');
      }
    } catch (e) {}
    return '';
  }

  function currentPlaylistContextKey() {
    return playlistContextKeyFromUrlLike(location.href);
  }

  function currentPlaylistIndexHint() {
    try {
      const params = new URLSearchParams(location.search || '');
      const value = Number.parseInt(params.get('index') || '', 10);
      if (Number.isFinite(value) && value > 0) {
        return value - 1;
      }
    } catch (e) {}
    return -1;
  }

  function debugEnabled() {
    return !!window.__oneTabTubeYouTubeFallbackDebug;
  }

  function debugLog(event, detail) {
    if (!debugEnabled()) {
      return;
    }
    try {
      console.info(
          'OTB_YT_FALLBACK event=' + event
          + (detail ? ' ' + String(detail) : ''));
    } catch (e) {}
  }

  function normalizeTitle(rawTitle) {
    const title = String(rawTitle || '').replace(/\s+/g, ' ').trim();
    return title || undefined;
  }

  function normalizedLabel(value) {
    return String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function isEditableTarget(el) {
    if (!el) {
      return false;
    }
    if (el.isContentEditable) {
      return true;
    }
    const tagName = String(el.tagName || '').toLowerCase();
    if (tagName === 'input' || tagName === 'textarea' || tagName === 'select') {
      return true;
    }
    if (typeof el.closest === 'function') {
      return !!el.closest(
          'input, textarea, select, [contenteditable=""], '
          + '[contenteditable="true"], [role="textbox"]');
    }
    return false;
  }

  function focusedEditableElement() {
    return isEditableTarget(document.activeElement) ? document.activeElement : null;
  }

  function isVisible(el) {
    if (!el || !el.isConnected) {
      return false;
    }
    if (el.hidden) {
      return false;
    }
    const style = window.getComputedStyle ? window.getComputedStyle(el) : null;
    if (style && (style.display === 'none' || style.visibility === 'hidden'
                  || style.pointerEvents === 'none')) {
      return false;
    }
    const rect = typeof el.getBoundingClientRect === 'function'
        ? el.getBoundingClientRect()
        : null;
    return !!rect && rect.width > 0 && rect.height > 0;
  }

  function isEnabled(el) {
    if (!el) {
      return false;
    }
    if (el.disabled) {
      return false;
    }
    const ariaDisabled = String(el.getAttribute?.('aria-disabled') || '').toLowerCase();
    return ariaDisabled !== 'true';
  }

  function isActionable(el) {
    return isVisible(el) && isEnabled(el);
  }

  function isConnectedAndEnabled(el) {
    return !!el && !!el.isConnected && isEnabled(el);
  }

  function nudgePlayerTransportControls() {
    const targets = [
      currentVideo(),
      playerLikeRoot(currentVideo()),
      document.getElementById('movie_player'),
      document.querySelector('.html5-video-player'),
    ].filter(Boolean);
    for (const target of targets) {
      const rect = typeof target.getBoundingClientRect === 'function'
          ? target.getBoundingClientRect()
          : {left: 0, top: 0, width: 0, height: 0};
      const clientX = Math.round((rect.left || 0) + Math.max(8, (rect.width || 0) / 2));
      const clientY = Math.round((rect.top || 0) + Math.max(8, (rect.height || 0) / 2));
      const commonInit = {
        bubbles: true,
        cancelable: true,
        composed: true,
        clientX,
        clientY,
      };
      try {
        target.dispatchEvent(new MouseEvent('mousemove', commonInit));
      } catch (e) {}
      try {
        target.dispatchEvent(new PointerEvent('pointermove', commonInit));
      } catch (e) {}
      try {
        target.dispatchEvent(new MouseEvent('mouseenter', commonInit));
      } catch (e) {}
    }
  }

  function clickIfActionable(el) {
    if (!isActionable(el)) {
      return false;
    }
    try {
      if (typeof el.focus === 'function') {
        el.focus({preventScroll: true});
      }
    } catch (e) {}
    try {
      el.click();
      return true;
    } catch (e) {
      return false;
    }
  }

  function clickTransportButton(el) {
    if (!isConnectedAndEnabled(el)) {
      return false;
    }
    nudgePlayerTransportControls();
    const rect = typeof el.getBoundingClientRect === 'function'
        ? el.getBoundingClientRect()
        : {left: 0, top: 0, width: 0, height: 0};
    const clientX = Math.round((rect.left || 0) + Math.max(8, (rect.width || 0) / 2));
    const clientY = Math.round((rect.top || 0) + Math.max(8, (rect.height || 0) / 2));
    const pointerInit = {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1,
      clientX,
      clientY,
      pointerId: 1,
      pointerType: 'mouse',
      isPrimary: true,
      view: window,
    };
    const mouseInit = {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1,
      clientX,
      clientY,
      view: window,
    };
    try {
      if (typeof el.focus === 'function') {
        el.focus({preventScroll: true});
      }
    } catch (e) {}
    try {
      el.dispatchEvent(new PointerEvent('pointerdown', pointerInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('mousedown', mouseInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new PointerEvent('pointerup', pointerInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('mouseup', mouseInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('click', mouseInit));
      return true;
    } catch (e) {}
    try {
      el.click();
      return true;
    } catch (e) {
      return false;
    }
  }

  function playerLikeRoot(el) {
    if (!el || typeof el.closest !== 'function') {
      return null;
    }
    return el.closest(
        '#movie_player, .html5-video-player, .ytp-chrome-controls, '
        + 'ytd-player, ytd-watch-flexy, ytm-watch, ytmusic-player, '
        + 'ytmusic-player-bar, ytmusic-player-page');
  }

  function describeNode(node) {
    if (!node) {
      return '';
    }
    const tagName = String(node.tagName || '').toLowerCase();
    const id = String(node.id || '').trim();
    const className =
        typeof node.className === 'string' ? node.className.trim() : '';
    return [tagName, id, className].filter(Boolean).join('#');
  }

  function ancestorDescriptorText(el) {
    const parts = [];
    let current = el;
    for (let depth = 0; current && depth < 5; ++depth) {
      parts.push(describeNode(current).toLowerCase());
      current = current.parentElement;
    }
    return parts.join(' ');
  }

  function collectSearchRoots() {
    const roots = [];
    const seen = new Set();

    function visit(root) {
      if (!root || seen.has(root) || typeof root.querySelectorAll !== 'function') {
        return;
      }
      seen.add(root);
      roots.push(root);
      let elements = [];
      try {
        elements = Array.from(root.querySelectorAll('*'));
      } catch (e) {}
      for (const element of elements) {
        if (element && element.shadowRoot) {
          visit(element.shadowRoot);
        }
      }
    }

    visit(document);
    return roots;
  }

  function currentVideoIdFromUrl() {
    try {
      const currentUrl = new URL(String(location.href || ''));
      if (currentUrl.hostname === 'youtu.be') {
        return currentUrl.pathname.replace(/^\/+/, '') || '';
      }
      return currentUrl.searchParams.get('v') || '';
    } catch (e) {
      return '';
    }
  }

  function parseCandidateUrl(rawHref) {
    try {
      return new URL(String(rawHref || ''), location.href);
    } catch (e) {
      return null;
    }
  }

  function preservePlaylistUrlContext(beforeHref) {
    const beforeUrl = parseCandidateUrl(beforeHref);
    const currentUrl = parseCandidateUrl(location.href);
    if (!beforeUrl || !currentUrl || !isYouTubeWatchLikeUrl(currentUrl)) {
      return false;
    }

    const preservedKeys = ['list', 'start_radio', 'pp', 'feature', 'si'];
    let changed = false;
    for (const key of preservedKeys) {
      if (beforeUrl.searchParams.has(key) && !currentUrl.searchParams.has(key)) {
        currentUrl.searchParams.set(key, beforeUrl.searchParams.get(key));
        changed = true;
      }
    }

    if (!changed) {
      return false;
    }

    try {
      history.replaceState(history.state, '', currentUrl.toString());
      scheduleRefresh('preserve_playlist_url_context');
      return true;
    } catch (e) {
      return false;
    }
  }

  function extractVideoIdFromUrl(candidateUrl) {
    if (!candidateUrl) {
      return '';
    }
    if (candidateUrl.hostname === 'youtu.be') {
      return candidateUrl.pathname.replace(/^\/+/, '') || '';
    }
    return candidateUrl.searchParams.get('v') || '';
  }

  function isYouTubeWatchLikeUrl(candidateUrl) {
    if (!candidateUrl) {
      return false;
    }
    const hostname = String(candidateUrl.hostname || '').toLowerCase();
    if (!kYouTubeHosts.has(hostname) && hostname !== 'youtu.be') {
      return false;
    }
    return candidateUrl.pathname === '/watch'
        || hostname === 'youtu.be'
        || candidateUrl.pathname.includes('/watch');
  }

  function collectElementLabels(el) {
    if (!el) {
      return [];
    }

    const values = [
      el.getAttribute?.('aria-label'),
      el.getAttribute?.('title'),
      el.getAttribute?.('data-title-no-tooltip'),
      el.getAttribute?.('data-tooltip-text'),
      el.getAttribute?.('data-tooltip-target-id'),
      el.getAttribute?.('aria-keyshortcuts'),
      el.textContent,
    ];

    return values.map(normalizedLabel).filter(Boolean);
  }

  function focusPlayerSurface() {
    const candidates = [
      currentVideo(),
      document.getElementById('movie_player'),
      document.querySelector('.html5-video-player'),
      document.querySelector('ytmusic-player-bar'),
      document.body,
      document.documentElement,
    ];
    for (const candidate of candidates) {
      if (!candidate || typeof candidate.focus !== 'function') {
        continue;
      }
      try {
        candidate.focus({preventScroll: true});
      } catch (e) {
        try {
          candidate.focus();
        } catch (ignored) {}
      }
      if (document.activeElement === candidate) {
        return true;
      }
    }
    return false;
  }

  function snapshotTrackIdentity() {
    const video = currentVideo();
    return {
      href: String(location.href || ''),
      title: normalizeTitle(document.title) || '',
      src: video ? String(video.currentSrc || video.src || '') : '',
      currentTime:
          video && Number.isFinite(video.currentTime) ? video.currentTime : null,
    };
  }

  function didTrackActionChange(kind, beforeSnapshot, afterSnapshot) {
    if (!afterSnapshot) {
      return false;
    }
    if (beforeSnapshot.href !== afterSnapshot.href) {
      return true;
    }
    if (beforeSnapshot.src && afterSnapshot.src
        && beforeSnapshot.src !== afterSnapshot.src) {
      return true;
    }
    if (beforeSnapshot.title && afterSnapshot.title
        && beforeSnapshot.title !== afterSnapshot.title) {
      return true;
    }
    if (kind === 'previous'
        && Number.isFinite(beforeSnapshot.currentTime)
        && beforeSnapshot.currentTime > 4
        && Number.isFinite(afterSnapshot.currentTime)
        && afterSnapshot.currentTime < 1.5) {
      // Some previous-track UIs restart the current video first.
      return true;
    }
    return false;
  }

  async function waitForTrackActionOutcome(kind, beforeSnapshot) {
    for (let attempt = 0; attempt < 7; ++attempt) {
      await new Promise((resolve) => window.setTimeout(resolve, 120));
      if (didTrackActionChange(kind, beforeSnapshot, snapshotTrackIdentity())) {
        return true;
      }
    }
    return false;
  }

  async function waitForTrackActionOutcomeWithBudget(kind, beforeSnapshot, attempts, delayMs) {
    const totalAttempts = Math.max(1, Number(attempts) || 1);
    const waitMs = Math.max(40, Number(delayMs) || 120);
    for (let attempt = 0; attempt < totalAttempts; ++attempt) {
      await new Promise((resolve) => window.setTimeout(resolve, waitMs));
      if (didTrackActionChange(kind, beforeSnapshot, snapshotTrackIdentity())) {
        return true;
      }
    }
    return false;
  }

  function wait(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function queueTrackContextRefresh(reason) {
    observedVideo = null;
    lastTrackFallbackSucceeded = false;
    lastTrackFallbackKind = '';
    lastTrackFallbackAt = 0;
    const delays = [0, 100, 260, 520, 900];
    for (const delay of delays) {
      window.setTimeout(() => {
        observedVideo = null;
        scheduleRefresh(reason + '_' + delay);
      }, delay);
    }
  }

  async function settleTrackContext(kind, beforeSnapshot, reason) {
    const settlePromise = (async function() {
      const changed = await waitForTrackActionOutcomeWithBudget(
          kind, beforeSnapshot, 18, 140);
      if (!changed) {
        return false;
      }
      queueTrackContextRefresh(reason);
      await new Promise((resolve) => window.setTimeout(resolve, 180));
      return true;
    }());

    trackSettleState = {kind, promise: settlePromise};
    try {
      return await settlePromise;
    } finally {
      if (trackSettleState && trackSettleState.promise === settlePromise) {
        trackSettleState = null;
      }
    }
  }

  function strategyResult(ok, strategy, reason) {
    const result = {ok, strategy};
    if (reason) {
      result.reason = reason;
    }
    return result;
  }

  function canUseYouTubeIframeApi() {
    return !!findYouTubeIframePlayer();
  }

  function findYouTubeIframePlayer() {
    const maybeYT = window.YT;
    if (!maybeYT || typeof maybeYT.get !== 'function') {
      return null;
    }
    const frames = document.querySelectorAll(
        'iframe[id][src*="youtube.com/embed"], '
        + 'iframe[id][src*="youtube-nocookie.com/embed"]');
    for (const frame of frames) {
      try {
        const player = maybeYT.get(frame.id);
        if (player) {
          return player;
        }
      } catch (e) {}
    }
    return null;
  }

  function isUsableTrackPlayer(player) {
    return !!player
        && (typeof player.nextVideo === 'function'
            || typeof player.previousVideo === 'function');
  }

  function findYouTubeTrackPlayer() {
    const candidates = [
      document.getElementById('movie_player'),
      window.movie_player,
      window.ytplayer?.player_,
      window.ytplayer?.app?.player,
    ];
    for (const candidate of candidates) {
      if (isUsableTrackPlayer(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  function getReliablePlayerTrackContext() {
    if (!isYouTubeHost()) {
      return null;
    }
    const player = findYouTubeTrackPlayer();
    if (!player) {
      return null;
    }

    let playlist = null;
    let index = -1;
    try {
      if (typeof player.getPlaylist === 'function') {
        const maybePlaylist = player.getPlaylist();
        if (Array.isArray(maybePlaylist)) {
          playlist = maybePlaylist.filter(Boolean).map((item) => String(item));
        }
      }
    } catch (e) {}
    try {
      if (typeof player.getPlaylistIndex === 'function') {
        index = Number(player.getPlaylistIndex());
      }
    } catch (e) {}

    if ((!playlist || playlist.length <= 1) && !isPlaylistContext()) {
      return null;
    }

    if ((!Number.isFinite(index) || index < 0) && playlist && playlist.length > 1) {
      const currentVideoId = currentVideoIdFromUrl();
      if (currentVideoId) {
        index = playlist.findIndex((item) => item === currentVideoId);
      }
    }

    return {
      player,
      playlist,
      index: Number.isFinite(index) ? index : -1,
    };
  }

  function hasReliablePlayerTrackCapability(kind) {
    const context = getReliablePlayerTrackContext();
    if (!context) {
      return false;
    }
    const methodName = kind === 'next' ? 'nextVideo' : 'previousVideo';
    if (typeof context.player[methodName] !== 'function') {
      return false;
    }
    if (Array.isArray(context.playlist) && context.playlist.length > 1
        && context.index >= 0) {
      return kind === 'next' ? context.index < context.playlist.length - 1
                             : context.index > 0;
    }
    return isPlaylistContext();
  }

  async function tryYouTubePlayerTrack(kind) {
    const context = getReliablePlayerTrackContext();
    if (!context) {
      return strategyResult(false, 'player-api', 'unavailable');
    }
    const methodName = kind === 'next' ? 'nextVideo' : 'previousVideo';
    const action = context.player[methodName];
    if (typeof action !== 'function') {
      return strategyResult(false, 'player-api', 'method-unavailable');
    }
    const beforeSnapshot = snapshotTrackIdentity();
    const beforeHref = String(location.href || '');
    try {
      action.call(context.player);
      scheduleRefresh('player_' + kind);
      const ok = await settleTrackContext(kind, beforeSnapshot, 'player_' + kind);
      if (ok) {
        preservePlaylistUrlContext(beforeHref);
      }
      return ok ? strategyResult(true, 'player-api')
                : strategyResult(false, 'player-api', 'unsettled');
    } catch (e) {
      return strategyResult(false, 'player-api', 'exception');
    }
  }

  async function tryYouTubeIframeNext() {
    const player = findYouTubeIframePlayer();
    if (!player || typeof player.nextVideo !== 'function') {
      return strategyResult(false, 'iframe-api', 'unavailable');
    }
    try {
      player.nextVideo();
      scheduleRefresh('iframe_next');
      return strategyResult(true, 'iframe-api');
    } catch (e) {
      return strategyResult(false, 'iframe-api', 'exception');
    }
  }

  async function tryYouTubeIframePrevious() {
    const player = findYouTubeIframePlayer();
    if (!player || typeof player.previousVideo !== 'function') {
      return strategyResult(false, 'iframe-api', 'unavailable');
    }
    try {
      player.previousVideo();
      scheduleRefresh('iframe_previous');
      return strategyResult(true, 'iframe-api');
    } catch (e) {
      return strategyResult(false, 'iframe-api', 'exception');
    }
  }

  async function tryGenericMediaSessionTrack(kind) {
    return strategyResult(false, 'media-session',
        'browser-tab-no-generic-track-api:' + kind);
  }

  function dispatchShortcut(key, code) {
    const targets = [
      document.activeElement,
      currentVideo(),
      document.getElementById('movie_player'),
      document.body,
      document.documentElement,
      document,
    ].filter(Boolean);
    const eventInit = {
      key,
      code,
      shiftKey: true,
      bubbles: true,
      cancelable: true,
      composed: true,
    };
    let dispatched = false;
    for (const target of targets) {
      try {
        dispatched =
            !!target.dispatchEvent(new KeyboardEvent('keydown', eventInit))
            || dispatched;
      } catch (e) {}
      try {
        dispatched =
            !!target.dispatchEvent(new KeyboardEvent('keyup', eventInit))
            || dispatched;
      } catch (e) {}
    }
    return dispatched;
  }

  async function tryYouTubeShortcutNext() {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'shortcut', 'unsupported-host');
    }
    if (focusedEditableElement()) {
      return strategyResult(false, 'shortcut', 'editable-focus');
    }
    focusPlayerSurface();
    const beforeSnapshot = snapshotTrackIdentity();
    if (!dispatchShortcut('N', 'KeyN')) {
      return strategyResult(false, 'shortcut', 'dispatch-failed');
    }
    scheduleRefresh('shortcut_next');
    const ok = await waitForTrackActionOutcome('next', beforeSnapshot);
    return ok ? strategyResult(true, 'shortcut')
              : strategyResult(false, 'shortcut', 'no-track-change');
  }

  async function tryYouTubeShortcutPrevious() {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'shortcut', 'unsupported-host');
    }
    if (focusedEditableElement()) {
      return strategyResult(false, 'shortcut', 'editable-focus');
    }
    focusPlayerSurface();
    const beforeSnapshot = snapshotTrackIdentity();
    if (!dispatchShortcut('P', 'KeyP')) {
      return strategyResult(false, 'shortcut', 'dispatch-failed');
    }
    scheduleRefresh('shortcut_previous');
    const ok = await waitForTrackActionOutcome('previous', beforeSnapshot);
    return ok ? strategyResult(true, 'shortcut')
              : strategyResult(false, 'shortcut', 'no-track-change');
  }

  function scoreTrackButtonCandidate(el, kind) {
    if (!isActionable(el)) {
      return -1;
    }
    let score = playerLikeRoot(el) ? 2 : 0;
    const ancestorText = ancestorDescriptorText(el);
    if (/(player|control|chrome|transport)/.test(ancestorText)) {
      score += 2;
    }
    if (/(playlist|queue|autoplay|next|related|watch-next)/.test(ancestorText)) {
      score += 2;
    }
    const labels = collectElementLabels(el);
    const tokens = kind === 'next' ? kNextLabelTokens : kPreviousLabelTokens;
    for (const label of labels) {
      for (const token of tokens) {
        if (label.includes(token)) {
          score += 6;
        }
      }
      if (kind === 'next' && label.includes('shift+n')) {
        score += 2;
      }
      if (kind === 'previous' && label.includes('shift+p')) {
        score += 2;
      }
    }
    const tagName = String(el.tagName || '').toLowerCase();
    if (tagName === 'button' || tagName === 'tp-yt-paper-icon-button') {
      score += 1;
    }
    return score;
  }

  function playerTransportRoots() {
    return Array.from(new Set([
      playerLikeRoot(currentVideo()),
      document.querySelector('.ytp-chrome-controls'),
      document.getElementById('movie_player'),
      document.querySelector('.html5-video-player'),
      document.querySelector('ytmusic-player-bar'),
      document.querySelector('ytmusic-player-page'),
    ].filter(Boolean)));
  }

  function candidateRoots() {
    const roots = [
      ...playerTransportRoots(),
      document.querySelector('ytm-single-column-watch-next-results-renderer'),
      document.querySelector('ytm-watch-next-secondary-results-renderer'),
      document.querySelector('ytd-watch-flexy'),
      document.querySelector('ytd-playlist-panel-renderer'),
      document.querySelector('ytmusic-player-queue'),
    ];
    return Array.from(
        new Set([...roots.filter(Boolean), ...collectSearchRoots()]));
  }

  function findTrackButton(kind) {
    nudgePlayerTransportControls();

    return findReliableTransportButton(kind, true);
  }

  function findReliableTransportButton(kind, requireActionable) {
    const selectors =
        kind === 'next' ? kLastResortNextSelectors : kLastResortPreviousSelectors;
    for (const root of playerTransportRoots()) {
      for (const selector of selectors) {
        try {
          const candidate = root.querySelector(selector);
          const usable = requireActionable ? isActionable(candidate)
                                           : isConnectedAndEnabled(candidate);
          if (usable) {
            return candidate;
          }
        } catch (e) {}
      }
    }

    let bestCandidate = null;
    let bestScore = -1;
    for (const root of playerTransportRoots()) {
      let candidates = [];
      try {
        candidates = Array.from(root.querySelectorAll(
            'button, [role="button"], tp-yt-paper-icon-button, '
            + 'yt-button-shape button'));
      } catch (e) {}
      for (const candidate of candidates) {
        const score = scoreTrackButtonCandidate(candidate, kind);
        if (score >= 8 && score > bestScore) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }
    }
    if (bestCandidate) {
      return bestCandidate;
    }
    return null;
  }

  function hasReliableTransportCapability(kind) {
    if (!isYouTubeHost()) {
      return false;
    }
    return !!findReliableTransportButton(kind, false);
  }

  function findYouTubeNextButton() {
    return findTrackButton('next');
  }

  function findYouTubePreviousButton() {
    return findTrackButton('previous');
  }

  function findReliableTrackHref(kind) {
    if (!isPlaylistContext()) {
      return '';
    }
    return findTrackHrefInPlaylistPanel(kind) || findTrackHrefInInitialData(kind);
  }

  function elementLooksSelected(el, currentVideoId) {
    if (!el || !el.isConnected) {
      return false;
    }
    const selectedValue = String(
        el.getAttribute?.('aria-current')
        || el.getAttribute?.('selected')
        || el.getAttribute?.('aria-selected')
        || '').toLowerCase();
    if (selectedValue === 'true' || selectedValue === 'page'
        || selectedValue === 'step' || selectedValue === 'location') {
      return true;
    }
    const selectedAncestor = typeof el.closest === 'function'
        ? el.closest(
            '[aria-current],[selected],[aria-selected="true"],'
            + '.selected,.is-selected,.current,.ytmusic-player-queue-item--selected')
        : null;
    if (selectedAncestor) {
      return true;
    }
    const candidateUrl = parseCandidateUrl(el.getAttribute?.('href'));
    const candidateVideoId = extractVideoIdFromUrl(candidateUrl);
    return !!candidateVideoId && !!currentVideoId && candidateVideoId === currentVideoId;
  }

  function findReliableTrackLink(kind) {
    if (!isPlaylistContext()) {
      return null;
    }

    const currentVideoId = currentVideoIdFromUrl();
    for (const root of candidateRoots()) {
      let links = [];
      try {
        links = Array.from(root.querySelectorAll('a[href]'));
      } catch (e) {}
      const candidates = [];
      for (const link of links) {
        const candidateUrl = parseCandidateUrl(link.getAttribute('href'));
        if (!isYouTubeWatchLikeUrl(candidateUrl)) {
          continue;
        }
        const candidateVideoId = extractVideoIdFromUrl(candidateUrl);
        const href = canonicalTrackHref(candidateUrl.toString());
        if (!href) {
          continue;
        }
        candidates.push({
          link,
          href,
          videoId: candidateVideoId,
          selected: elementLooksSelected(link, currentVideoId),
        });
      }
      if (!candidates.length) {
        continue;
      }

      let selectedIndex = candidates.findIndex((candidate) => candidate.selected);
      if (selectedIndex < 0 && currentVideoId) {
        selectedIndex = candidates.findIndex(
            (candidate) => candidate.videoId && candidate.videoId === currentVideoId);
      }
      if (selectedIndex < 0) {
        continue;
      }

      const delta = kind === 'next' ? 1 : -1;
      for (let index = selectedIndex + delta;
           index >= 0 && index < candidates.length; index += delta) {
        if (isActionable(candidates[index].link)) {
          return candidates[index].link;
        }
      }
    }
    return null;
  }

  function dispatchPrimaryClick(el) {
    if (!el || !el.isConnected) {
      return false;
    }
    const rect = typeof el.getBoundingClientRect === 'function'
        ? el.getBoundingClientRect()
        : {left: 0, top: 0, width: 0, height: 0};
    const clientX = Math.round((rect.left || 0) + Math.max(8, (rect.width || 0) / 2));
    const clientY = Math.round((rect.top || 0) + Math.max(8, (rect.height || 0) / 2));
    const pointerInit = {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1,
      clientX,
      clientY,
      pointerId: 1,
      pointerType: 'mouse',
      isPrimary: true,
      view: window,
    };
    const mouseInit = {
      bubbles: true,
      cancelable: true,
      composed: true,
      button: 0,
      buttons: 1,
      clientX,
      clientY,
      view: window,
    };
    try {
      if (typeof el.focus === 'function') {
        el.focus({preventScroll: true});
      }
    } catch (e) {}
    try {
      el.dispatchEvent(new PointerEvent('pointerdown', pointerInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('mousedown', mouseInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new PointerEvent('pointerup', pointerInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('mouseup', mouseInit));
    } catch (e) {}
    try {
      el.dispatchEvent(new MouseEvent('click', mouseInit));
      return true;
    } catch (e) {}
    try {
      el.click();
      return true;
    } catch (e) {}
    return false;
  }

  function hasReliableTrackCapability(kind, options) {
    const preferCachedPlaylistPanel = !!options?.preferCachedPlaylistPanel;
    const playlistPanelHref = preferCachedPlaylistPanel
        ? findTrackHrefInCachedPlaylistPanel(kind)
        : findTrackHrefInPlaylistPanel(kind);
    return !!playlistPanelHref
        || hasReliablePlayerTrackCapability(kind)
        || hasReliableTransportCapability(kind)
        || !!findReliableTrackLink(kind);
  }

  function canonicalTrackHref(rawHref) {
    const candidateUrl = parseCandidateUrl(rawHref);
    if (!isYouTubeWatchLikeUrl(candidateUrl)) {
      return '';
    }
    const currentVideoId = currentVideoIdFromUrl();
    const candidateVideoId = extractVideoIdFromUrl(candidateUrl);
    if (candidateVideoId && currentVideoId && candidateVideoId === currentVideoId) {
      return '';
    }
    return candidateUrl ? candidateUrl.toString() : '';
  }

  function extractTrackRenderer(item) {
    return item?.playlistPanelVideoRenderer
        || item?.playlistVideoRenderer
        || item?.compactVideoRenderer
        || item?.videoWithContextRenderer
        || item?.gridVideoRenderer
        || item?.videoRenderer
        || item?.richItemRenderer?.content?.videoRenderer
        || item?.richItemRenderer?.content?.compactVideoRenderer
        || null;
  }

  function extractRendererHref(renderer) {
    if (!renderer || typeof renderer !== 'object') {
      return '';
    }
    const watchEndpoint = renderer?.navigationEndpoint?.watchEndpoint;
    if (watchEndpoint && typeof watchEndpoint === 'object') {
      try {
        const candidateUrl = new URL('/watch', location.origin);
        if (watchEndpoint.videoId) {
          candidateUrl.searchParams.set('v', String(watchEndpoint.videoId));
        }
        if (watchEndpoint.playlistId) {
          candidateUrl.searchParams.set('list', String(watchEndpoint.playlistId));
        }
        if (watchEndpoint.index !== undefined && watchEndpoint.index !== null
            && String(watchEndpoint.index) !== '') {
          candidateUrl.searchParams.set('index', String(watchEndpoint.index));
        }
        return candidateUrl.toString();
      } catch (e) {}
    }
    return String(
        renderer?.navigationEndpoint?.commandMetadata?.webCommandMetadata?.url
        || renderer?.navigationEndpoint?.urlEndpoint?.url
        || renderer?.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl
        || '');
  }

  function extractRendererVideoId(renderer) {
    if (!renderer || typeof renderer !== 'object') {
      return '';
    }
    const directVideoId = String(
        renderer?.videoId || renderer?.navigationEndpoint?.watchEndpoint?.videoId || '');
    if (directVideoId) {
      return directVideoId;
    }
    return extractVideoIdFromUrl(parseCandidateUrl(extractRendererHref(renderer)));
  }

  function rendererLooksSelected(renderer, currentVideoId) {
    if (!renderer || typeof renderer !== 'object') {
      return false;
    }
    if (renderer.selected === true) {
      return true;
    }
    const selectionState = String(
        renderer?.selected || renderer?.isSelected || renderer?.isCurrent || '')
                               .toLowerCase();
    if (selectionState === 'true') {
      return true;
    }
    const candidateVideoId = extractRendererVideoId(renderer);
    return !!candidateVideoId && !!currentVideoId && candidateVideoId === currentVideoId;
  }

  function findTrackHrefInRendererArray(items, kind) {
    if (!Array.isArray(items) || !items.length) {
      return '';
    }

    const currentVideoId = currentVideoIdFromUrl();
    const candidates = [];
    for (const item of items) {
      const renderer = extractTrackRenderer(item);
      if (!renderer) {
        continue;
      }
      candidates.push({
        href: canonicalTrackHref(extractRendererHref(renderer)),
        videoId: extractRendererVideoId(renderer),
        selected: rendererLooksSelected(renderer, currentVideoId),
      });
    }

    if (!candidates.length) {
      return '';
    }

    let selectedIndex = candidates.findIndex((candidate) => candidate.selected);
    if (selectedIndex < 0 && currentVideoId) {
      selectedIndex = candidates.findIndex(
          (candidate) => candidate.videoId && candidate.videoId === currentVideoId);
    }

    if (selectedIndex >= 0) {
      const delta = kind === 'next' ? 1 : -1;
      for (let index = selectedIndex + delta;
           index >= 0 && index < candidates.length; index += delta) {
        if (candidates[index]?.href) {
          return candidates[index].href;
        }
      }
    }

    return '';
  }

  function getPlaylistPanelItemsFromInitialData() {
    return window.ytInitialData?.contents?.singleColumnWatchNextResults?.playlist?.playlist
               ?.contents
        || null;
  }

  function buildPlaylistPanelCandidates(items) {
    const candidates = [];
    if (!Array.isArray(items)) {
      return candidates;
    }
    for (const item of items) {
      const renderer = extractTrackRenderer(item);
      if (!renderer) {
        continue;
      }
      const href = canonicalTrackHref(extractRendererHref(renderer));
      const videoId = extractRendererVideoId(renderer);
      candidates.push({
        href,
        videoId,
        selected: !!renderer.selected,
      });
    }
    return candidates;
  }

  function resolvePlaylistCandidateIndex(candidates, currentVideoId) {
    if (!Array.isArray(candidates) || !candidates.length) {
      return -1;
    }

    if (currentVideoId) {
      const byCurrentVideoId = candidates.findIndex(
          (candidate) => candidate.videoId && candidate.videoId === currentVideoId);
      if (byCurrentVideoId >= 0) {
        return byCurrentVideoId;
      }
    }

    const selectedIndex = candidates.findIndex((candidate) => candidate.selected);
    if (selectedIndex >= 0) {
      const selectedVideoId = candidates[selectedIndex]?.videoId || '';
      if (!currentVideoId || (selectedVideoId && selectedVideoId === currentVideoId)) {
        return selectedIndex;
      }
    }

    const hintedIndex = currentPlaylistIndexHint();
    if (hintedIndex >= 0 && hintedIndex < candidates.length) {
      const hintedVideoId = candidates[hintedIndex]?.videoId || '';
      if (!currentVideoId || !hintedVideoId || hintedVideoId === currentVideoId) {
        return hintedIndex;
      }
    }

    return -1;
  }

  function refreshReliablePlaylistContext(reason) {
    if (shouldReuseReliablePlaylistContext(reason)) {
      lastReliablePlaylistContext.updatedAt = Date.now();
      lastReliablePlaylistContext.reason = String(reason || '') + '_cached';
      return;
    }

    const items = getPlaylistPanelItemsFromInitialData();
    const candidates = buildPlaylistPanelCandidates(items);
    if (!candidates.length) {
      return;
    }

    const currentVideoId = currentVideoIdFromUrl();
    const currentIndex = resolvePlaylistCandidateIndex(candidates, currentVideoId);
    if (currentIndex < 0 || !candidates[currentIndex]?.href) {
      return;
    }

    lastReliablePlaylistContext = {
      key: currentPlaylistContextKey(),
      candidates,
      currentIndex,
      currentVideoId,
      updatedAt: Date.now(),
      reason: String(reason || ''),
    };
  }

  function canReuseReliablePlaylistContext() {
    const context = lastReliablePlaylistContext;
    if (!context || !Array.isArray(context.candidates) || !context.candidates.length) {
      return false;
    }

    const currentKey = currentPlaylistContextKey();
    if (!currentKey || !context.key || currentKey !== context.key) {
      return false;
    }

    const currentVideoId = currentVideoIdFromUrl();
    if (!currentVideoId) {
      return false;
    }

    if (context.currentVideoId === currentVideoId) {
      return true;
    }

    return context.candidates.some(
        (candidate) => candidate && candidate.videoId === currentVideoId);
  }

  function shouldReuseReliablePlaylistContext(reason) {
    if (String(reason || '') !== 'keepalive') {
      return false;
    }
    if (!canReuseReliablePlaylistContext()) {
      return false;
    }
    const updatedAt = Number(lastReliablePlaylistContext?.updatedAt || 0);
    return !updatedAt || Date.now() - updatedAt < kReliablePlaylistContextReuseMs;
  }

  function findTrackHrefInCachedPlaylistPanel(kind) {
    const context = lastReliablePlaylistContext;
    if (!context || !Array.isArray(context.candidates) || !context.candidates.length) {
      return '';
    }

    let currentIndex = -1;
    const currentVideoId = currentVideoIdFromUrl();
    if (currentVideoId) {
      currentIndex = context.candidates.findIndex(
          (candidate) => candidate.videoId && candidate.videoId === currentVideoId);
    }

    if (currentIndex < 0) {
      const currentKey = currentPlaylistContextKey();
      if (currentKey && context.key && currentKey === context.key) {
        const hintedIndex = currentPlaylistIndexHint();
        if (hintedIndex >= 0 && hintedIndex < context.candidates.length) {
          currentIndex = hintedIndex;
        }
      }
    }

    if (currentIndex < 0) {
      return '';
    }

    const delta = kind === 'next' ? 1 : -1;
    for (let index = currentIndex + delta;
         index >= 0 && index < context.candidates.length; index += delta) {
      if (context.candidates[index]?.href) {
        return context.candidates[index].href;
      }
    }

    return '';
  }

  function findTrackHrefInPlaylistPanel(kind) {
    const items = getPlaylistPanelItemsFromInitialData();
    const currentVideoId = currentVideoIdFromUrl();
    const candidates = buildPlaylistPanelCandidates(items).map((candidate) => ({
      href: candidate.href,
      videoId: candidate.videoId,
      selected: candidate.selected,
    }));
    if (Array.isArray(items) && items.length && candidates.length) {
      for (let index = 0; index < items.length && index < candidates.length; ++index) {
        const renderer = extractTrackRenderer(items[index]);
        if (!renderer) {
          continue;
        }
        candidates[index].selected = rendererLooksSelected(renderer, currentVideoId);
      }
    }

    const currentIndex = resolvePlaylistCandidateIndex(candidates, currentVideoId);
    if (currentIndex < 0) {
      return findTrackHrefInCachedPlaylistPanel(kind);
    }

    const delta = kind === 'next' ? 1 : -1;
    for (let index = currentIndex + delta;
         index >= 0 && index < candidates.length; index += delta) {
      if (candidates[index]?.href) {
        return candidates[index].href;
      }
    }

    return findTrackHrefInCachedPlaylistPanel(kind);
  }

  function findTrackHrefInInitialData(kind) {
    const visited = new Set();
    let bestHref = '';

    const walk = (value, depth) => {
      if (!value || bestHref || depth > 14) {
        return;
      }

      if (Array.isArray(value)) {
        const href = findTrackHrefInRendererArray(value, kind);
        if (href) {
          bestHref = href;
          return;
        }
        for (const item of value) {
          walk(item, depth + 1);
          if (bestHref) {
            return;
          }
        }
        return;
      }

      if (typeof value !== 'object' || visited.has(value)) {
        return;
      }
      visited.add(value);
      for (const child of Object.values(value)) {
        walk(child, depth + 1);
        if (bestHref) {
          return;
        }
      }
    };

    try {
      walk(window.ytInitialData, 0);
    } catch (e) {}
    return bestHref;
  }

  async function navigateTrackHref(kind, targetHref, reason, options) {
    const beforeSnapshot = snapshotTrackIdentity();
    if (options && options.preserveVideoPresentation
        && typeof window.__onetabtubeArmVideoPresentation === 'function') {
      try {
        window.__onetabtubeArmVideoPresentation(
            targetHref, 'native_track_' + kind);
      } catch (e) {}
    }
    const navigateWatch =
        typeof window.__onetabtubeNavigateWatch === 'function'
            ? window.__onetabtubeNavigateWatch
            : null;
    if (navigateWatch) {
      try {
        const handled = !!navigateWatch(
            targetHref, 'native_track_' + kind, {warmTarget: true});
        if (handled) {
          const changed = await settleTrackContext(
              kind, beforeSnapshot, reason + '_pipeline');
          return changed ? strategyResult(true, 'dom', reason + '-pipeline')
                         : strategyResult(false, 'dom', reason + '-pipeline-unsettled');
        }
      } catch (e) {}
    }
    try {
      location.assign(targetHref);
      return strategyResult(true, 'dom', reason);
    } catch (e) {
      const changed = await waitForTrackActionOutcome(kind, beforeSnapshot);
      return changed ? strategyResult(true, 'dom', reason)
                     : strategyResult(false, 'dom', reason + '-failed');
    }
  }

  async function tryYouTubeInitialDataNavigation(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'dom', 'unsupported-host');
    }

    if (!isPlaylistContext()) {
      return strategyResult(false, 'dom', 'initial-data-playlist-context-required');
    }

    const targetHref = findTrackHrefInPlaylistPanel(kind) || findReliableTrackHref(kind);
    if (!targetHref) {
      return strategyResult(false, 'dom', 'initial-data-link-not-found');
    }

    return navigateTrackHref(
        kind, targetHref, 'initial-data-navigation', options || {});
  }

  function scoreTrackLinkCandidate(link, kind) {
    if (!isActionable(link)) {
      return -1;
    }
    const candidateUrl = parseCandidateUrl(link.getAttribute('href'));
    if (!isYouTubeWatchLikeUrl(candidateUrl)) {
      return -1;
    }
    const currentVideoId = currentVideoIdFromUrl();
    const candidateVideoId = extractVideoIdFromUrl(candidateUrl);
    if (candidateVideoId && currentVideoId && candidateVideoId === currentVideoId) {
      return -1;
    }

    let score = 1;
    const labels = collectElementLabels(link);
    const ancestorText = ancestorDescriptorText(link);
    const tokens = kind === 'next' ? kNextLabelTokens : kPreviousLabelTokens;
    for (const label of labels) {
      for (const token of tokens) {
        if (label.includes(token)) {
          score += 6;
        }
      }
    }
    if (/(playlist|queue)/.test(ancestorText)) {
      score += 4;
    }
    if (/(autoplay|next|watch-next|related)/.test(ancestorText) && kind === 'next') {
      score += 3;
    }
    if (link.hasAttribute('aria-current')
        || String(link.getAttribute('selected') || '').toLowerCase() === 'true') {
      score -= 4;
    }
    if (isPlaylistContext()) {
      score += 1;
    }
    return score;
  }

  function findTrackLink(kind) {
    let bestCandidate = null;
    let bestScore = -1;
    for (const root of candidateRoots()) {
      let links = [];
      try {
        links = Array.from(root.querySelectorAll('a[href]'));
      } catch (e) {}
      for (const link of links) {
        const score = scoreTrackLinkCandidate(link, kind);
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = link;
        }
      }
    }
    return bestCandidate;
  }

  async function tryYouTubeDomLinkNavigation(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'dom', 'unsupported-host');
    }

    const link = findTrackLink(kind);
    if (!link) {
      return tryYouTubeInitialDataNavigation(
          kind, Object.assign({}, options || {}, {requirePlaylistContext: true}));
    }

    const candidateUrl = parseCandidateUrl(link.getAttribute('href'));
    if (!candidateUrl) {
      return tryYouTubeInitialDataNavigation(
          kind, Object.assign({}, options || {}, {requirePlaylistContext: true}));
    }

    return navigateTrackHref(
        kind, candidateUrl.toString(), 'link-navigation', options || {});
  }

  async function tryYouTubeDomTrack(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'dom', 'unsupported-host');
    }
    const beforeSnapshot = snapshotTrackIdentity();
    for (let attempt = 0; attempt < 3; ++attempt) {
      nudgePlayerTransportControls();
      if (attempt > 0) {
        await wait(90);
      }
      const button =
          kind === 'next' ? findYouTubeNextButton() : findYouTubePreviousButton();
      if (!button) {
        continue;
      }
      if (!clickTransportButton(button)) {
        continue;
      }
      scheduleRefresh('dom_' + kind + '_attempt_' + attempt);
      const ok = await settleTrackContext(
          kind, beforeSnapshot, 'dom_' + kind + '_attempt_' + attempt);
      if (ok) {
        return strategyResult(true, 'dom');
      }
    }
    return strategyResult(false, 'dom', 'transport-button-unavailable');
  }

  async function tryYouTubeDomTrackLink(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'dom', 'unsupported-host');
    }
    const beforeSnapshot = snapshotTrackIdentity();
    const link = findReliableTrackLink(kind);
    if (!link) {
      return strategyResult(false, 'dom', 'reliable-link-unavailable');
    }
    if (!dispatchPrimaryClick(link)) {
      return strategyResult(false, 'dom', 'reliable-link-dispatch-failed');
    }
    scheduleRefresh('dom_link_' + kind);
    const ok = await settleTrackContext(kind, beforeSnapshot, 'dom_link_' + kind);
    return ok ? strategyResult(true, 'dom', 'reliable-link-click')
              : strategyResult(false, 'dom', 'reliable-link-unsettled');
  }

  async function runTrackFallback(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'none', 'unsupported-host');
    }
    if (trackSettleState) {
      try {
        await trackSettleState.promise;
      } catch (e) {}
    }
    if (trackFallbackState) {
      if (trackFallbackState.kind === kind) {
        return trackFallbackState.promise;
      }
      return strategyResult(false, 'none', 'busy');
    }
    const now = Date.now();
    if (lastTrackFallbackSucceeded && lastTrackFallbackKind === kind
        && now - lastTrackFallbackAt < kTrackFallbackCooldownMs) {
      return strategyResult(false, 'none', 'throttled');
    }

    const runner = async function() {
      let result = strategyResult(false, 'none', 'no-strategy');
      const hasPlayerTrack = hasReliablePlayerTrackCapability(kind);
      const reliableTrackLink = findReliableTrackLink(kind);
      const playlistPanelHref = findTrackHrefInPlaylistPanel(kind);
      if (playlistPanelHref) {
        result = await navigateTrackHref(
            kind, playlistPanelHref, 'playlist-panel-navigation', options || {});
        debugLog(kind + '_playlist_panel', JSON.stringify(result));
        if (result.ok) {
          return result;
        }
      }
      const hasTransport = hasReliableTransportCapability(kind);
      if (hasTransport) {
        result = await tryYouTubeDomTrack(kind, options);
        debugLog(kind + '_dom', JSON.stringify(result));
        if (result.ok) {
          return result;
        }
        result = kind === 'next' ? await tryYouTubeShortcutNext()
                                 : await tryYouTubeShortcutPrevious();
        debugLog(kind + '_shortcut', JSON.stringify(result));
        if (result.ok) {
          return result;
        }
      } else {
        if (!hasPlayerTrack && !reliableTrackLink) {
          return strategyResult(false, 'none', 'unreliable-track-context');
        }
      }
      if (hasPlayerTrack
          && !isPlaylistContext()
          && !lastReliablePlaylistContext) {
        result = await tryYouTubePlayerTrack(kind);
        debugLog(kind + '_player_api', JSON.stringify(result));
        if (result.ok) {
          return result;
        }
      }
      result = await tryYouTubeDomTrackLink(kind, options);
      debugLog(kind + '_dom_link', JSON.stringify(result));
      return result;
    };

    const trackPromise = runner();
    trackFallbackState = {kind, promise: trackPromise};
    try {
      const result = await trackPromise;
      lastTrackFallbackKind = kind;
      lastTrackFallbackSucceeded = !!result?.ok;
      return result;
    } finally {
      lastTrackFallbackAt = Date.now();
      trackFallbackState = null;
    }
  }

  function getStateSnapshot(videoOverride, capabilityOverride) {
    const video = videoOverride || currentVideo();
    if (!video) {
      return null;
    }

    const duration = Number.isFinite(video.duration) ? video.duration : undefined;
    const currentTime =
        Number.isFinite(video.currentTime) ? video.currentTime : undefined;

    return {
      source: 'youtube-tab',
      title: normalizeTitle(document.title),
      playing: !video.paused && !video.ended,
      paused: !!video.paused,
      duration,
      currentTime,
      canNext: capabilityOverride && typeof capabilityOverride.canNext === 'boolean'
          ? capabilityOverride.canNext
          : hasReliableTrackCapability('next'),
      canPrevious: capabilityOverride
              && typeof capabilityOverride.canPrevious === 'boolean'
          ? capabilityOverride.canPrevious
          : hasReliableTrackCapability('previous'),
    };
  }

  function updatePlaybackState(state) {
    if (!navigator.mediaSession) {
      return;
    }
    const playbackState =
        !state ? 'none' : (state.playing ? 'playing' : 'paused');
    if (playbackState === lastPlaybackStateSignature) {
      return;
    }
    lastPlaybackStateSignature = playbackState;
    try {
      navigator.mediaSession.playbackState = playbackState;
    } catch (e) {}
  }

  function updatePositionState(state, video) {
    if (!navigator.mediaSession
        || typeof navigator.mediaSession.setPositionState !== 'function') {
      return;
    }

    if (!state || !Number.isFinite(state.duration) || state.duration <= 0
        || !Number.isFinite(state.currentTime)) {
      lastPositionStateSignature = '';
      return;
    }

    if (!video) {
      lastPositionStateSignature = '';
      return;
    }

    const playbackRate =
        Number.isFinite(video.playbackRate) ? video.playbackRate : 1;
    const position = Math.min(state.duration, Math.max(0, state.currentTime));
    const signature =
        [
          Math.round(state.duration * 2) / 2,
          Math.round(position * 2) / 2,
          Math.round(playbackRate * 100) / 100,
        ].join('|');
    if (signature === lastPositionStateSignature) {
      return;
    }
    lastPositionStateSignature = signature;

    try {
      navigator.mediaSession.setPositionState({
        duration: state.duration,
        playbackRate,
        position,
      });
    } catch (e) {}
  }

  function getPositionStateSnapshot(videoOverride) {
    const video = videoOverride || currentVideo();
    if (!video) {
      return null;
    }
    const duration = Number.isFinite(video.duration) ? video.duration : undefined;
    const currentTime =
        Number.isFinite(video.currentTime) ? video.currentTime : undefined;
    return {duration, currentTime};
  }

  function flushPositionStateUpdate() {
    positionRefreshTimer = 0;
    const video = currentVideo();
    const state = getPositionStateSnapshot(video);
    updatePositionState(state, video);
  }

  function schedulePositionStateUpdate() {
    if (positionRefreshTimer) {
      return;
    }
    positionRefreshTimer = setTimeout(() => {
      flushPositionStateUpdate();
    }, kPositionUpdateDebounceMs);
  }

  async function play() {
    const video = currentVideo();
    if (!video || typeof video.play !== 'function') {
      return false;
    }

    if (!video.paused && !video.ended) {
      const state = getStateSnapshot(video);
      updatePlaybackState(state);
      updatePositionState(state, video);
      return true;
    }

    try {
      const maybePromise = video.play();
      if (maybePromise && typeof maybePromise.then === 'function') {
        await maybePromise.catch(() => {});
      }
      scheduleRefresh('play');
      return true;
    } catch (e) {
      return false;
    }
  }

  async function pause() {
    const video = currentVideo();
    if (!video || typeof video.pause !== 'function') {
      return false;
    }

    if (video.paused || video.ended) {
      const state = getStateSnapshot(video);
      updatePlaybackState(state);
      updatePositionState(state, video);
      return true;
    }

    try {
      video.pause();
      scheduleRefresh('pause');
      return true;
    } catch (e) {
      return false;
    }
  }

  async function playPause() {
    const video = currentVideo();
    if (!video) {
      return false;
    }
    return video.paused || video.ended ? play() : pause();
  }

  async function seekTo(time) {
    const video = currentVideo();
    if (!video || !Number.isFinite(time)) {
      return false;
    }

    try {
      video.currentTime = Number(time);
      scheduleRefresh('seek_to');
      return true;
    } catch (e) {
      return false;
    }
  }

  async function seekBy(offsetSeconds) {
    const state = getStateSnapshot();
    if (!state || !Number.isFinite(state.currentTime) || !Number.isFinite(offsetSeconds)) {
      return false;
    }
    return seekTo(Math.max(0, state.currentTime + Number(offsetSeconds)));
  }

  function setActionHandler(action, handler) {
    if (!navigator.mediaSession
        || typeof navigator.mediaSession.setActionHandler !== 'function') {
      return;
    }
    try {
      navigator.mediaSession.setActionHandler(action, handler);
    } catch (e) {}
  }

  function refreshMediaSessionActions(hasVideo, canNext, canPrevious) {
    const signature =
        [hasVideo ? 1 : 0, canNext ? 1 : 0, canPrevious ? 1 : 0].join('|');
    if (signature === lastMediaSessionActionSignature) {
      return;
    }
    lastMediaSessionActionSignature = signature;

    setActionHandler('nexttrack', canNext ? () => {
      void bridge.next();
    } : null);
    setActionHandler('previoustrack', canPrevious ? () => {
      void bridge.previous();
    } : null);
    setActionHandler('play', hasVideo ? () => { void play(); } : null);
    setActionHandler('pause', hasVideo ? () => { void pause(); } : null);
    setActionHandler('seekforward', hasVideo ? () => {
      void seekBy(10);
    } : null);
    setActionHandler('seekbackward', hasVideo ? () => {
      void seekBy(-10);
    } : null);
    setActionHandler('seekto', hasVideo ? (details) => {
      if (details && Number.isFinite(details.seekTime)) {
        void seekTo(details.seekTime);
      }
    } : null);
  }

  function refreshMediaSession(reason) {
    const video = currentVideo();
    const hasVideo = !!video;
    if (shouldResolveReliablePlaylistContext(video)) {
      refreshReliablePlaylistContext(reason);
    }
    const preferCachedPlaylistPanel = shouldReuseReliablePlaylistContext(reason);
    const canNext = hasVideo && hasReliableTrackCapability(
        'next', {preferCachedPlaylistPanel});
    const canPrevious = hasVideo && hasReliableTrackCapability(
        'previous', {preferCachedPlaylistPanel});
    const state = getStateSnapshot(video, {canNext, canPrevious});

    refreshMediaSessionActions(hasVideo, canNext, canPrevious);
    updatePlaybackState(state);
    updatePositionState(state, video);
    updateKeepAliveState(video);
  }

  function updateKeepAliveState(video) {
    const shouldKeepAlive = !!video;
    if (!shouldKeepAlive) {
      if (keepAliveTimer) {
        clearInterval(keepAliveTimer);
        keepAliveTimer = 0;
      }
      return;
    }

    if (keepAliveTimer) {
      return;
    }

    keepAliveTimer = setInterval(() => {
      bindVideoEvents(currentVideo());
      refreshMediaSession('keepalive');
    }, kMediaSessionKeepAliveMs);
  }

  function forceRefreshMediaSession(reason) {
    observeLifecycle();
    bindVideoEvents(currentVideo());
    refreshMediaSession(reason);
  }

  function bindVideoEvents(video) {
    if (!video || video === observedVideo) {
      return;
    }

    observedVideo = video;
    const events = [
      'play',
      'pause',
      'playing',
      'loadstart',
      'canplay',
      'canplaythrough',
      'seeking',
      'seeked',
      'loadedmetadata',
      'durationchange',
      'ratechange',
      'waiting',
      'stalled',
      'emptied',
      'ended',
    ];
    for (const eventName of events) {
      video.addEventListener(eventName, () => scheduleRefresh(eventName), true);
    }
    video.addEventListener('timeupdate', () => schedulePositionStateUpdate(), true);
  }

  function scheduleRefresh(reason) {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => {
      forceRefreshMediaSession(reason);
    }, 80);
  }

  function elementMatchesBridgeMutationSelector(el) {
    if (!el || typeof el.matches !== 'function') {
      return false;
    }
    try {
      return el.matches(kBridgeRelevantMutationSelector);
    } catch (e) {
      return false;
    }
  }

  function nodeTouchesBridgeRelevantSubtree(node) {
    if (!node) {
      return false;
    }

    if (node.nodeType === Node.ELEMENT_NODE) {
      const el = /** @type {!Element} */ (node);
      if (elementMatchesBridgeMutationSelector(el)) {
        return true;
      }
      if (typeof el.closest === 'function') {
        try {
          if (el.closest(kBridgeRelevantMutationSelector)) {
            return true;
          }
        } catch (e) {}
      }
      if (typeof el.querySelector === 'function') {
        try {
          if (el.querySelector(kBridgeRelevantMutationSelector)) {
            return true;
          }
        } catch (e) {}
      }
      return false;
    }

    if (node.nodeType === Node.DOCUMENT_FRAGMENT_NODE
        && typeof node.querySelector === 'function') {
      try {
        return !!node.querySelector(kBridgeRelevantMutationSelector);
      } catch (e) {
        return false;
      }
    }

    return false;
  }

  function mutationNeedsBridgeRefresh(mutation) {
    if (!mutation) {
      return false;
    }
    if (nodeTouchesBridgeRelevantSubtree(mutation.target)) {
      return true;
    }
    for (const node of mutation.addedNodes || []) {
      if (nodeTouchesBridgeRelevantSubtree(node)) {
        return true;
      }
    }
    for (const node of mutation.removedNodes || []) {
      if (nodeTouchesBridgeRelevantSubtree(node)) {
        return true;
      }
    }
    return false;
  }

  function observeLifecycle() {
    if (lifecycleObserver || typeof MutationObserver !== 'function') {
      return;
    }

    if (!shouldObserveBridgeLifecycle()) {
      return;
    }

    const root = document.body || document.documentElement;
    if (!root) {
      return;
    }

    lifecycleObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations || []) {
        if (mutationNeedsBridgeRefresh(mutation)) {
          scheduleRefresh('mutation');
          return;
        }
      }
    });
    lifecycleObserver.observe(root, {childList: true, subtree: true});
  }

  const bridge = {
    isAvailable: async function() {
      return !!currentVideo();
    },
    getState: async function() {
      return getStateSnapshot();
    },
    playPause: async function() {
      return playPause();
    },
    play: async function() {
      return play();
    },
    pause: async function() {
      return pause();
    },
    seekTo: async function(time) {
      return seekTo(time);
    },
    seekBy: async function(offsetSeconds) {
      return seekBy(offsetSeconds);
    },
    next: async function(options) {
      return runTrackFallback('next', options || {});
    },
    previous: async function(options) {
      return runTrackFallback('previous', options || {});
    },
  };

  window.__oneTabTubeNativeTabBridge = bridge;
  scheduleRefresh('bootstrap');

  document.addEventListener(
      'DOMContentLoaded', () => scheduleRefresh('dom_ready'), true);
  document.addEventListener(
      'yt-page-data-updated', () => scheduleRefresh('yt_page_data_updated'),
      true);
  document.addEventListener(
      'yt-player-updated', () => scheduleRefresh('yt_player_updated'), true);
  document.addEventListener(
      'yt-navigate-finish', () => scheduleRefresh('yt_navigate_finish'), true);
  document.addEventListener(
      'visibilitychange', () => scheduleRefresh('visibilitychange'), true);
  window.addEventListener('pageshow', () => scheduleRefresh('pageshow'), true);
  window.addEventListener('pagehide', () => scheduleRefresh('pagehide'), true);
  window.addEventListener('focus', () => scheduleRefresh('focus'), true);
}());
)OTB_YT_BRIDGE";

}  // namespace

const char16_t* GetYouTubeNativeTabBridgeScript() {
  return kYouTubeNativeTabBridgeScript;
}

}  // namespace youtube_script_injector
