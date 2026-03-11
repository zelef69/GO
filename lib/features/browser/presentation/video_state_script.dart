const String goPlayVideoStateScript = '''
(function() {
  if (window.__go_playVideoObserverInstalled) {
    return;
  }
  window.__go_playVideoObserverInstalled = true;

  function isFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  function getVideoState() {
    var video = document.querySelector('video');
    var isPlaying = !!(video && !video.paused && !video.ended && video.readyState > 2);
    var width = 0;
    var height = 0;
    var rectLeft = 0;
    var rectTop = 0;
    var rectRight = 0;
    var rectBottom = 0;
    if (video) {
      var intrinsicWidth = Number(video.videoWidth || 0);
      var intrinsicHeight = Number(video.videoHeight || 0);
      var rect = video.getBoundingClientRect();
      var cssWidth = Math.max(0, Number(rect.width || (rect.right - rect.left) || 0));
      var cssHeight = Math.max(0, Number(rect.height || (rect.bottom - rect.top) || 0));

      if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
        intrinsicWidth = Number(video.clientWidth || cssWidth || 0);
        intrinsicHeight = Number(video.clientHeight || cssHeight || 0);
      }

      width = Math.max(0, Math.round(intrinsicWidth));
      height = Math.max(0, Math.round(intrinsicHeight));

      // Compute the rendered video frame (content box), not only the element box.
      // This keeps PiP sourceRect close to the real video aspect ratio.
      var visibleLeft = Number(rect.left || 0);
      var visibleTop = Number(rect.top || 0);
      var visibleWidth = cssWidth;
      var visibleHeight = cssHeight;

      if (intrinsicWidth > 0 && intrinsicHeight > 0 && cssWidth > 0 && cssHeight > 0) {
        var intrinsicAspect = intrinsicWidth / intrinsicHeight;
        var boxAspect = cssWidth / cssHeight;
        if (Number.isFinite(intrinsicAspect) &&
            Number.isFinite(boxAspect) &&
            intrinsicAspect > 0 &&
            boxAspect > 0) {
          if (boxAspect > intrinsicAspect) {
            visibleHeight = cssHeight;
            visibleWidth = cssHeight * intrinsicAspect;
            visibleLeft = rect.left + ((cssWidth - visibleWidth) / 2);
          } else {
            visibleWidth = cssWidth;
            visibleHeight = cssWidth / intrinsicAspect;
            visibleTop = rect.top + ((cssHeight - visibleHeight) / 2);
          }
        }
      }

      var dpr = Number(window.devicePixelRatio || 1);
      rectLeft = Math.max(0, Math.round(visibleLeft * dpr));
      rectTop = Math.max(0, Math.round(visibleTop * dpr));
      rectRight = Math.max(rectLeft, Math.round((visibleLeft + visibleWidth) * dpr));
      rectBottom = Math.max(rectTop, Math.round((visibleTop + visibleHeight) * dpr));
    }

    var titleNode = document.querySelector(
      'h1 yt-formatted-string, h1.title yt-formatted-string, .slim-video-metadata-title'
    );
    var authorNode = document.querySelector(
      'ytd-channel-name a, ytm-slim-owner-renderer a, #text-container a'
    );
    var title = titleNode && titleNode.textContent ? titleNode.textContent.trim() : document.title;
    var author = authorNode && authorNode.textContent ? authorNode.textContent.trim() : '';

    var durationMs = 0;
    var positionMs = 0;
    if (video) {
      if (Number.isFinite(video.duration) && video.duration > 0) {
        durationMs = Math.round(video.duration * 1000);
      }
      if (Number.isFinite(video.currentTime) && video.currentTime >= 0) {
        positionMs = Math.round(video.currentTime * 1000);
      }
    }

    var listId = '';
    var hasListContext = false;
    var currentVideoId = '';
    try {
      var currentUrl = new URL(window.location.href);
      listId = String(currentUrl.searchParams.get('list') || '').trim();
      hasListContext = listId.length > 0;
      currentVideoId = String(currentUrl.searchParams.get('v') || '').trim();
      if (!currentVideoId && currentUrl.pathname.indexOf('/shorts/') === 0) {
        var segments = currentUrl.pathname.split('/');
        if (segments.length >= 3) {
          currentVideoId = String(segments[2] || '').trim();
        }
      }
    } catch (_) {}

    function hasDisabledState(node) {
      if (!node) {
        return true;
      }
      if (node.disabled === true) {
        return true;
      }
      var ariaDisabled = String(node.getAttribute('aria-disabled') || '').toLowerCase();
      if (ariaDisabled === 'true') {
        return true;
      }
      if (node.getAttribute('disabled') !== null) {
        return true;
      }
      return false;
    }

    var nextSelectors = [
      'button.ytp-next-button',
      '.ytp-next-button',
      'button[aria-keyshortcuts="SHIFT+n"]',
      '#movie_player .ytp-next-button',
      'button[aria-label*="Next"]',
      'button[aria-label*="next"]',
      'button[aria-label*="\\u0e16\\u0e31\\u0e14\\u0e44\\u0e1b"]',
      '[role="button"][aria-label*="Next"]',
      '[role="button"][aria-label*="next"]',
      '[role="button"][aria-label*="\\u0e16\\u0e31\\u0e14\\u0e44\\u0e1b"]',
      'ytm-player-control-button[button-id="next"] button',
      'ytm-player-control-button[button-id="next"]'
    ];

    var nextButton = null;
    for (var i = 0; i < nextSelectors.length; i += 1) {
      var candidate = document.querySelector(nextSelectors[i]);
      if (candidate) {
        nextButton = candidate;
        break;
      }
    }
    var hasNext = false;
    if (nextButton) {
      hasNext = !hasDisabledState(nextButton);
    }

    if (!hasNext && hasListContext) {
      var playlistSelectors = [
        'ytm-compact-video-renderer a[href*="/watch"]',
        'ytm-playlist-panel-video-renderer a[href*="/watch"]',
        'a.compact-media-item-image[href*="/watch"]',
        'a.media-item-thumbnail-container[href*="/watch"]',
        'a[href*="/watch?"][href*="list="]'
      ];
      for (var selectorIndex = 0; selectorIndex < playlistSelectors.length; selectorIndex += 1) {
        var links = document.querySelectorAll(playlistSelectors[selectorIndex]);
        for (var linkIndex = 0; linkIndex < links.length; linkIndex += 1) {
          var link = links[linkIndex];
          if (!link || hasDisabledState(link)) {
            continue;
          }
          var href = String(link.getAttribute('href') || '').trim();
          if (!href) {
            continue;
          }
          if (href.indexOf('/watch') < 0) {
            continue;
          }
          if (listId && href.indexOf('list=' + encodeURIComponent(listId)) < 0 && href.indexOf('list=' + listId) < 0) {
            continue;
          }
          if (currentVideoId) {
            var sameVideoByQuery = href.indexOf('v=' + encodeURIComponent(currentVideoId)) >= 0 || href.indexOf('v=' + currentVideoId) >= 0;
            var sameVideoByPath = href.indexOf('/shorts/' + currentVideoId) >= 0;
            if (sameVideoByQuery || sameVideoByPath) {
              continue;
            }
          }
          hasNext = true;
          break;
        }
        if (hasNext) {
          break;
        }
      }
    }
    if (!hasNext) {
      var playerNode = document.getElementById('movie_player');
      hasNext = !!(playerNode && typeof playerNode.nextVideo === 'function');
    }

    return {
      isPlaying: isPlaying,
      isFullscreen: isFullscreen(),
      videoWidth: width,
      videoHeight: height,
      videoRectLeft: rectLeft,
      videoRectTop: rectTop,
      videoRectRight: rectRight,
      videoRectBottom: rectBottom,
      title: title || '',
      author: author,
      durationMs: durationMs,
      positionMs: positionMs,
      hasNext: hasNext,
      hasListContext: hasListContext,
      listId: listId
    };
  }

  function publishState() {
    try {
      if (!window.flutter_inappwebview ||
          typeof window.flutter_inappwebview.callHandler !== 'function') {
        return;
      }
      window.flutter_inappwebview.callHandler('go_playVideoState', getVideoState());
    } catch (_) {
      return;
    }
  }

  window.__go_playPublishVideoState = publishState;
  window.__go_playReadVideoState = getVideoState;

  document.addEventListener('play', publishState, true);
  document.addEventListener('pause', publishState, true);
  document.addEventListener('fullscreenchange', publishState, true);
  document.addEventListener('webkitfullscreenchange', publishState, true);
  document.addEventListener('visibilitychange', publishState, true);
  window.addEventListener('yt-navigate-finish', publishState, true);

  publishState();
})();
''';

