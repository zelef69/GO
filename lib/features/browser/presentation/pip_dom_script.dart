const String goPlayPreparePiPVideoOnlyScript = '''
(function() {
  var video = document.querySelector('#movie_player video, .html5-main-video, video');
  if (!video) {
    return false;
  }

  if (!window.__go_playPiPHooksInstalled) {
    window.__go_playPiPHooksInstalled = true;
    window.__go_playPiPActive = false;
    window.__go_playPausePermitCount = 0;
    window.__go_playPauseInFlight = false;
    window.__go_playVisibilityBlockerAttached = false;
    window.__go_playVisibilityBlocker = null;
    window.__go_playPendingRestoreResyncHandler = null;

    try {
      var mediaProto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
      if (mediaProto && typeof mediaProto.pause === 'function') {
        var originalPause = mediaProto.pause;
        window.__go_playOriginalMediaPause = originalPause;
        mediaProto.pause = function() {
          if (window.__go_playPiPActive) {
            var permits = Number(window.__go_playPausePermitCount || 0);
            if (permits <= 0) {
              return;
            }
            window.__go_playPausePermitCount = permits - 1;
            window.__go_playPauseInFlight = true;
          }
          return originalPause.apply(this, arguments);
        };
      }
    } catch (_) {}

    window.__go_playInstallVisibilityBlocker = function() {
      if (window.__go_playVisibilityBlockerAttached === true) {
        return false;
      }
      var blockVisibilityEvent = function(event) {
        if (window.__go_playPiPActive !== true) {
          return;
        }
        var state = String(document.visibilityState || '').toLowerCase();
        if (state !== 'hidden') {
          return;
        }
        event.stopImmediatePropagation();
      };
      window.__go_playVisibilityBlocker = blockVisibilityEvent;
      document.addEventListener('visibilitychange', blockVisibilityEvent, true);
      document.addEventListener('webkitvisibilitychange', blockVisibilityEvent, true);
      window.__go_playVisibilityBlockerAttached = true;
      return true;
    };

    window.__go_playUninstallVisibilityBlocker = function() {
      if (window.__go_playVisibilityBlockerAttached !== true) {
        return false;
      }
      var blocker = window.__go_playVisibilityBlocker;
      if (!blocker) {
        window.__go_playVisibilityBlockerAttached = false;
        return false;
      }
      document.removeEventListener('visibilitychange', blocker, true);
      document.removeEventListener('webkitvisibilitychange', blocker, true);
      window.__go_playVisibilityBlocker = null;
      window.__go_playVisibilityBlockerAttached = false;
      return true;
    };

    if (!window.__go_playPauseFallbackInstalled) {
      window.__go_playPauseFallbackInstalled = true;
      var resolvePlayPauseControl = function(target) {
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
        for (var i = 0; i < selectors.length; i++) {
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
      };

      document.addEventListener('click', function(event) {
        var target = event && event.target;
        var button = resolvePlayPauseControl(target);
        if (!button) {
          return;
        }
        var activeVideo = document.querySelector('#movie_player video, .html5-main-video, video');
        if (!activeVideo || activeVideo.paused || activeVideo.ended) {
          return;
        }
        var player = document.getElementById('movie_player');
        if (!player || typeof player.pauseVideo !== 'function') {
          return;
        }

        var pauseObserved = false;
        var cleaned = false;
        var cleanup = function() {
          if (cleaned) {
            return;
          }
          cleaned = true;
          try {
            activeVideo.removeEventListener('pause', onPause, true);
          } catch (_) {}
        };
        var onPause = function() {
          pauseObserved = true;
          cleanup();
        };

        try {
          activeVideo.addEventListener('pause', onPause, true);
        } catch (_) {
          return;
        }

        setTimeout(function() {
          try {
            if (!pauseObserved && !activeVideo.paused && !activeVideo.ended) {
              player.pauseVideo();
            }
          } catch (_) {}
          cleanup();
        }, 220);
      }, true);
    }
  }

  if (typeof window.__go_playInstallVisibilityBlocker === 'function') {
    window.__go_playInstallVisibilityBlocker();
  }

  window.__go_playPiPActive = true;
  window.__go_playPausePermitCount = 0;
  window.__go_playPauseInFlight = false;
  document.documentElement.classList.add('go_play-pip-active');

  if (window.__go_playPipLayoutPrepared === true) {
    return true;
  }

  var style = document.getElementById('go_play-pip-layout-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'go_play-pip-layout-style';
    style.textContent = [
      'html.go_play-pip-active, html.go_play-pip-active body {',
      '  margin: 0 !important;',
      '  padding: 0 !important;',
      '  background: #000 !important;',
      '  overflow: hidden !important;',
      '}',
      'html.go_play-pip-active body * {',
      '  visibility: hidden !important;',
      '}',
      'html.go_play-pip-active .go_play-pip-path {',
      '  visibility: visible !important;',
      '  position: fixed !important;',
      '  left: 0 !important;',
      '  top: 0 !important;',
      '  width: 100vw !important;',
      '  height: 100vh !important;',
      '  max-width: 100vw !important;',
      '  max-height: 100vh !important;',
      '  z-index: 2147483647 !important;',
      '  background: #000 !important;',
      '  overflow: hidden !important;',
      '}',
      'html.go_play-pip-active .go_play-pip-video {',
      '  visibility: visible !important;',
      '  position: fixed !important;',
      '  left: 0 !important;',
      '  top: 0 !important;',
      '  width: 100vw !important;',
      '  height: 100vh !important;',
      '  object-fit: contain !important;',
      '  background: #000 !important;',
      '  z-index: 2147483647 !important;',
      '}'
    ].join('\\n');
    document.documentElement.appendChild(style);
  }

  var node = video;
  while (node) {
    if (node.classList) {
      node.classList.add('go_play-pip-path');
    }
    if (node === document.documentElement) {
      break;
    }
    node = node.parentElement;
  }
  video.classList.add('go_play-pip-video');
  if (!video.__go_playPipPauseListenerInstalled) {
    video.__go_playPipPauseListenerInstalled = true;
    video.addEventListener('pause', function() {
      if (!window.__go_playPiPActive) {
        return;
      }
      if (window.__go_playPauseInFlight) {
        window.__go_playPauseInFlight = false;
        return;
      }
      var replay = video.play();
      if (replay && typeof replay.catch === 'function') {
        replay.catch(function() {});
      }
    }, true);
  }
  window.__go_playPipLayoutPrepared = true;

  window.scrollTo(0, 0);
  return true;
})();
''';

