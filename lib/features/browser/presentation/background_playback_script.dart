const String goPlayEnableBackgroundPlaybackScript = '''
(function() {
  if (!window.__go_playBackgroundPlaybackState) {
    window.__go_playBackgroundPlaybackState = {
      active: false,
      installed: false,
      blocker: null
    };
  }
  var state = window.__go_playBackgroundPlaybackState;

  if (!state.installed) {
    var blocker = function(event) {
      if (state.active !== true) {
        return;
      }
      var visibility = String(document.visibilityState || '').toLowerCase();
      if (visibility !== 'hidden') {
        return;
      }
      event.stopImmediatePropagation();
    };
    state.blocker = blocker;
    document.addEventListener('visibilitychange', blocker, true);
    document.addEventListener('webkitvisibilitychange', blocker, true);
    state.installed = true;
  }

  state.active = true;
  return {
    active: state.active,
    installed: state.installed,
    pageVisibility: document.visibilityState || ''
  };
})();
''';

const String goPlayDisableBackgroundPlaybackScript = '''
(function() {
  var state = window.__go_playBackgroundPlaybackState;
  if (!state) {
    return {
      active: false,
      installed: false,
      pageVisibility: document.visibilityState || ''
    };
  }

  state.active = false;
  try {
    document.dispatchEvent(new Event('visibilitychange'));
  } catch (_) {}
  try {
    document.dispatchEvent(new Event('webkitvisibilitychange'));
  } catch (_) {}
  try {
    window.dispatchEvent(new Event('pageshow'));
  } catch (_) {}
  try {
    window.dispatchEvent(new Event('focus'));
  } catch (_) {}
  try {
    window.dispatchEvent(new Event('resize'));
  } catch (_) {}

  return {
    active: state.active,
    installed: state.installed === true,
    pageVisibility: document.visibilityState || ''
  };
})();
''';