const String goPlayPlaybackDebugScript = '''
(function() {
  if (window.__go_playPlaybackDebugInstalled) {
    return;
  }
  window.__go_playPlaybackDebugInstalled = true;

  function toMs(value) {
    if (typeof value !== 'number' || !isFinite(value) || value < 0) {
      return 0;
    }
    return Math.round(value * 1000);
  }

  function toInt(value) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return 0;
    }
    return Math.round(value);
  }

  function getVideoIdFromUrl() {
    try {
      var url = new URL(window.location.href);
      var fromQuery = url.searchParams.get('v');
      if (fromQuery) {
        return fromQuery;
      }
      var parts = String(url.pathname || '').split('/');
      var shortsIndex = parts.indexOf('shorts');
      if (shortsIndex >= 0 && parts.length > shortsIndex + 1) {
        var shortsId = parts[shortsIndex + 1];
        if (shortsId) {
          return shortsId;
        }
      }
    } catch (_) {}
    return '';
  }

  function bufferedAheadMs(video) {
    if (!video || !video.buffered || video.buffered.length === 0) {
      return 0;
    }
    var current = Number(video.currentTime || 0);
    if (!isFinite(current) || current < 0) {
      current = 0;
    }
    for (var i = 0; i < video.buffered.length; i += 1) {
      var start = Number(video.buffered.start(i) || 0);
      var end = Number(video.buffered.end(i) || 0);
      if (!isFinite(start) || !isFinite(end)) {
        continue;
      }
      if (current >= start && current <= end) {
        return toMs(end - current);
      }
    }
    var fallbackEnd = Number(video.buffered.end(video.buffered.length - 1) || 0);
    if (!isFinite(fallbackEnd) || fallbackEnd <= current) {
      return 0;
    }
    return toMs(fallbackEnd - current);
  }

  function isVisibleElement(element) {
    if (!element) {
      return false;
    }
    var style = window.getComputedStyle(element);
    if (!style || style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || 1) === 0) {
      return false;
    }
    var rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function readState(eventName) {
    var video = document.querySelector('video');
    var player = document.getElementById('movie_player');
    var spinner = document.querySelector('.ytp-spinner');
    var adOverlay = document.querySelector('.ytp-ad-module, .ytp-ad-player-overlay');
    var rect = video ? video.getBoundingClientRect() : null;

    return {
      tsEpochMs: Date.now(),
      event: eventName || 'snapshot',
      url: window.location.href || '',
      videoId: getVideoIdFromUrl(),
      hasVideo: !!video,
      adShowing: !!(player && player.classList && player.classList.contains('ad-showing')),
      adInterrupting: !!(player && player.classList && player.classList.contains('ad-interrupting')),
      hasAdOverlay: !!adOverlay,
      spinnerVisible: isVisibleElement(spinner),
      paused: !!(video && video.paused),
      ended: !!(video && video.ended),
      readyState: toInt(video ? video.readyState : 0),
      networkState: toInt(video ? video.networkState : 0),
      currentTimeMs: toMs(video ? video.currentTime : 0),
      durationMs: toMs(video ? video.duration : 0),
      bufferedAheadMs: bufferedAheadMs(video),
      videoWidth: toInt(video ? video.videoWidth : 0),
      videoHeight: toInt(video ? video.videoHeight : 0),
      cssWidth: toInt(rect ? rect.width : 0),
      cssHeight: toInt(rect ? rect.height : 0),
      videoVisible: !!(rect && rect.width > 0 && rect.height > 0),
      pageVisibility: document.visibilityState || 'unknown'
    };
  }

  function publish(eventName) {
    try {
      if (!window.flutter_inappwebview ||
          typeof window.flutter_inappwebview.callHandler !== 'function') {
        return;
      }
      window.flutter_inappwebview.callHandler('go_playPlaybackDebug', readState(eventName));
    } catch (_) {}
  }

  function readUrlContext() {
    var listId = '';
    var videoId = '';
    var hasListContext = false;
    try {
      var url = new URL(window.location.href);
      listId = String(url.searchParams.get('list') || '').trim();
      hasListContext = listId.length > 0;
      videoId = String(url.searchParams.get('v') || '').trim();
      if (!videoId && url.pathname.indexOf('/shorts/') === 0) {
        var segments = url.pathname.split('/');
        if (segments.length >= 3) {
          videoId = String(segments[2] || '').trim();
        }
      }
    } catch (_) {}
    return {
      videoId: videoId,
      listId: listId,
      hasListContext: hasListContext
    };
  }

  function hasDisabledState(node) {
    if (!node) {
      return true;
    }
    if (node.disabled === true) {
      return true;
    }
    if (node.getAttribute && node.getAttribute('disabled') !== null) {
      return true;
    }
    var ariaDisabled = '';
    try {
      ariaDisabled = String(node.getAttribute('aria-disabled') || '').toLowerCase();
    } catch (_) {
      ariaDisabled = '';
    }
    return ariaDisabled === 'true';
  }

  function clickNode(node) {
    if (!node || hasDisabledState(node)) {
      return false;
    }
    try {
      node.click();
      return true;
    } catch (_) {}
    try {
      var eventObj = new MouseEvent('click', {
        view: window,
        bubbles: true,
        cancelable: true
      });
      node.dispatchEvent(eventObj);
      return true;
    } catch (_) {}
    return false;
  }

  function backgroundAutoNextEnabled() {
    try {
      if (window.__go_playBackgroundPlaybackState &&
          window.__go_playBackgroundPlaybackState.active === true) {
        return true;
      }
    } catch (_) {}
    var visibility = String(document.visibilityState || '').toLowerCase();
    return visibility === 'hidden';
  }

  function tryNextInCurrentContext(context) {
    var nextButtonSelectors = [
      'button.ytp-next-button',
      '.ytp-next-button',
      'button[aria-keyshortcuts="SHIFT+n"]',
      '#movie_player .ytp-next-button',
      'button[aria-label*="Next"]',
      'button[aria-label*="next"]',
      'button[aria-label*="\\u0e16\\u0e31\\u0e14\\u0e44\\u0e1b"]',
      '[role="button"][aria-label*="Next"]',
      '[role="button"][aria-label*="next"]',
      '[role="button"][aria-label*="\\u0e16\\u0e31\\u0e14\\u0e44\\u0e1b"]',
      'ytm-player-control-button[button-id="next"] button',
      'ytm-player-control-button[button-id="next"]'
    ];
    for (var selectorIndex = 0; selectorIndex < nextButtonSelectors.length; selectorIndex += 1) {
      var selector = nextButtonSelectors[selectorIndex];
      var button = document.querySelector(selector);
      if (!button) {
        continue;
      }
      if (clickNode(button)) {
        return {
          ok: true,
          strategy: 'button:' + selector
        };
      }
    }

    if (context.hasListContext) {
      var playlistSelectors = [
        'ytm-compact-video-renderer a[href*="/watch"]',
        'ytm-playlist-panel-video-renderer a[href*="/watch"]',
        'a.compact-media-item-image[href*="/watch"]',
        'a.media-item-thumbnail-container[href*="/watch"]',
        'a[href*="/watch?"][href*="list="]'
      ];
      for (var listSelectorIndex = 0; listSelectorIndex < playlistSelectors.length; listSelectorIndex += 1) {
        var listSelector = playlistSelectors[listSelectorIndex];
        var links = document.querySelectorAll(listSelector);
        for (var linkIndex = 0; linkIndex < links.length; linkIndex += 1) {
          var link = links[linkIndex];
          if (!link || hasDisabledState(link)) {
            continue;
          }
          var href = String(link.getAttribute('href') || '').trim();
          if (!href || href.indexOf('/watch') < 0) {
            continue;
          }
          if (context.listId) {
            var encodedListId = encodeURIComponent(context.listId);
            if (href.indexOf('list=' + context.listId) < 0 &&
                href.indexOf('list=' + encodedListId) < 0) {
              continue;
            }
          }
          if (context.videoId) {
            var encodedVideoId = encodeURIComponent(context.videoId);
            var sameVideoByQuery =
                href.indexOf('v=' + context.videoId) >= 0 ||
                href.indexOf('v=' + encodedVideoId) >= 0;
            var sameVideoByPath =
                href.indexOf('/shorts/' + context.videoId) >= 0;
            if (sameVideoByQuery || sameVideoByPath) {
              continue;
            }
          }
          if (clickNode(link)) {
            return {
              ok: true,
              strategy: 'playlist:' + listSelector
            };
          }
        }
      }
    }

    var player = document.getElementById('movie_player');
    if (player && typeof player.nextVideo === 'function') {
      try {
        player.nextVideo();
        return {
          ok: true,
          strategy: 'player.nextVideo'
        };
      } catch (_) {}
    }

    if (typeof window.nextVideo === 'function') {
      try {
        window.nextVideo();
        return {
          ok: true,
          strategy: 'window.nextVideo'
        };
      } catch (_) {}
    }

    return {
      ok: false,
      strategy: 'none'
    };
  }

  if (!window.__go_playBgAutoNextState) {
    window.__go_playBgAutoNextState = {
      token: 0,
      lastVideoId: '',
      lastTriggeredAt: 0
    };
  }

  function scheduleBackgroundAutoNext() {
    publish('auto-next:bg-ended-received');
    if (!backgroundAutoNextEnabled()) {
      publish('auto-next:bg-guard-inactive');
      return;
    }
    publish('auto-next:bg-guard-active');
    var state = window.__go_playBgAutoNextState;
    if (!state) {
      return;
    }
    var snapshot = readState('auto-next:bg-check');
    if (snapshot.adShowing === true || snapshot.adInterrupting === true) {
      return;
    }
    var context = readUrlContext();
    if (!context.videoId) {
      publish('auto-next:bg-missing-video-id');
      return;
    }
    if (state.lastVideoId === context.videoId &&
        (Date.now() - Number(state.lastTriggeredAt || 0)) < 5000) {
      publish('auto-next:bg-skip-duplicate');
      return;
    }

    var token = Number(state.token || 0) + 1;
    state.token = token;
    publish('auto-next:bg-armed');

    var runAttempt = function(label) {
      if (Number(state.token || 0) !== token) {
        return false;
      }
      var triggerResult = tryNextInCurrentContext(context);
      if (triggerResult.ok === true) {
        state.lastVideoId = context.videoId;
        state.lastTriggeredAt = Date.now();
        publish('auto-next:bg-triggered:' + String(triggerResult.strategy || label));
        return true;
      }
      return false;
    };

    // Try immediate first because timers can be throttled while the screen is locked.
    if (runAttempt('primary_immediate')) {
      return;
    }

    setTimeout(function() {
      if (runAttempt('primary_delay')) {
        return;
      }
      setTimeout(function() {
        if (runAttempt('retry')) {
          return;
        }
        publish('auto-next:bg-failed');
      }, 650);
    }, 180);
  }

  function cancelBackgroundAutoNext() {
    var state = window.__go_playBgAutoNextState;
    if (!state) {
      return;
    }
    state.token = Number(state.token || 0) + 1;
  }

  var mediaEvents = [
    'loadstart',
    'loadedmetadata',
    'loadeddata',
    'canplay',
    'canplaythrough',
    'waiting',
    'stalled',
    'suspend',
    'playing',
    'pause',
    'seeking',
    'seeked',
    'ended',
    'error',
    'emptied'
  ];

  function hookVideoEvents() {
    var video = document.querySelector('video');
    if (!video || video.__go_playPlaybackDebugHooked) {
      return;
    }
    video.__go_playPlaybackDebugHooked = true;
    mediaEvents.forEach(function(eventName) {
      video.addEventListener(eventName, function() {
        publish('video:' + eventName);
        if (eventName === 'ended') {
          scheduleBackgroundAutoNext();
        }
      }, true);
    });
    publish('video:hooked');
  }

  var mutationScheduled = false;
  function scheduleMutationPublish() {
    if (mutationScheduled) {
      return;
    }
    mutationScheduled = true;
    setTimeout(function() {
      mutationScheduled = false;
      hookVideoEvents();
      publish('dom:mutation');
    }, 250);
  }

  hookVideoEvents();

  var root = document.documentElement || document.body;
  if (root) {
    var observer = new MutationObserver(function() {
      scheduleMutationPublish();
    });
    observer.observe(root, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class']
    });
  }

  document.addEventListener('visibilitychange', function() {
    publish('doc:visibilitychange');
  }, true);
  window.addEventListener('yt-navigate-start', function() {
    cancelBackgroundAutoNext();
    publish('yt:navigate-start');
  }, true);
  window.addEventListener('yt-navigate-finish', function() {
    hookVideoEvents();
    publish('yt:navigate-finish');
  }, true);

  function resolvePlayPauseControl(target) {
    if (!target || typeof target.closest !== 'function') {
      return null;
    }

    var selectors = [
      'button.ytp-play-button',
      '.ytp-play-button',
      '[data-tooltip-target-id="ytp-play-button"]',
      'button[aria-keyshortcuts="k"]',
      '[role="button"][aria-keyshortcuts="k"]',
      'button.player-control-play-pause-icon',
      '.player-control-play-pause-icon',
      '.ytp-large-play-button'
    ];

    for (var i = 0; i < selectors.length; i += 1) {
      var match = target.closest(selectors[i]);
      if (match) {
        return match;
      }
    }

    var candidate = target.closest('button, [role="button"]');
    if (!candidate) {
      return null;
    }

    var className = String(candidate.className || '').toLowerCase();
    if (className.indexOf('ytp-play-button') >= 0 ||
        className.indexOf('play-pause') >= 0 ||
        className.indexOf('player-control-play-pause') >= 0) {
      return candidate;
    }

    var tooltipTarget = String(candidate.getAttribute('data-tooltip-target-id') || '').toLowerCase();
    if (tooltipTarget === 'ytp-play-button') {
      return candidate;
    }

    var keyShortcuts = String(candidate.getAttribute('aria-keyshortcuts') || '').toLowerCase();
    if (keyShortcuts === 'k') {
      return candidate;
    }

    return null;
  }

  document.addEventListener('click', function(event) {
    var target = event && event.target;
    var playButton = resolvePlayPauseControl(target);
    if (!playButton) {
      return;
    }
    publish('ui:ytp-play-button:click');
  }, true);

  setInterval(function() {
    hookVideoEvents();
    publish('tick');
  }, 1500);

  publish('installed');
})();
''';
