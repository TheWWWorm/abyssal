/* The shell owns canvas sizing (Godot canvasResizePolicy: 0). Measuring its
 * displayed rectangle avoids stale innerHeight values on iOS Home Screen
 * launch and keeps rendering and touch coordinates on the same scale. */
(function () {
  'use strict';
  const modes = ['standalone', 'fullscreen'].map(mode => matchMedia(`(display-mode: ${mode})`));
  function displayMode() {
    const root = document.documentElement;
    const installed = navigator.standalone === true || modes.some(mode => mode.matches);
    root.classList.toggle('abyssal-standalone', installed);
    // An installed iPhone app occupies the screen, but WebKit can retain even
    // CSS viewport units from the previous orientation. Screen dimensions are
    // CSS pixels, so use them here only; tabs and windowed iPads keep CSS sizing.
    const screen = window.screen;
    if (installed && /iPhone|iPod/.test(navigator.userAgent) && screen?.width > 0 && screen.height > 0) {
      const short = Math.min(screen.width, screen.height), long = Math.max(screen.width, screen.height);
      const landscape = typeof window.orientation === 'number' ? Math.abs(window.orientation) % 180 === 90
        : Math.abs(window.innerWidth - long) < Math.abs(window.innerWidth - short);
      root.style.setProperty('--abyssal-app-width', `${landscape ? long : short}px`);
      root.style.setProperty('--abyssal-app-height', `${landscape ? short : long}px`);
    } else {
      root.style.removeProperty('--abyssal-app-width');
      root.style.removeProperty('--abyssal-app-height');
    }
  }
  displayMode();

  function start() {
    const canvas = document.getElementById('canvas');
    if (!canvas) return;
    let frame = 0;
    let settling = [];

    function resize() {
      frame = 0;
      if (document.hidden) return;
      displayMode();
      const rect = canvas.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return;
      const scale = window.devicePixelRatio || 1;
      const width = Math.max(1, Math.round(rect.width * scale));
      const height = Math.max(1, Math.round(rect.height * scale));
      // Assigning either dimension clears a canvas, even when it is unchanged.
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
    }
    function queue() {
      if (!frame && !document.hidden) frame = requestAnimationFrame(resize);
    }
    function pause() {
      settling.forEach(clearTimeout);
      settling = [];
      cancelAnimationFrame(frame);
      frame = 0;
    }
    function refresh() {
      pause();
      displayMode();
      queue();
      // WebKit may finish a launch/rotation after the first event. Recheck
      // briefly, without a permanent render loop or work in the background.
      if (!document.hidden) settling = [250, 1000].map(delay => setTimeout(queue, delay));
    }

    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(queue).observe(canvas);
    window.addEventListener('resize', queue);
    window.visualViewport?.addEventListener('resize', queue);
    window.addEventListener('orientationchange', refresh);
    window.addEventListener('pageshow', refresh);
    window.addEventListener('load', refresh);
    window.addEventListener('pagehide', pause);
    document.addEventListener('visibilitychange', refresh);
    document.addEventListener('fullscreenchange', refresh);
    document.addEventListener('webkitfullscreenchange', refresh);
    modes.forEach(mode => mode.addEventListener('change', refresh));
    resize();
    refresh();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, {once: true});
  else start();
}());