const String goPlayRestorePiPVideoOnlyScript = '''
(function() {
  var pipActiveBefore = window.__go_playPiPActive === true;
  var hadActiveClass = document.documentElement.classList.contains('go_play-pip-active');
  var style = document.getElementById('go_play-pip-layout-style');
  var hadStyle = !!style;
  var detachedVisibilityBlocker = false;

  window.__go_playPiPActive = false;
  window.__go_playPausePermitCount = 0;
  window.__go_playPauseInFlight = false;
  if (typeof window.__go_playUninstallVisibilityBlocker === 'function') {
    detachedVisibilityBlocker = window.__go_playUninstallVisibilityBlocker() === true;
  }
  document.documentElement.classList.remove('go_play-pip-active');
  var prepared = window.__go_playPipLayoutPrepared === true;
  var removedPathCount = 0;
  var removedVideoCount = 0;
  if (prepared) {
    var pathNodes = document.querySelectorAll('.go_play-pip-path');
    for (var i = 0; i < pathNodes.length; i++) {
      pathNodes[i].classList.remove('go_play-pip-path');
      removedPathCount += 1;
    }
    var videoNodes = document.querySelectorAll('.go_play-pip-video');
    for (var j = 0; j < videoNodes.length; j++) {
      videoNodes[j].classList.remove('go_play-pip-video');
      removedVideoCount += 1;
    }
    window.__go_playPipLayoutPrepared = false;
  }
  if (style && style.parentNode) {
    style.parentNode.removeChild(style);
  }

  var oldPendingHandler = window.__go_playPendingRestoreResyncHandler;
  if (oldPendingHandler) {
    try {
      document.removeEventListener('visibilitychange', oldPendingHandler, true);
    } catch (_) {}
    try {
      window.removeEventListener('pageshow', oldPendingHandler, true);
    } catch (_) {}
    try {
      window.removeEventListener('focus', oldPendingHandler, true);
    } catch (_) {}
    window.__go_playPendingRestoreResyncHandler = null;
  }

  var resyncEvents = [];
  var resyncDeferred = false;
  var resyncTrigger = '';
  var pageVisibilityBefore = String(document.visibilityState || '').toLowerCase();
  var syncAction = '';
  var syncedVideoState = false;
  var compactBeforeResync = false;
  var compactAfterResync = false;
  var expandedCompactPlayer = false;
  var compactExpandSelector = '';

  function dispatchResync(target, eventName, usePageTransition) {
    if (!target) {
      return false;
    }
    try {
      var eventObj;
      if (usePageTransition === true && typeof window.PageTransitionEvent === 'function') {
        eventObj = new PageTransitionEvent(eventName, { persisted: false });
      } else {
        eventObj = new Event(eventName);
      }
      target.dispatchEvent(eventObj);
      resyncEvents.push(eventName);
      return true;
    } catch (_) {
      return false;
    }
  }

  function syncPlayerState() {
    try {
      var video = document.querySelector('#movie_player video, .html5-main-video, video');
      var player = document.getElementById('movie_player');
      if (!video || !player) {
        return;
      }
      var playerState = -1;
      if (typeof player.getPlayerState === 'function') {
        playerState = Number(player.getPlayerState());
      }
      var videoPaused = !!(video.paused || video.ended);
      if (videoPaused) {
        if (playerState === 1 && typeof player.pauseVideo === 'function') {
          player.pauseVideo();
          syncAction = 'pauseVideo';
        }
        return;
      }
      if (playerState === 2 && typeof player.playVideo === 'function') {
        player.playVideo();
        syncAction = 'playVideo_mismatch';
      }
    } catch (_) {}
  }

  function publishVideoStateSnapshot() {
    try {
      if (typeof window.__go_playPublishVideoState === 'function') {
        window.__go_playPublishVideoState();
        syncedVideoState = true;
      }
    } catch (_) {}
  }

  function readVideoLayoutState() {
    var viewportWidth = Math.max(
      Number(window.innerWidth || 0),
      Number(document.documentElement && document.documentElement.clientWidth || 0)
    );
    var viewportHeight = Math.max(
      Number(window.innerHeight || 0),
      Number(document.documentElement && document.documentElement.clientHeight || 0)
    );
    var video = document.querySelector('#movie_player video, .html5-main-video, video');
    var rect = video ? video.getBoundingClientRect() : null;
    var cssWidth = rect ? Math.max(0, Number(rect.width || (rect.right - rect.left) || 0)) : 0;
    var cssHeight = rect ? Math.max(0, Number(rect.height || (rect.bottom - rect.top) || 0)) : 0;
    var miniPlayerNode = document.querySelector(
      'ytd-miniplayer[active], ytm-miniplayer, #movie_player.ytp-player-minimized, .ytp-player-minimized'
    );
    return {
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      videoCssWidth: cssWidth,
      videoCssHeight: cssHeight,
      hasVideo: !!video,
      hasMiniPlayer: !!miniPlayerNode
    };
  }

  function isCompactLayout(layoutState) {
    if (!layoutState) {
      return false;
    }
    var viewportWidth = Number(layoutState.viewportWidth || 0);
    var videoCssWidth = Number(layoutState.videoCssWidth || 0);
    if (!(viewportWidth > 0 && videoCssWidth > 0)) {
      return false;
    }
    return (videoCssWidth / viewportWidth) < 0.7;
  }

  function triggerClick(node) {
    if (!node) {
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

  function tryExpandCompactPlayer() {
    var selectors = [
      'button.ytp-miniplayer-expand-watch-page-button',
      '.ytp-miniplayer-expand-watch-page-button',
      'button.ytp-player-minimized-button',
      '.ytp-player-minimized-button',
      'ytd-miniplayer button[aria-label*="Expand"]',
      'ytd-miniplayer button[aria-label*="expand"]',
      'ytd-miniplayer button[aria-label*="ขยาย"]',
      'ytd-miniplayer button[title*="Expand"]',
      'ytd-miniplayer button[title*="expand"]',
      'ytd-miniplayer button[title*="ขยาย"]'
    ];
    for (var index = 0; index < selectors.length; index += 1) {
      var selector = selectors[index];
      var node = document.querySelector(selector);
      if (!node) {
        continue;
      }
      if (triggerClick(node)) {
        return {
          clicked: true,
          selector: selector
        };
      }
    }
    return {
      clicked: false,
      selector: ''
    };
  }

  function runResyncSequence(trigger) {
    resyncTrigger = trigger || '';
    var beforeLayout = readVideoLayoutState();
    compactBeforeResync = isCompactLayout(beforeLayout);
    try {
      window.scrollTo(0, 0);
    } catch (_) {}
    dispatchResync(document, 'visibilitychange', false);
    dispatchResync(document, 'webkitvisibilitychange', false);
    dispatchResync(window, 'pageshow', true);
    dispatchResync(window, 'focus', false);
    syncPlayerState();
    publishVideoStateSnapshot();
    try {
      window.dispatchEvent(new Event('resize'));
    } catch (_) {}
    if (compactBeforeResync || beforeLayout.hasMiniPlayer === true) {
      var expandResult = tryExpandCompactPlayer();
      expandedCompactPlayer = expandResult.clicked === true;
      compactExpandSelector = String(expandResult.selector || '');
      if (expandedCompactPlayer) {
        dispatchResync(window, 'focus', false);
        try {
          window.dispatchEvent(new Event('resize'));
        } catch (_) {}
        syncPlayerState();
        publishVideoStateSnapshot();
      }
    }
    var afterLayout = readVideoLayoutState();
    compactAfterResync = isCompactLayout(afterLayout);
  }

  if (pageVisibilityBefore === 'visible') {
    runResyncSequence('immediate_visible');
  } else {
    resyncDeferred = true;
    var pendingHandler = function() {
      var state = String(document.visibilityState || '').toLowerCase();
      if (state !== 'visible') {
        return;
      }
      try {
        document.removeEventListener('visibilitychange', pendingHandler, true);
      } catch (_) {}
      try {
        window.removeEventListener('pageshow', pendingHandler, true);
      } catch (_) {}
      try {
        window.removeEventListener('focus', pendingHandler, true);
      } catch (_) {}
      window.__go_playPendingRestoreResyncHandler = null;
      runResyncSequence('deferred_visible');
    };
    window.__go_playPendingRestoreResyncHandler = pendingHandler;
    document.addEventListener('visibilitychange', pendingHandler, true);
    window.addEventListener('pageshow', pendingHandler, true);
    window.addEventListener('focus', pendingHandler, true);
  }

  return {
    pipActiveBefore: pipActiveBefore,
    hadActiveClass: hadActiveClass,
    hadStyle: hadStyle,
    removedPathCount: removedPathCount,
    removedVideoCount: removedVideoCount,
    detachedVisibilityBlocker: detachedVisibilityBlocker,
    pageVisibilityBefore: pageVisibilityBefore,
    resyncDeferred: resyncDeferred,
    resyncTrigger: resyncTrigger,
    resyncEvents: resyncEvents,
    syncAction: syncAction,
    syncedVideoState: syncedVideoState,
    compactBeforeResync: compactBeforeResync,
    compactAfterResync: compactAfterResync,
    expandedCompactPlayer: expandedCompactPlayer,
    compactExpandSelector: compactExpandSelector
  };
})();
''';

