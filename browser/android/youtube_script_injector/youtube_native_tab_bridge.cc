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
  let trackFallbackState = null;
  let lastTrackFallbackAt = 0;
  let lastTrackFallbackKind = '';
  let lastTrackFallbackSucceeded = false;
  const kTrackFallbackCooldownMs = 250;
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

  function currentVideo() {
    return document.querySelector('video');
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

  function candidateRoots() {
    const roots = [
      playerLikeRoot(currentVideo()),
      document.querySelector('.ytp-chrome-controls'),
      document.getElementById('movie_player'),
      document.querySelector('.html5-video-player'),
      document.querySelector('ytmusic-player-bar'),
      document.querySelector('ytmusic-player-page'),
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
    let bestCandidate = null;
    let bestScore = -1;
    for (const root of candidateRoots()) {
      let candidates = [];
      try {
        candidates = Array.from(root.querySelectorAll(
            'button, [role="button"], tp-yt-paper-icon-button, '
            + 'yt-button-shape button, a[href]'));
      } catch (e) {}
      for (const candidate of candidates) {
        const score = scoreTrackButtonCandidate(candidate, kind);
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }
    }
    if (bestCandidate) {
      return bestCandidate;
    }

    // Last resort: use a small selector list for known transport buttons.
    const selectors =
        kind === 'next' ? kLastResortNextSelectors : kLastResortPreviousSelectors;
    for (const selector of selectors) {
      try {
        const candidate = document.querySelector(selector);
        if (isActionable(candidate)) {
          return candidate;
        }
      } catch (e) {}
    }
    return null;
  }

  function findYouTubeNextButton() {
    return findTrackButton('next');
  }

  function findYouTubePreviousButton() {
    return findTrackButton('previous');
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

    if (kind === 'next') {
      for (const candidate of candidates) {
        if (candidate?.href) {
          return candidate.href;
        }
      }
    }
    return '';
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

  async function tryRestartCurrentTrack() {
    const video = currentVideo();
    if (!video || !Number.isFinite(video.currentTime) || video.currentTime < 1.5) {
      return strategyResult(false, 'media-element', 'restart-unavailable');
    }
    const ok = await seekTo(0);
    return ok ? strategyResult(true, 'media-element', 'restart-current')
              : strategyResult(false, 'media-element', 'restart-failed');
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
          return strategyResult(true, 'dom', reason + '-pipeline');
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

    const targetHref = findTrackHrefInInitialData(kind);
    if (!targetHref) {
      return kind === 'previous' ? tryRestartCurrentTrack()
                                 : strategyResult(
                                       false, 'dom', 'initial-data-link-not-found');
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
      return tryYouTubeInitialDataNavigation(kind, options);
    }

    const candidateUrl = parseCandidateUrl(link.getAttribute('href'));
    if (!candidateUrl) {
      return tryYouTubeInitialDataNavigation(kind, options);
    }

    return navigateTrackHref(
        kind, candidateUrl.toString(), 'link-navigation', options || {});
  }

  async function tryYouTubeDomTrack(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'dom', 'unsupported-host');
    }
    const button =
        kind === 'next' ? findYouTubeNextButton() : findYouTubePreviousButton();
    if (!button) {
      return tryYouTubeDomLinkNavigation(kind, options);
    }
    const beforeSnapshot = snapshotTrackIdentity();
    if (!clickIfActionable(button)) {
      return tryYouTubeDomLinkNavigation(kind, options);
    }
    scheduleRefresh('dom_' + kind);
    const ok = await waitForTrackActionOutcome(kind, beforeSnapshot);
    if (ok) {
      return strategyResult(true, 'dom');
    }
    return tryYouTubeDomLinkNavigation(kind, options);
  }

  async function runTrackFallback(kind, options) {
    if (!isYouTubeHost()) {
      return strategyResult(false, 'none', 'unsupported-host');
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
      if (kind === 'next') {
        if (canUseYouTubeIframeApi()) {
          result = await tryYouTubeIframeNext();
          debugLog('next_iframe', JSON.stringify(result));
          if (result.ok) return result;
        }
        result = await tryGenericMediaSessionTrack('next');
        debugLog('next_media_session', JSON.stringify(result));
        if (result.ok) return result;
        result = await tryYouTubeShortcutNext();
        debugLog('next_shortcut', JSON.stringify(result));
        if (result.ok) return result;
        result = await tryYouTubeInitialDataNavigation('next', options);
        debugLog('next_initial_data', JSON.stringify(result));
        if (result.ok) return result;
        result = await tryYouTubeDomTrack('next', options);
        debugLog('next_dom', JSON.stringify(result));
        return result;
      }

      if (canUseYouTubeIframeApi()) {
        result = await tryYouTubeIframePrevious();
        debugLog('previous_iframe', JSON.stringify(result));
        if (result.ok) return result;
      }
      result = await tryGenericMediaSessionTrack('previous');
      debugLog('previous_media_session', JSON.stringify(result));
      if (result.ok) return result;
      result = await tryYouTubeShortcutPrevious();
      debugLog('previous_shortcut', JSON.stringify(result));
      if (result.ok) return result;
      result = await tryYouTubeInitialDataNavigation('previous', options);
      debugLog('previous_initial_data', JSON.stringify(result));
      if (result.ok) return result;
      result = await tryYouTubeDomTrack('previous', options);
      debugLog('previous_dom', JSON.stringify(result));
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

  function getStateSnapshot() {
    const video = currentVideo();
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
      canNext: isYouTubeHost(),
      canPrevious: isYouTubeHost(),
    };
  }

  function updatePlaybackState() {
    if (!navigator.mediaSession) {
      return;
    }
    const state = getStateSnapshot();
    try {
      navigator.mediaSession.playbackState =
          !state ? 'none' : (state.playing ? 'playing' : 'paused');
    } catch (e) {}
  }

  function updatePositionState() {
    if (!navigator.mediaSession
        || typeof navigator.mediaSession.setPositionState !== 'function') {
      return;
    }

    const state = getStateSnapshot();
    if (!state || !Number.isFinite(state.duration) || state.duration <= 0
        || !Number.isFinite(state.currentTime)) {
      return;
    }

    const video = currentVideo();
    if (!video) {
      return;
    }

    try {
      navigator.mediaSession.setPositionState({
        duration: state.duration,
        playbackRate: Number.isFinite(video.playbackRate) ? video.playbackRate : 1,
        position: Math.min(state.duration, Math.max(0, state.currentTime)),
      });
    } catch (e) {}
  }

  async function play() {
    const video = currentVideo();
    if (!video || typeof video.play !== 'function') {
      return false;
    }

    if (!video.paused && !video.ended) {
      updatePlaybackState();
      updatePositionState();
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
      updatePlaybackState();
      updatePositionState();
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

  function refreshMediaSession(reason) {
    const hasVideo = !!currentVideo();

    setActionHandler('nexttrack', hasVideo ? () => {
      void bridge.next();
    } : null);
    setActionHandler('previoustrack', hasVideo ? () => {
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

    updatePlaybackState();
    updatePositionState();
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
      'timeupdate',
      'seeking',
      'seeked',
      'loadedmetadata',
      'durationchange',
      'ratechange',
      'ended',
    ];
    for (const eventName of events) {
      video.addEventListener(eventName, () => scheduleRefresh(eventName), true);
    }
  }

  function scheduleRefresh(reason) {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => {
      bindVideoEvents(currentVideo());
      refreshMediaSession(reason);
    }, 80);
  }

  function observeLifecycle() {
    if (lifecycleObserver || typeof MutationObserver !== 'function') {
      return;
    }

    const root = document.body || document.documentElement;
    if (!root) {
      return;
    }

    lifecycleObserver = new MutationObserver(() => scheduleRefresh('mutation'));
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
  observeLifecycle();
  bindVideoEvents(currentVideo());
  refreshMediaSession('bootstrap');

  document.addEventListener(
      'DOMContentLoaded', () => scheduleRefresh('dom_ready'), true);
  document.addEventListener(
      'yt-navigate-finish', () => scheduleRefresh('yt_navigate_finish'), true);
  window.addEventListener('pageshow', () => scheduleRefresh('pageshow'), true);
  window.addEventListener('focus', () => scheduleRefresh('focus'), true);
}());
)OTB_YT_BRIDGE";

}  // namespace

const char16_t* GetYouTubeNativeTabBridgeScript() {
  return kYouTubeNativeTabBridgeScript;
}

}  // namespace youtube_script_injector
