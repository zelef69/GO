const String goPlayPreferNonAv1Script = '''
(function() {
  if (window.__go_playCodecPreferenceInstalled === true) {
    return;
  }
  window.__go_playCodecPreferenceInstalled = true;

  function isAv1CodecType(value) {
    if (!value) {
      return false;
    }
    var type = String(value).toLowerCase();
    return type.indexOf('av01') !== -1 ||
      type.indexOf('video/av1') !== -1 ||
      type.indexOf('codecs="av1') !== -1 ||
      type.indexOf('codecs=av1') !== -1;
  }

  try {
    if (
      window.MediaSource &&
      typeof window.MediaSource.isTypeSupported === 'function'
    ) {
      window.__go_playOriginalMediaSourceIsTypeSupported =
        window.MediaSource.isTypeSupported.bind(window.MediaSource);
      window.MediaSource.isTypeSupported = function(type) {
        if (isAv1CodecType(type)) {
          return false;
        }
        return window.__go_playOriginalMediaSourceIsTypeSupported(type);
      };
    }
  } catch (_) {}

  try {
    if (
      window.HTMLMediaElement &&
      window.HTMLMediaElement.prototype &&
      typeof window.HTMLMediaElement.prototype.canPlayType === 'function'
    ) {
      var proto = window.HTMLMediaElement.prototype;
      window.__go_playOriginalCanPlayType = proto.canPlayType;
      proto.canPlayType = function(type) {
        if (isAv1CodecType(type)) {
          return '';
        }
        return window.__go_playOriginalCanPlayType.call(this, type);
      };
    }
  } catch (_) {}
})();
''';