const String goPlayTogglePlayPauseScript = '''
(function() {
  function resolveVideo() {
    return document.querySelector('#movie_player video, .html5-main-video, video');
  }
  function resolvePlayer() {
    return document.getElementById('movie_player');
  }
  function schedulePauseFallback(video, player) {
    if (!video || !player || typeof player.pauseVideo !== 'function') {
      return;
    }

    var pauseObserved = false;
    var cleaned = false;
    var onPause = function() {
      pauseObserved = true;
      cleanup();
    };
    var cleanup = function() {
      if (cleaned) {
        return;
      }
      cleaned = true;
      try {
        video.removeEventListener('pause', onPause, true);
      } catch (_) {}
    };

    try {
      video.addEventListener('pause', onPause, true);
    } catch (_) {
      return;
    }

    setTimeout(function() {
      try {
        if (!pauseObserved && !video.paused && !video.ended) {
          player.pauseVideo();
        }
      } catch (_) {}
      cleanup();
    }, 220);
  }

  var video = resolveVideo();
  var player = resolvePlayer();
  if (!video) {
    if (!player) {
      return false;
    }
    try {
      var state = typeof player.getPlayerState === 'function'
          ? player.getPlayerState()
          : -1;
      if (state === 1 && typeof player.pauseVideo === 'function') {
        player.pauseVideo();
        return true;
      }
      if (typeof player.playVideo === 'function') {
        player.playVideo();
        return true;
      }
    } catch (_) {}
    return false;
  }
  if (video.paused || video.ended) {
    window.__go_playPausePermitCount = 0;
    window.__go_playPauseInFlight = false;
    var playPromise = video.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch(function() {});
    }
    return true;
  }
  window.__go_playPausePermitCount = Number(window.__go_playPausePermitCount || 0) + 1;
  schedulePauseFallback(video, player);
  video.pause();
  return true;
})();
''';

