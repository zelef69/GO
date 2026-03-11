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

    var blockVisibilityEvent = function(event) {
      if (window.__go_playPiPActive) {
        event.stopImmediatePropagation();
      }
    };
    document.addEventListener('visibilitychange', blockVisibilityEvent, true);
    document.addEventListener('webkitvisibilitychange', blockVisibilityEvent, true);
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

  window.__go_playPiPActive = false;
  window.__go_playPausePermitCount = 0;
  window.__go_playPauseInFlight = false;
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
  try {
    window.dispatchEvent(new Event('resize'));
  } catch (_) {}
  return {
    pipActiveBefore: pipActiveBefore,
    hadActiveClass: hadActiveClass,
    hadStyle: hadStyle,
    removedPathCount: removedPathCount,
    removedVideoCount: removedVideoCount
  };
})();
''';

const String goPlayTogglePlayPauseScript = '''
(function() {
  function resolveVideo() {
    return document.querySelector('#movie_player video, .html5-main-video, video');
  }

  var video = resolveVideo();
  if (!video) {
    var player = document.getElementById('movie_player');
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

const String goPlayNextVideoScript = '''
(function() {
  var player = document.getElementById('movie_player');
  if (player && typeof player.nextVideo === 'function') {
    try {
      player.nextVideo();
      return true;
    } catch (_) {}
  }

  var selectors = [
    'button.ytp-next-button',
    '.ytp-next-button',
    'button[aria-keyshortcuts="SHIFT+n"]',
    '#movie_player .ytp-next-button'
  ];
  for (var i = 0; i < selectors.length; i++) {
    var button = document.querySelector(selectors[i]);
    if (!button) {
      continue;
    }
    var isDisabled = button.disabled === true ||
      button.getAttribute('disabled') !== null ||
      button.getAttribute('aria-disabled') === 'true';
    if (!isDisabled) {
      button.click();
      return true;
    }
  }

  if (typeof window.nextVideo === 'function') {
    try {
      window.nextVideo();
      return true;
    } catch (_) {}
  }
  return false;
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