const String goPlayEnableAdblockScript = '''
(function() {
  var blockedHosts = [
    'doubleclick.net',
    '.doubleclick.net',
    'googlesyndication.com',
    '.googlesyndication.com',
    'googleadservices.com',
    '.googleadservices.com',
    'adservice.google.com',
    '.adservice.google.com',
    'pagead2.googlesyndication.com',
    'pubads.g.doubleclick.net',
    'securepubads.g.doubleclick.net'
  ];

  var youtubeAdPathTokens = [
    // Keep high-churn first-party telemetry fail-open in JS hooks too.
    // Avoid broad /pagead/ blocking because /pagead/interaction retries can
    // hold the player in an ad-recovery loop and delay real playback.
    '/get_midroll_info',
    '/ptracking',
    '/ad_break',
    '/youtubei/v1/player/ad_break',
    '/youtubei/v1/ad'
  ];

  var googleVideoAdQueryKeys = [
    'oad',
    'adformat',
    'ad_type',
    'ad_preroll',
    'dclk_video_ads',
    'ad3_module',
    'videoadid',
    'adtag',
    'ad_tag',
    'ad_debug',
    'adsid',
    'ad_host_tier',
    'ad_flags'
  ];

  var adSkipButtonSelectors = [
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-ad-skip-button-container button',
    '.ytp-ad-skip-button-slot button',
    'button[aria-label*="Skip"]',
    'button[aria-label*="skip"]',
    '[class*="skip-ad"] button'
  ];

  var adOverlayCloseSelectors = [
    '.ytp-ad-overlay-close-button',
    '.ytp-ad-overlay-container button[aria-label*="Close"]',
    '.ytp-ad-overlay-container button[aria-label*="close"]'
  ];

  var adNextSelectors = [
    '.ytp-next-button',
    '.ytp-next-button.ytp-button',
    'button[aria-label*="Next"]',
    'button[aria-label*="next"]',
    'button[title*="Next"]',
    'button[title*="next"]'
  ];

  // Tune for faster ad recovery to reduce black-screen stall before content starts.
  var adStuckNoProgressThresholdMs = 650;
  var adMaxVisibleThresholdMs = 4500;
  var forceAdRecoveryCooldownMs = 250;
  var adSeekForwardCooldownMs = 320;
  var adSeekMinReadyState = 2;
  var adHardRecoveryThresholdMs = 2200;
  var adStuckRecoveryMaxAttempts = 2;
  var enableHardReloadRecovery = false;
  var enableNetworkHooks = false;
  var blockGoogleVideoPlaybackAdQueries = false;
  var adHardReloadCooldownMs = 45000;
  var hardReloadBudgetStorageKey = 'go_play_ad_hard_reload_budget';

  function parseUrl(rawUrl) {
    if (!rawUrl) {
      return null;
    }
    try {
      return new URL(String(rawUrl), window.location.href);
    } catch (_) {
      return null;
    }
  }

  function hostMatches(host) {
    for (var i = 0; i < blockedHosts.length; i++) {
      var pattern = blockedHosts[i];
      if (pattern.charAt(0) === '.') {
        var suffix = pattern.slice(1);
        if (host === suffix || host.endsWith(pattern)) {
          return true;
        }
      } else if (host === pattern) {
        return true;
      }
    }
    return false;
  }

  function hasGoogleVideoAdQuery(urlObj) {
    for (var i = 0; i < googleVideoAdQueryKeys.length; i++) {
      if (urlObj.searchParams.has(googleVideoAdQueryKeys[i])) {
        return true;
      }
    }
    return false;
  }

  function shouldBlockUrl(rawUrl) {
    var urlObj = parseUrl(rawUrl);
    if (!urlObj) {
      return false;
    }

    var host = (urlObj.hostname || '').toLowerCase();
    var path = (urlObj.pathname || '').toLowerCase();

    if (hostMatches(host)) {
      return true;
    }

    var isYoutubeHost = host === 'youtube.com' || host.endsWith('.youtube.com');
    if (isYoutubeHost) {
      for (var i = 0; i < youtubeAdPathTokens.length; i++) {
        if (path.indexOf(youtubeAdPathTokens[i]) !== -1) {
          return true;
        }
      }
    }

    var isGoogleVideoHost = host === 'googlevideo.com' || host.endsWith('.googlevideo.com');
    var isVideoPlaybackPath = path.indexOf('/videoplayback') !== -1;
    if (
      blockGoogleVideoPlaybackAdQueries &&
      isGoogleVideoHost &&
      isVideoPlaybackPath &&
      hasGoogleVideoAdQuery(urlObj)
    ) {
      return true;
    }

    return false;
  }

  function installNetworkHooks() {
    if (window.__go_playAdblockNetworkInstalled) {
      return;
    }
    window.__go_playAdblockNetworkInstalled = true;

    if (typeof window.fetch === 'function') {
      window.__go_playOriginalFetch = window.fetch;
      window.fetch = function(input, init) {
        var url = '';
        if (typeof input === 'string') {
          url = input;
        } else if (input && typeof input.url === 'string') {
          url = input.url;
        }
        if (shouldBlockUrl(url)) {
          return Promise.resolve(new Response(null, { status: 204, statusText: 'No Content' }));
        }
        return window.__go_playOriginalFetch.apply(this, arguments);
      };
    }

    if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {
      var proto = window.XMLHttpRequest.prototype;
      window.__go_playOriginalXhrOpen = proto.open;
      window.__go_playOriginalXhrSend = proto.send;

      proto.open = function(method, url) {
        this.__go_playBlockedByAdblock = shouldBlockUrl(url);
        return window.__go_playOriginalXhrOpen.apply(this, arguments);
      };

      proto.send = function(body) {
        if (this.__go_playBlockedByAdblock) {
          try {
            this.abort();
          } catch (_) {}
          return;
        }
        return window.__go_playOriginalXhrSend.apply(this, arguments);
      };
    }

    if (navigator && typeof navigator.sendBeacon === 'function') {
      window.__go_playOriginalSendBeacon = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = function(url, data) {
        if (shouldBlockUrl(url)) {
          return true;
        }
        return window.__go_playOriginalSendBeacon(url, data);
      };
    }
  }

  function ensureStyle() {
    var style = document.getElementById('go_play-adblock-style');
    if (style) {
      return;
    }

    style = document.createElement('style');
    style.id = 'go_play-adblock-style';
    style.textContent = [
      'ytd-display-ad-renderer,',
      'ytd-promoted-video-renderer,',
      'ytd-promoted-sparkles-web-renderer,',
      'ytd-companion-slot-renderer,',
      'ytd-ad-slot-renderer,',
      'ytd-action-companion-ad-renderer,',
      'ytd-player-legacy-desktop-watch-ads-renderer,',
      'ytd-in-feed-ad-layout-renderer,',
      'ytm-promoted-sparkles-web-renderer,',
      'ytm-promoted-sparkles-text-search-renderer,',
      'ytm-companion-ad-renderer,',
      '#player-ads,',
      '.video-ads {',
      '  display: none !important;',
      '  opacity: 0 !important;',
      '  pointer-events: none !important;',
      '  height: 0 !important;',
      '}'
    ].join('\\n');
    document.documentElement.appendChild(style);
  }

  function isAdShowing() {
    var player = document.querySelector('.html5-video-player, #movie_player');
    if (player && player.classList && player.classList.contains('ad-showing')) {
      return true;
    }

    return !!document.querySelector(
      '.ytp-ad-player-overlay, .ytp-ad-text, .ytp-ad-simple-ad-badge, ' +
      '.ytp-ad-preview-text, .ytm-ad-player-overlay'
    );
  }

  function rememberAndMuteVideo(video) {
    if (!video) {
      return;
    }

    if (window.__go_playAdAudioSnapshotTaken !== true) {
      window.__go_playAdAudioSnapshotTaken = true;
      window.__go_playAdPreviousMuted = video.muted === true;
      window.__go_playAdPreviousVolume =
          typeof video.volume === 'number' ? video.volume : 1;
      window.__go_playAdPreviousPlaybackRate =
          typeof video.playbackRate === 'number' ? video.playbackRate : 1;
    }

    if (video.muted !== true) {
      video.muted = true;
    }
  }

  function restoreVideoAudio(video) {
    if (!video || window.__go_playAdAudioSnapshotTaken !== true) {
      return;
    }

    video.muted = window.__go_playAdPreviousMuted === true;
    var previousVolume = window.__go_playAdPreviousVolume;
    if (typeof previousVolume === 'number' && isFinite(previousVolume)) {
      video.volume = Math.max(0, Math.min(previousVolume, 1));
    }
    var previousPlaybackRate = window.__go_playAdPreviousPlaybackRate;
    if (
      typeof previousPlaybackRate === 'number' &&
      isFinite(previousPlaybackRate) &&
      previousPlaybackRate > 0
    ) {
      video.playbackRate = previousPlaybackRate;
    }
    window.__go_playAdAudioSnapshotTaken = false;
    window.__go_playAdPreviousMuted = null;
    window.__go_playAdPreviousVolume = null;
    window.__go_playAdPreviousPlaybackRate = null;
  }

  function resetAdStuckState() {
    window.__go_playAdVisibleSinceMs = 0;
    window.__go_playAdLastVideoTime = null;
    window.__go_playAdLastVideoProgressAtMs = 0;
    window.__go_playAdLastSeekAtMs = 0;
    window.__go_playAdStuckWindowStartMs = 0;
    window.__go_playAdStuckRecoverCount = 0;
    window.__go_playAdLastForceRecoverAtMs = 0;
    window.__go_playAdHardReloadIssued = false;
    try {
      sessionStorage.removeItem(hardReloadBudgetStorageKey);
    } catch (_) {}
  }

  function adNoProgressDurationMs(video) {
    var now = Date.now();
    if (!window.__go_playAdVisibleSinceMs) {
      window.__go_playAdVisibleSinceMs = now;
      window.__go_playAdLastVideoProgressAtMs = now;
      window.__go_playAdLastVideoTime =
          video && isFinite(video.currentTime) ? video.currentTime : null;
      return 0;
    }

    if (video && isFinite(video.currentTime)) {
      var lastVideoTime = window.__go_playAdLastVideoTime;
      if (
        typeof lastVideoTime !== 'number' ||
        !isFinite(lastVideoTime) ||
        Math.abs(video.currentTime - lastVideoTime) > 0.12
      ) {
        window.__go_playAdLastVideoTime = video.currentTime;
        window.__go_playAdLastVideoProgressAtMs = now;
      }
    }

    var lastProgressAt = window.__go_playAdLastVideoProgressAtMs || window.__go_playAdVisibleSinceMs;
    return Math.max(now - lastProgressAt, 0);
  }

  function adVisibleDurationMs() {
    var visibleSince = window.__go_playAdVisibleSinceMs || 0;
    if (!visibleSince) {
      return 0;
    }
    return Math.max(Date.now() - visibleSince, 0);
  }

  function maybeFastForwardAd(video, nowMs) {
    if (!video) {
      return false;
    }

    if (typeof video.readyState === 'number' && video.readyState < adSeekMinReadyState) {
      return false;
    }

    if (!(typeof video.duration === 'number' && isFinite(video.duration) && video.duration > 0.25)) {
      return false;
    }

    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    var lastSeekAt = window.__go_playAdLastSeekAtMs || 0;
    if (now - lastSeekAt < adSeekForwardCooldownMs) {
      return false;
    }

    try {
      video.currentTime = Math.max(video.duration - 0.25, 0);
      window.__go_playAdLastSeekAtMs = now;
      return true;
    } catch (_) {
      return false;
    }
  }

  function registerStuckRecoveryAttempt(nowMs) {
    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    var windowStart = window.__go_playAdStuckWindowStartMs || 0;
    if (!windowStart || now - windowStart > adHardRecoveryThresholdMs) {
      window.__go_playAdStuckWindowStartMs = now;
      window.__go_playAdStuckRecoverCount = 0;
    }
    window.__go_playAdStuckRecoverCount = (window.__go_playAdStuckRecoverCount || 0) + 1;
    return window.__go_playAdStuckRecoverCount;
  }

  function tryPlayerAdBypass(video, nowMs) {
    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    var player = document.querySelector('#movie_player');
    if (player) {
      try {
        if (typeof player.skipAd === 'function') {
          player.skipAd();
          return true;
        }
      } catch (_) {}
      try {
        if (
          typeof player.getDuration === 'function' &&
          typeof player.seekTo === 'function'
        ) {
          var duration = player.getDuration();
          if (typeof duration === 'number' && isFinite(duration) && duration > 0.25) {
            player.seekTo(Math.max(duration - 0.05, 0), true);
            window.__go_playAdLastSeekAtMs = now;
            return true;
          }
        }
      } catch (_) {}
    }
    return maybeFastForwardAd(video, now);
  }

  function hardRecoverFromAdDeadlock(video) {
    clickButtons(adSkipButtonSelectors);
    clickButtons(adOverlayCloseSelectors);
    var bypassed = tryPlayerAdBypass(video);
    clickButtons(adNextSelectors);
    if (bypassed) {
      return;
    }

    if (!enableHardReloadRecovery) {
      return;
    }

    var now = Date.now();
    var lastHardReloadAt = window.__go_playAdLastHardReloadAtMs || 0;
    if (window.__go_playAdHardReloadIssued === true || now - lastHardReloadAt < adHardReloadCooldownMs) {
      return;
    }

    var usedBudget = 0;
    try {
      usedBudget = parseInt(sessionStorage.getItem(hardReloadBudgetStorageKey) || '0', 10) || 0;
    } catch (_) {}
    if (usedBudget >= 1) {
      return;
    }

    try {
      sessionStorage.setItem(hardReloadBudgetStorageKey, String(usedBudget + 1));
    } catch (_) {}

    window.__go_playAdHardReloadIssued = true;
    window.__go_playAdLastHardReloadAtMs = now;
    try {
      window.location.reload();
    } catch (_) {}
  }

  function forceRecoverFromStuckAd(video, noProgressMs) {
    var now = Date.now();
    var lastForceAt = window.__go_playAdLastForceRecoverAtMs || 0;
    if (now - lastForceAt < forceAdRecoveryCooldownMs) {
      return;
    }
    window.__go_playAdLastForceRecoverAtMs = now;
    var recoveryCount = registerStuckRecoveryAttempt(now);

    clickButtons(adSkipButtonSelectors);
    clickButtons(adOverlayCloseSelectors);

    if (!video) {
      if (noProgressMs >= adHardRecoveryThresholdMs || recoveryCount >= adStuckRecoveryMaxAttempts) {
        hardRecoverFromAdDeadlock(null);
      }
      return;
    }

    rememberAndMuteVideo(video);

    var didSeek = tryPlayerAdBypass(video, now);

    if (!didSeek && video.seekable && video.seekable.length > 0) {
      try {
        var seekableEnd = video.seekable.end(video.seekable.length - 1);
        if (typeof seekableEnd === 'number' && isFinite(seekableEnd) && seekableEnd > 0.25) {
          video.currentTime = Math.max(seekableEnd - 0.05, 0);
          window.__go_playAdLastSeekAtMs = now;
          didSeek = true;
        }
      } catch (_) {}
    }

    if (video.paused && typeof video.play === 'function') {
      try {
        var playResult = video.play();
        if (playResult && typeof playResult.catch === 'function') {
          playResult.catch(function() {});
        }
      } catch (_) {}
    }

    if (typeof video.playbackRate === 'number' && isFinite(video.playbackRate) && video.playbackRate < 2) {
      try {
        video.playbackRate = 2;
      } catch (_) {}
    }

    if (noProgressMs >= adHardRecoveryThresholdMs || recoveryCount >= adStuckRecoveryMaxAttempts) {
      hardRecoverFromAdDeadlock(video);
    }
  }

  function clickButtons(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var list = document.querySelectorAll(selectors[i]);
      list.forEach(function(button) {
        if (button && typeof button.click === 'function') {
          button.click();
        }
      });
    }
  }

  function skipVideoAds() {
    try {
      var video = document.querySelector('video');
      if (!isAdShowing()) {
        restoreVideoAudio(video);
        resetAdStuckState();
        return;
      }

      var noProgressMs = adNoProgressDurationMs(video);
      if (video) {
        rememberAndMuteVideo(video);
        tryPlayerAdBypass(video);
      }

      clickButtons(adSkipButtonSelectors);

      clickButtons(adOverlayCloseSelectors);

      // If ad playback is paused/stalled at readyState 0-1, recover immediately
      // instead of waiting for no-progress threshold to expire.
      if (
        video &&
        typeof video.readyState === 'number' &&
        video.readyState <= 1
      ) {
        forceRecoverFromStuckAd(
          video,
          Math.max(noProgressMs, adStuckNoProgressThresholdMs),
        );
        return;
      }

      if (noProgressMs >= adStuckNoProgressThresholdMs) {
        forceRecoverFromStuckAd(video, noProgressMs);
        return;
      }

      // Some ads keep progressing just enough to avoid no-progress detection
      // while still trapping playback. Bound total ad-visible time to recover.
      if (adVisibleDurationMs() >= adMaxVisibleThresholdMs) {
        forceRecoverFromStuckAd(video, noProgressMs);
      }
    } catch (_) {}
  }

  window.__go_playAdblockInstalled = true;
  if (enableNetworkHooks) {
    installNetworkHooks();
  }
  ensureStyle();

  if (window.__go_playAdblockTicker) {
    clearInterval(window.__go_playAdblockTicker);
  }
  window.__go_playAdblockTicker = setInterval(skipVideoAds, 80);

  if (window.__go_playAdblockObserver) {
    window.__go_playAdblockObserver.disconnect();
  }
  window.__go_playAdblockObserver = new MutationObserver(function() {
    if (window.__go_playAdMutationScheduled === true) {
      return;
    }
    window.__go_playAdMutationScheduled = true;
    setTimeout(function() {
      window.__go_playAdMutationScheduled = false;
      skipVideoAds();
    }, 25);
  });
  window.__go_playAdblockObserver.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  skipVideoAds();
})();
''';