const String goPlayForcePlayVideoScript = '''
(function() {
  function resolveVideo() {
    return document.querySelector('#movie_player video, .html5-main-video, video');
  }

  function withPlayer(methodName) {
    var player = document.getElementById('movie_player');
    if (!player || typeof player[methodName] !== 'function') {
      return false;
    }
    try {
      player[methodName]();
      return true;
    } catch (_) {
      return false;
    }
  }

  var video = resolveVideo();
  if (!video) {
    return withPlayer('playVideo');
  }
  window.__go_playPausePermitCount = 0;
  window.__go_playPauseInFlight = false;
  var playPromise = video.play();
  if (playPromise && typeof playPromise.catch === 'function') {
    playPromise.catch(function() {});
  }
  return true;
})();
''';

const String goPlayPauseVideoScript = '''
(function() {
  function resolveVideo() {
    return document.querySelector('#movie_player video, .html5-main-video, video');
  }
  function schedulePauseFallback(video, player) {
    if (!video || !player || typeof player.pauseVideo !== 'function') {
      return;
    }

    var pauseObserved = false;
    var cleaned = false;
    var onPause = function() {
      pauseObserved = true;
      cleanup();
    };
    var cleanup = function() {
      if (cleaned) {
        return;
      }
      cleaned = true;
      try {
        video.removeEventListener('pause', onPause, true);
      } catch (_) {}
    };

    try {
      video.addEventListener('pause', onPause, true);
    } catch (_) {
      return;
    }

    setTimeout(function() {
      try {
        if (!pauseObserved && !video.paused && !video.ended) {
          player.pauseVideo();
        }
      } catch (_) {}
      cleanup();
    }, 220);
  }

  function withPlayer(methodName) {
    var player = document.getElementById('movie_player');
    if (!player || typeof player[methodName] !== 'function') {
      return false;
    }
    try {
      player[methodName]();
      return true;
    } catch (_) {
      return false;
    }
  }

  var video = resolveVideo();
  if (!video) {
    return withPlayer('pauseVideo');
  }
  window.__go_playPausePermitCount = Number(window.__go_playPausePermitCount || 0) + 1;
  if (!video.paused && !video.ended) {
    var player = document.getElementById('movie_player');
    schedulePauseFallback(video, player);
    video.pause();
  }
  return true;
})();
''';

