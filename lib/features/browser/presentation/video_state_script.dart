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

    var nextButton = document.querySelector(
      'button.ytp-next-button, .ytp-next-button, button[aria-keyshortcuts="SHIFT+n"], #movie_player .ytp-next-button'
    );
    var hasNext = false;
    if (nextButton) {
      var disabled = nextButton.disabled === true ||
        nextButton.getAttribute('disabled') !== null ||
        nextButton.getAttribute('aria-disabled') === 'true';
      hasNext = !disabled;
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
      hasNext: hasNext
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
    publish('yt:navigate-start');
  }, true);
  window.addEventListener('yt-navigate-finish', function() {
    hookVideoEvents();
    publish('yt:navigate-finish');
  }, true);

  setInterval(function() {
    hookVideoEvents();
    publish('tick');
  }, 1500);

  publish('installed');
})();
''';