const String goPlayDisableAdblockScript = '''
(function() {
  var video = document.querySelector('video');
  if (video && window.__go_playAdAudioSnapshotTaken === true) {
    video.muted = window.__go_playAdPreviousMuted === true;
    var previousVolume = window.__go_playAdPreviousVolume;
    if (typeof previousVolume === 'number' && isFinite(previousVolume)) {
      video.volume = Math.max(0, Math.min(previousVolume, 1));
    }
    var previousPlaybackRate = window.__go_playAdPreviousPlaybackRate;
    if (
      typeof previousPlaybackRate === 'number' &&
      isFinite(previousPlaybackRate) &&
      previousPlaybackRate > 0
    ) {
      video.playbackRate = previousPlaybackRate;
    }
  }
  window.__go_playAdAudioSnapshotTaken = false;
  window.__go_playAdPreviousMuted = null;
  window.__go_playAdPreviousVolume = null;
  window.__go_playAdPreviousPlaybackRate = null;
  window.__go_playAdVisibleSinceMs = 0;
  window.__go_playAdLastVideoTime = null;
  window.__go_playAdLastVideoProgressAtMs = 0;
  window.__go_playAdLastSeekAtMs = 0;
  window.__go_playAdStuckWindowStartMs = 0;
  window.__go_playAdStuckRecoverCount = 0;
  window.__go_playAdLastForceRecoverAtMs = 0;
  window.__go_playAdLastHardReloadAtMs = 0;
  window.__go_playAdHardReloadIssued = false;
  window.__go_playAdMutationScheduled = false;
  try {
    sessionStorage.removeItem('go_play_ad_hard_reload_budget');
  } catch (_) {}

  var style = document.getElementById('go_play-adblock-style');
  if (style && style.parentNode) {
    style.parentNode.removeChild(style);
  }
  if (window.__go_playAdblockTicker) {
    clearInterval(window.__go_playAdblockTicker);
    window.__go_playAdblockTicker = null;
  }
  if (window.__go_playAdblockObserver) {
    window.__go_playAdblockObserver.disconnect();
    window.__go_playAdblockObserver = null;
  }
  if (window.__go_playOriginalFetch) {
    window.fetch = window.__go_playOriginalFetch;
    window.__go_playOriginalFetch = null;
  }
  if (window.XMLHttpRequest && window.XMLHttpRequest.prototype &&
      window.__go_playOriginalXhrOpen && window.__go_playOriginalXhrSend) {
    var proto = window.XMLHttpRequest.prototype;
    proto.open = window.__go_playOriginalXhrOpen;
    proto.send = window.__go_playOriginalXhrSend;
    window.__go_playOriginalXhrOpen = null;
    window.__go_playOriginalXhrSend = null;
  }
  if (window.__go_playOriginalSendBeacon && navigator && typeof navigator.sendBeacon === 'function') {
    navigator.sendBeacon = window.__go_playOriginalSendBeacon;
    window.__go_playOriginalSendBeacon = null;
  }
  window.__go_playAdblockNetworkInstalled = false;
  window.__go_playAdblockInstalled = false;
})();
''';