const String goPlayReadPiPLayoutStateScript = '''
(function() {
  var html = document.documentElement;
  var hasActiveClass = !!(html && html.classList && html.classList.contains('go_play-pip-active'));
  var hasStyle = !!document.getElementById('go_play-pip-layout-style');
  var pathCount = document.querySelectorAll('.go_play-pip-path').length;
  var videoCount = document.querySelectorAll('.go_play-pip-video').length;
  return {
    pipActive: window.__go_playPiPActive === true,
    hasActiveClass: hasActiveClass,
    hasStyle: hasStyle,
    pathCount: pathCount,
    videoCount: videoCount,
    pageVisibility: document.visibilityState || ''
  };
})();
''';

const String goPlayReadVideoLayoutStateScript = '''
(function() {
  var viewportWidth = Math.max(
    Number(window.innerWidth || 0),
    Number(document.documentElement && document.documentElement.clientWidth || 0)
  );
  var viewportHeight = Math.max(
    Number(window.innerHeight || 0),
    Number(document.documentElement && document.documentElement.clientHeight || 0)
  );
  var video = document.querySelector('#movie_player video, .html5-main-video, video');
  var rect = video ? video.getBoundingClientRect() : null;
  var cssWidth = rect ? Math.max(0, Number(rect.width || (rect.right - rect.left) || 0)) : 0;
  var cssHeight = rect ? Math.max(0, Number(rect.height || (rect.bottom - rect.top) || 0)) : 0;
  var hasMiniPlayer = !!document.querySelector(
    'ytd-miniplayer[active], ytm-miniplayer, #movie_player.ytp-player-minimized, .ytp-player-minimized'
  );
  var compact = false;
  if (viewportWidth > 0 && cssWidth > 0) {
    compact = (cssWidth / viewportWidth) < 0.7;
  }
  return {
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    videoCssWidth: cssWidth,
    videoCssHeight: cssHeight,
    hasVideo: !!video,
    hasMiniPlayer: hasMiniPlayer,
    compact: compact,
    pageVisibility: document.visibilityState || ''
  };
})();
''';

