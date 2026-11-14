/* Image viewer: view math + DOM wiring.
 * Classic script (not an ES module) so it loads from file:// in every browser.
 * The pure math is exported for Node tests at the bottom.
 */
(function () {
  'use strict';

  // ---------------------------------------------------------------- math --
  // A view is { scale, x, y }: image top-left (x, y) in frame pixels, and
  // scale = screen pixels per image pixel.

  var MAX_SCALE = 64;
  var MIN_SCALE = 0.01;
  var ZOOM_STEP = 1.25;

  function fitScale(iw, ih, fw, fh) {
    if (iw <= 0 || ih <= 0 || fw <= 0 || fh <= 0) return 1;
    return Math.min(fw / iw, fh / ih);
  }

  // Allowed scale range; always contains the fit scale and 100%.
  function scaleLimits(iw, ih, fw, fh) {
    var f = fitScale(iw, ih, fw, fh);
    return { min: Math.min(MIN_SCALE, f), max: Math.max(MAX_SCALE, f) };
  }

  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }

  // Image fitted into the frame and centered on both axes.
  function fitView(iw, ih, fw, fh) {
    var s = fitScale(iw, ih, fw, fh);
    return { scale: s, x: (fw - iw * s) / 2, y: (fh - ih * s) / 2 };
  }

  // Set an absolute scale, keeping the image point under (cx, cy) fixed.
  // Position is not limited: the image may be moved anywhere, even off-screen.
  function zoomTo(v, scale, cx, cy, iw, ih, fw, fh) {
    var lim = scaleLimits(iw, ih, fw, fh);
    var s = clamp(scale, lim.min, lim.max);
    var k = s / v.scale;
    return { scale: s, x: cx - (cx - v.x) * k, y: cy - (cy - v.y) * k };
  }

  function zoomBy(v, factor, cx, cy, iw, ih, fw, fh) {
    return zoomTo(v, v.scale * factor, cx, cy, iw, ih, fw, fh);
  }

  // Free panning: no limits.
  function panBy(v, dx, dy) {
    return { scale: v.scale, x: v.x + dx, y: v.y + dy };
  }

  // Frame resized from (ofw, ofh) to (fw, fh): keep the image point that was
  // at the old frame center at the new frame center.
  function recenter(v, ofw, ofh, iw, ih, fw, fh) {
    return { scale: v.scale, x: v.x + (fw - ofw) / 2, y: v.y + (fh - ofh) / 2 };
  }

  // Wheel delta -> zoom factor. Normalises line/page delta modes.
  function wheelFactor(deltaY, deltaMode, pageHeight) {
    var d = deltaY;
    if (deltaMode === 1) d *= 16;
    else if (deltaMode === 2) d *= pageHeight || 800;
    d = clamp(d, -300, 300);
    return Math.exp(-d * 0.002);
  }

  // ?src= value -> URL usable in <img src>.
  function resolveSrc(raw) {
    if (!raw) return '';
    if (/^[a-z]:[\\/]/i.test(raw)) {                         // C:\path
      return 'file:///' + raw.replace(/\\/g, '/').split('/').map(function (seg, i) {
        return i === 0 ? seg : encodeURIComponent(seg);
      }).join('/');
    }
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return raw;      // already a URL
    if (raw.charAt(0) === '/') {                             // /abs/path
      return 'file://' + raw.split('/').map(encodeURIComponent).join('/');
    }
    return raw;                                              // relative URL
  }

  function fileName(url) {
    var path = url.split(/[?#]/)[0];
    var last = path.split(/[\\/]/).filter(Boolean).pop() || url;
    try { return decodeURIComponent(last); } catch (e) { return last; }
  }

  var ViewMath = {
    fitScale: fitScale, scaleLimits: scaleLimits,
    fitView: fitView, zoomTo: zoomTo, zoomBy: zoomBy, panBy: panBy,
    recenter: recenter, wheelFactor: wheelFactor, resolveSrc: resolveSrc,
    fileName: fileName, ZOOM_STEP: ZOOM_STEP
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = ViewMath;
  if (typeof document === 'undefined') return;

  // ----------------------------------------------------------------- DOM --

  var $ = function (id) { return document.getElementById(id); };
  var frame = $('frame');
  var img = $('image');
  var checker = $('checker');
  var message = $('message');
  var btn = {
    zoomIn: $('btn-zoom-in'),
    zoomOut: $('btn-zoom-out'),
    fit: $('btn-fit'),
    actual: $('btn-actual')
  };
  var info = { name: $('info-name'), dims: $('info-dims'), zoom: $('info-zoom') };

  var state = {
    loaded: false,
    iw: 0, ih: 0,          // image natural size
    fw: 0, fh: 0,          // frame size
    view: { scale: 1, x: 0, y: 0 },
    fitMode: true          // re-fit on resize until the user zooms
  };

  var pending = false;
  function scheduleRender() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () { pending = false; render(); });
  }

  function render() {
    var v = state.view;
    var t = 'translate(' + v.x + 'px,' + v.y + 'px) scale(' + v.scale + ')';
    img.style.transform = t;
    img.classList.toggle('pixelated', v.scale > 3);

    // Checker is sized in screen pixels so its squares don't scale.
    checker.style.transform = 'translate(' + v.x + 'px,' + v.y + 'px)';
    checker.style.width = state.iw * v.scale + 'px';
    checker.style.height = state.ih * v.scale + 'px';

    var pct = v.scale * 100;
    info.zoom.textContent = (pct < 10 ? pct.toFixed(1) : Math.round(pct)) + '%';
    btn.fit.setAttribute('aria-pressed', String(state.fitMode));
    btn.actual.setAttribute('aria-pressed', String(Math.abs(v.scale - 1) < 1e-9));

    var lim = scaleLimits(state.iw, state.ih, state.fw, state.fh);
    btn.zoomIn.disabled = v.scale >= lim.max - 1e-9;
    btn.zoomOut.disabled = v.scale <= lim.min + 1e-9;

    frame.classList.toggle('can-pan', state.loaded);
  }

  function measureFrame() {
    state.fw = frame.clientWidth;
    state.fh = frame.clientHeight;
  }

  // -------------------------------------------------------------- actions --

  function args() { return [state.iw, state.ih, state.fw, state.fh]; }

  var actions = {
    zoomAll: function () {
      if (!state.loaded) return;
      state.view = fitView.apply(null, args());
      state.fitMode = true;
      scheduleRender();
    },
    zoom100: function () {
      if (!state.loaded) return;
      state.view = zoomTo.apply(null, [state.view, 1, state.fw / 2, state.fh / 2].concat(args()));
      state.fitMode = false;
      scheduleRender();
    },
    zoomAt: function (factor, cx, cy) {
      if (!state.loaded) return;
      state.view = zoomBy.apply(null, [state.view, factor, cx, cy].concat(args()));
      state.fitMode = false;
      scheduleRender();
    },
    zoomIn: function () { actions.zoomAt(ZOOM_STEP, state.fw / 2, state.fh / 2); },
    zoomOut: function () { actions.zoomAt(1 / ZOOM_STEP, state.fw / 2, state.fh / 2); },
    panBy: function (dx, dy) {
      if (!state.loaded) return;
      state.view = panBy(state.view, dx, dy);
      state.fitMode = false;
      scheduleRender();
    }
  };

  // -------------------------------------------------------------- toolbar --

  btn.zoomIn.addEventListener('click', actions.zoomIn);
  btn.zoomOut.addEventListener('click', actions.zoomOut);
  btn.fit.addEventListener('click', actions.zoomAll);
  btn.actual.addEventListener('click', actions.zoom100);
  // Keep keyboard focus off the toolbar so Space/Enter don't re-trigger buttons.
  document.querySelectorAll('#toolbar button').forEach(function (b) {
    b.addEventListener('mousedown', function (e) { e.preventDefault(); });
  });

  // ------------------------------------------------------------- keyboard --

  window.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    var step = (e.shiftKey ? 0.4 : 0.1);
    switch (e.key) {
      case '+': case '=': actions.zoomIn(); break;
      case '-': case '_': actions.zoomOut(); break;
      case 'a': case 'A': actions.zoomAll(); break;
      case '1': actions.zoom100(); break;
      // Arrows move the view (like scrolling): Right shows more of the right side.
      case 'ArrowLeft': actions.panBy(state.fw * step, 0); break;
      case 'ArrowRight': actions.panBy(-state.fw * step, 0); break;
      case 'ArrowUp': actions.panBy(0, state.fh * step); break;
      case 'ArrowDown': actions.panBy(0, -state.fh * step); break;
      default: return;
    }
    e.preventDefault();
  });

  // ---------------------------------------------------------------- mouse --

  function framePoint(e) {
    var r = frame.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  frame.addEventListener('wheel', function (e) {
    e.preventDefault();
    if (!e.deltaY) return;
    var p = framePoint(e);
    actions.zoomAt(wheelFactor(e.deltaY, e.deltaMode, state.fh), p.x, p.y);
  }, { passive: false });

  // Middle button: suppress autoscroll / paste, fit on click.
  frame.addEventListener('mousedown', function (e) {
    if (e.button === 1) e.preventDefault();
  });
  frame.addEventListener('auxclick', function (e) {
    if (e.button === 1) { e.preventDefault(); actions.zoomAll(); }
  });

  // Left drag: pan.
  var drag = null;
  frame.addEventListener('pointerdown', function (e) {
    if (e.button !== 0 || !state.loaded) return;
    e.preventDefault();
    drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
    frame.setPointerCapture(e.pointerId);
    frame.classList.add('panning');
  });
  frame.addEventListener('pointermove', function (e) {
    if (!drag || e.pointerId !== drag.id) return;
    var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.x = e.clientX; drag.y = e.clientY;
    actions.panBy(dx, dy);
  });
  function endDrag(e) {
    if (!drag || e.pointerId !== drag.id) return;
    drag = null;
    frame.classList.remove('panning');
  }
  frame.addEventListener('pointerup', endDrag);
  frame.addEventListener('pointercancel', endDrag);
  frame.addEventListener('contextmenu', function (e) { if (drag) e.preventDefault(); });

  // --------------------------------------------------------------- resize --

  window.addEventListener('resize', function () {
    var ofw = state.fw, ofh = state.fh;
    measureFrame();
    if (!state.loaded) return;
    state.view = state.fitMode
      ? fitView.apply(null, args())
      : recenter.apply(null, [state.view, ofw, ofh].concat(args()));
    scheduleRender();
  });

  // ------------------------------------------------------------- messages --

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  var KEYS_HTML =
    '<table>' +
    '<tr><td><kbd>+</kbd> / wheel</td><td>Zoom in</td></tr>' +
    '<tr><td><kbd>−</kbd> / wheel</td><td>Zoom out</td></tr>' +
    '<tr><td><kbd>A</kbd> / middle click</td><td>Fit to window</td></tr>' +
    '<tr><td><kbd>1</kbd></td><td>Actual size (100%)</td></tr>' +
    '<tr><td>arrows / left drag</td><td>Pan</td></tr>' +
    '</table>';

  function showMessage(html) {
    message.innerHTML = html;
    message.hidden = false;
    img.hidden = true;
    checker.hidden = true;
    info.dims.textContent = '';
    info.zoom.textContent = '';
    [btn.zoomIn, btn.zoomOut, btn.fit, btn.actual].forEach(function (b) { b.disabled = true; });
  }

  // ----------------------------------------------------------------- load --

  function start() {
    measureFrame();
    var raw = new URLSearchParams(location.search).get('src') || window.SRC || '';
    var src = resolveSrc(raw);

    if (!src) {
      showMessage(
        '<h1>No image</h1>' +
        '<p>Open this page with an image: <code>viewer.html?src=file:///path/to/image.jpg</code></p>' +
        KEYS_HTML);
      return;
    }

    var name = fileName(src);
    document.title = name;
    info.name.textContent = name;
    info.name.title = raw;

    img.onload = function () {
      var w = img.naturalWidth, h = img.naturalHeight;
      if (!w || !h) { w = h = 1000; }        // e.g. SVG without intrinsic size
      state.iw = w; state.ih = h;
      img.style.width = w + 'px';
      img.style.height = h + 'px';
      info.dims.textContent = (img.naturalWidth && img.naturalHeight)
        ? w + ' × ' + h : 'no intrinsic size';
      state.loaded = true;
      measureFrame();
      actions.zoomAll();
      render();                              // fit before first paint: no flash of 100%
      img.hidden = false;
      checker.hidden = false;
    };
    img.onerror = function () {
      showMessage('<h1>Cannot load image</h1><p><code>' + esc(raw) + '</code></p>');
    };
    img.src = src;
  }

  start();
})();
