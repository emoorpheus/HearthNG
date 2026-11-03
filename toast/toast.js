/* HearthNG notifications (com.hearthng.toast). The helper (watch.sh, guard.sh) launches this app instead of a system
 * notification:
 *   luna-send -n 1 luna://com.webos.applicationManager/launch \
 *     '{"id":"com.hearthng.toast","params":{"text":"Home screen is loading…","ms":2000}}'
 * The window floats over whatever is on screen and does not take the remote: _WEBOS_WINDOW_TYPE_FLOATING, needFocus
 * false, an empty input region (the technique of eArcNG and of Nikolay1243's eARC Volume Overlay, checked there on an
 * OLED65M59LA). It closes itself `ms` after it appears (500-10000, default 2000). The window comes up some time after
 * this script starts (OLED65M59LA, webOS 10.3.0: the surface manager showed it 1.32-1.34 s after the launch request,
 * the script runs 0.23 s after it), so on a cold launch the time counts from the script start plus `appearMs`
 * (0-5000, default 1100). A launch while it is on screen (relaunch) puts the new text up and starts `ms` again;
 * {"close":true} closes it at once. No CSS transform in toast.css: with one the window came up only ~8 s after the
 * launch. Written for old Chrome (ES5). */
(function () {
  'use strict';
  var CFG = { ms: 2000, minMs: 500, maxMs: 10000, fade: 150, longText: 70, appear: 1100, maxAppear: 5000 };
  var box = document.getElementById('toast');
  var timers = {};
  var shown = false;

  function later(name, fn, ms) { window.clearTimeout(timers[name]); timers[name] = window.setTimeout(fn, ms); }
  function cancel(name) { window.clearTimeout(timers[name]); }
  function num(v, lo, hi, dflt) { var n = Number(v); return v !== undefined && v !== null && v !== '' && n >= lo && n <= hi ? n : dflt; }
  function paramsOf(input) {
    var p = input;
    try { if (typeof p === 'string') p = JSON.parse(p); } catch (e) { p = {}; }
    if (!p || typeof p !== 'object') p = {};
    if (p.params && typeof p.params === 'object') p = p.params;
    return p;
  }

  /* no input region and the default key mask: the remote stays with the app under the notification */
  function noInput() {
    if (!window.PalmSystem) return;
    if (PalmSystem.setInputRegion) PalmSystem.setInputRegion([{ x: 0, y: 0, width: 0, height: 0 }]);
    if (PalmSystem.setKeyMask) PalmSystem.setKeyMask(['KeyMaskDefault']);
  }
  /* a floating window without focus */
  function passive() {
    if (!window.PalmSystem) return;
    if (PalmSystem.setWindowProperty) {
      PalmSystem.setWindowProperty('needFocus', 'false');
      PalmSystem.setWindowProperty('_WEBOS_WINDOW_TYPE', '_WEBOS_WINDOW_TYPE_FLOATING');
    }
    noInput();
  }

  function closeNow() {
    cancel('show'); cancel('hide'); cancel('close'); cancel('focus');
    window.close();
  }

  function show(p) {
    var text = typeof p.text === 'string' ? p.text.slice(0, 300) : '';
    if (!text) { if (!shown) closeNow(); return; }          // nothing to say: never leave an empty window
    cancel('hide'); cancel('close');
    box.textContent = text;
    box.className = 'toast' + (p.kind === 'error' ? ' toast--error' : '') + (text.length > CFG.longText ? ' toast--long' : '') + (shown ? ' toast--show' : '');
    if (!shown) {
      passive();
      // activate() only when it first appears: calling it again takes the focus from the app underneath
      if (window.PalmSystem && PalmSystem.activate) PalmSystem.activate();
      later('focus', function () {                           // the native window exists now: give the focus back
        if (window.PalmSystem && PalmSystem.setWindowProperty) PalmSystem.setWindowProperty('needFocus', 'false');
        noInput();
      }, 60);
      later('show', function () { box.className += ' toast--show'; }, 20);
    }
    var delay = num(p.ms, CFG.minMs, CFG.maxMs, CFG.ms);
    if (!shown) delay += num(p.appearMs, 0, CFG.maxAppear, CFG.appear);   // cold launch: the window is not up yet
    shown = true;
    later('hide', function () {
      box.className = box.className.replace(/ toast--show/g, '');
      later('close', closeNow, CFG.fade);
    }, delay);
  }

  function handle(input) {
    var p = paramsOf(input);
    if (p.close === true || p.close === 'true') { closeNow(); return; }
    show(p);
  }

  window.webOSRelaunch = function () {
    var p = {};
    try { p = window.PalmSystem ? PalmSystem.launchParams : {}; } catch (e) { /* ignore */ }
    handle(p);
    return true;
  };
  document.addEventListener('webOSRelaunch', function (event) {
    if (event && event.detail !== undefined) handle(event.detail);
  }, true);

  var initial = {};
  try { initial = window.PalmSystem ? PalmSystem.launchParams : {}; } catch (e) { /* ignore */ }
  if (!window.PalmSystem && window.location.search) {       // a browser preview: ?text=...&ms=...
    initial = {};
    window.location.search.slice(1).split('&').forEach(function (kv) {
      var i = kv.indexOf('=');
      if (i > 0) initial[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1).replace(/\+/g, ' '));
    });
  }
  handle(initial);
}());