const String goPlayNormalizeAfterPiPExitScript = '''
(function() {
  function readLayoutState() {
    var viewportWidth = Math.max(
      Number(window.innerWidth || 0),
      Number(document.documentElement && document.documentElement.clientWidth || 0)
    );
    var viewportHeight = Math.max(
      Number(window.innerHeight || 0),
      Number(document.documentElement && document.documentElement.clientHeight || 0)
    );
    var video = document.querySelector('#movie_player video, .html5-main-video, video');
    var rect = video ? video.getBoundingClientRect() : null;
    var cssWidth = rect ? Math.max(0, Number(rect.width || (rect.right - rect.left) || 0)) : 0;
    var cssHeight = rect ? Math.max(0, Number(rect.height || (rect.bottom - rect.top) || 0)) : 0;
    var hasMiniPlayer = !!document.querySelector(
      'ytd-miniplayer[active], ytm-miniplayer, #movie_player.ytp-player-minimized, .ytp-player-minimized'
    );
    var compact = false;
    if (viewportWidth > 0 && cssWidth > 0) {
      compact = (cssWidth / viewportWidth) < 0.7;
    }
    return {
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      videoCssWidth: cssWidth,
      videoCssHeight: cssHeight,
      hasVideo: !!video,
      hasMiniPlayer: hasMiniPlayer,
      compact: compact,
      pageVisibility: document.visibilityState || ''
    };
  }

  function dispatchResyncSequence() {
    var events = [];
    function dispatch(target, eventName, usePageTransition) {
      if (!target) {
        return;
      }
      try {
        var eventObj;
        if (usePageTransition === true && typeof window.PageTransitionEvent === 'function') {
          eventObj = new PageTransitionEvent(eventName, { persisted: false });
        } else {
          eventObj = new Event(eventName);
        }
        target.dispatchEvent(eventObj);
        events.push(eventName);
      } catch (_) {}
    }
    try {
      window.scrollTo(0, 0);
      events.push('scrollToTop');
    } catch (_) {}
    dispatch(document, 'visibilitychange', false);
    dispatch(document, 'webkitvisibilitychange', false);
    dispatch(window, 'pageshow', true);
    dispatch(window, 'focus', false);
    try {
      window.dispatchEvent(new Event('resize'));
      events.push('resize');
    } catch (_) {}
    return events;
  }

  function syncPlayerState() {
    try {
      var video = document.querySelector('#movie_player video, .html5-main-video, video');
      var player = document.getElementById('movie_player');
      if (!video || !player) {
        return '';
      }
      var playerState = -1;
      if (typeof player.getPlayerState === 'function') {
        playerState = Number(player.getPlayerState());
      }
      var videoPaused = !!(video.paused || video.ended);
      if (videoPaused) {
        if (playerState === 1 && typeof player.pauseVideo === 'function') {
          player.pauseVideo();
          return 'pauseVideo';
        }
        return '';
      }
      if (playerState === 2 && typeof player.playVideo === 'function') {
        player.playVideo();
        return 'playVideo_mismatch';
      }
    } catch (_) {}
    return '';
  }

  function publishVideoStateSnapshot() {
    try {
      if (typeof window.__go_playPublishVideoState === 'function') {
        window.__go_playPublishVideoState();
        return true;
      }
    } catch (_) {}
    return false;
  }

  function triggerClick(node) {
    if (!node) {
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

  function tryExpandCompactPlayer() {
    var selectors = [
      'button.ytp-miniplayer-expand-watch-page-button',
      '.ytp-miniplayer-expand-watch-page-button',
      'button.ytp-player-minimized-button',
      '.ytp-player-minimized-button',
      'ytd-miniplayer button[aria-label*="Expand"]',
      'ytd-miniplayer button[aria-label*="expand"]',
      'ytd-miniplayer button[aria-label*="ขยาย"]',
      'ytd-miniplayer button[title*="Expand"]',
      'ytd-miniplayer button[title*="expand"]',
      'ytd-miniplayer button[title*="ขยาย"]'
    ];
    for (var index = 0; index < selectors.length; index += 1) {
      var selector = selectors[index];
      var node = document.querySelector(selector);
      if (!node) {
        continue;
      }
      if (triggerClick(node)) {
        return {
          clicked: true,
          selector: selector
        };
      }
    }
    return {
      clicked: false,
      selector: ''
    };
  }

  var before = readLayoutState();
  var resyncEvents = dispatchResyncSequence();
  var syncAction = syncPlayerState();
  var published = publishVideoStateSnapshot();
  var expandResult = {
    clicked: false,
    selector: ''
  };

  if (before.compact === true || before.hasMiniPlayer === true) {
    expandResult = tryExpandCompactPlayer();
    if (expandResult.clicked) {
      var followupEvents = dispatchResyncSequence();
      for (var eventIndex = 0; eventIndex < followupEvents.length; eventIndex += 1) {
        resyncEvents.push(followupEvents[eventIndex]);
      }
      var syncActionAfterExpand = syncPlayerState();
      if (!syncAction && syncActionAfterExpand) {
        syncAction = syncActionAfterExpand;
      }
      published = publishVideoStateSnapshot() || published;
    }
  }

  var after = readLayoutState();

  return {
    beforeCompact: before.compact,
    afterCompact: after.compact,
    beforeCssWidth: before.videoCssWidth,
    afterCssWidth: after.videoCssWidth,
    viewportWidth: after.viewportWidth,
    hasMiniBefore: before.hasMiniPlayer,
    hasMiniAfter: after.hasMiniPlayer,
    expandClicked: expandResult.clicked,
    expandSelector: expandResult.selector,
    resyncEvents: resyncEvents,
    syncAction: syncAction,
    published: published,
    pageVisibility: after.pageVisibility
  };
})();
''';

const String goPlayNextVideoScript = '''
(function() {
  function boolValue(value) {
    if (value === true) {
      return true;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      var normalized = value.toLowerCase().trim();
      return normalized === 'true' || normalized === '1';
    }
    return false;
  }

  function hasDisabledState(node) {
    if (!node) {
      return true;
    }
    if (boolValue(node.disabled)) {
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

  function readUrlContext() {
    var listId = '';
    var currentVideoId = '';
    var hasListContext = false;
    try {
      var url = new URL(window.location.href);
      listId = String(url.searchParams.get('list') || '').trim();
      hasListContext = listId.length > 0;
      currentVideoId = String(url.searchParams.get('v') || '').trim();
      if (!currentVideoId && url.pathname.indexOf('/shorts/') === 0) {
        var segments = url.pathname.split('/');
        if (segments.length >= 3) {
          currentVideoId = String(segments[2] || '').trim();
        }
      }
    } catch (_) {}
    return {
      listId: listId,
      currentVideoId: currentVideoId,
      hasListContext: hasListContext
    };
  }

  function result(ok, strategy, context, nextUrl) {
    return {
      ok: ok === true,
      strategy: String(strategy || ''),
      listId: String((context && context.listId) || ''),
      currentVideoId: String((context && context.currentVideoId) || ''),
      hasListContext: !!(context && context.hasListContext),
      nextUrl: String(nextUrl || '')
    };
  }

  var context = readUrlContext();

  // 1) Prefer explicit next-button click (same behavior as manual tap).
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
      return result(true, 'click:' + selector, context, '');
    }
  }

  // 2) If currently in mix/playlist, click the next link inside same list.
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
        var href = '';
        try {
          href = String(link.getAttribute('href') || '').trim();
        } catch (_) {
          href = '';
        }
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
        if (context.currentVideoId) {
          var encodedVideoId = encodeURIComponent(context.currentVideoId);
          var sameVideoByQuery =
              href.indexOf('v=' + context.currentVideoId) >= 0 ||
              href.indexOf('v=' + encodedVideoId) >= 0;
          var sameVideoByPath =
              href.indexOf('/shorts/' + context.currentVideoId) >= 0;
          if (sameVideoByQuery || sameVideoByPath) {
            continue;
          }
        }
        if (clickNode(link)) {
          return result(true, 'playlist_link:' + listSelector, context, href);
        }
      }
    }
  }

  // 3) Fallback to player API.
  var player = document.getElementById('movie_player');
  if (player && typeof player.nextVideo === 'function') {
    try {
      player.nextVideo();
      return result(true, 'player.nextVideo', context, '');
    } catch (_) {}
  }

  // 4) Last fallback.
  if (typeof window.nextVideo === 'function') {
    try {
      window.nextVideo();
      return result(true, 'window.nextVideo', context, '');
    } catch (_) {}
  }
  return result(false, 'none', context, '');
})();
''';

const String goPlayReadBufferedAheadMsScript = '''
(function() {
  var video = document.querySelector('#movie_player video, .html5-main-video, video');
  if (!video || !video.buffered || video.buffered.length === 0) {
    return 0;
  }
  try {
    var current = Number(video.currentTime || 0);
    var end = Number(video.buffered.end(video.buffered.length - 1) || current);
    var ahead = Math.max(0, end - current);
    return Math.round(ahead * 1000);
  } catch (_) {
    return 0;
  }
})();
''';

const String goPlayPublishVideoStateScript = '''
if (typeof window.__go_playPublishVideoState === "function") {
  window.__go_playPublishVideoState();
}
''';
