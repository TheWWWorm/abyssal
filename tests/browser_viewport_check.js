/* Canvas size and page lifecycle regressions, without a browser or game assets. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const source = fs.readFileSync(path.join(__dirname, '../browser/viewport.js'), 'utf8');

function target(properties = {}) {
  const listeners = new Map();
  return Object.assign(properties, {
    addEventListener(name, callback) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(callback);
    },
    emit(name) { for (const callback of listeners.get(name) || []) callback(); },
  });
}

function setup({standalone = false, loading = false, observer = true, iphone = false} = {}) {
  const frames = new Map(), timers = new Map(), classes = new Set(), writes = [];
  const properties = new Map();
  let next = 0, rect = {width: 844, height: 390}, pixels = {width: 300, height: 150};
  const canvas = {getBoundingClientRect: () => rect};
  for (const axis of ['width', 'height']) Object.defineProperty(canvas, axis, {
    get: () => pixels[axis], set(value) {pixels[axis] = value; writes.push([axis, value]);},
  });
  const document = target({hidden: false, readyState: loading ? 'loading' : 'complete',
    getElementById: () => loading ? null : canvas,
    documentElement: {classList: {toggle(name, on) {if (on) classes.add(name); else classes.delete(name);}},
      style: {setProperty(name, value) {properties.set(name, value);}, removeProperty(name) {properties.delete(name);}}},
  });
  const window = target({innerWidth: 844, innerHeight: 325, devicePixelRatio: 3, visualViewport: target(),
    screen: {width: 390, height: 844}, orientation: 90});
  const media = new Map(['standalone', 'fullscreen'].map(mode => [`(display-mode: ${mode})`, target({matches: false})]));
  let observed;
  const context = vm.createContext({document, window, navigator: {standalone, userAgent: iphone ? 'iPhone' : 'Other'}, matchMedia: query => media.get(query),
    requestAnimationFrame(callback) {const id = ++next; frames.set(id, callback); return id;},
    cancelAnimationFrame(id) {frames.delete(id);},
    setTimeout(callback, delay) {const id = ++next; timers.set(id, {callback, delay}); return id;},
    clearTimeout(id) {timers.delete(id);},
    ResizeObserver: observer ? class {
      constructor(callback) {this.callback = callback;}
      observe(element) {assert.equal(element, canvas); observed = this.callback;}
    } : undefined,
  });
  vm.runInContext(source, context);
  return {document, window, canvas, classes, properties, media, frames, timers, writes,
    dimensions(width, height) {rect = {width, height};},
    frame() {const callbacks = [...frames.values()]; frames.clear(); callbacks.forEach(callback => callback());},
    settle(delay) {for (const [id, timer] of timers) if (timer.delay === delay) {timers.delete(id); timer.callback();}},
    observe() {observed();},
    ready() {loading = false; document.readyState = 'complete'; document.emit('DOMContentLoaded');},
  };
}

test('fresh Home Screen launch fills the displayed canvas despite a short innerHeight', () => {
  const s = setup({standalone: true, loading: true});
  assert.ok(s.classes.has('abyssal-standalone'));
  assert.equal(s.writes.length, 0);
  s.ready();
  assert.deepEqual([s.canvas.width, s.canvas.height], [2532, 1170]);
  assert.equal(s.window.innerHeight, 325);
});

test('installed iPhones recover the screen extent even when CSS retains the previous orientation', () => {
  const s = setup({standalone: true, iphone: true});
  assert.equal(s.properties.get('--abyssal-app-width'), '844px');
  assert.equal(s.properties.get('--abyssal-app-height'), '390px');
  s.window.orientation = 0; s.window.emit('orientationchange'); s.frame();
  assert.equal(s.properties.get('--abyssal-app-width'), '390px');
  assert.equal(s.properties.get('--abyssal-app-height'), '844px');
  s.window.orientation = -90; s.window.emit('orientationchange'); s.frame();
  assert.equal(s.properties.get('--abyssal-app-width'), '844px');
  assert.equal(s.properties.get('--abyssal-app-height'), '390px');
  assert.equal(setup({iphone: true}).properties.size, 0, 'Safari tabs keep their available viewport');
  assert.equal(setup({standalone: true}).properties.size, 0, 'Windowed tablets and desktops keep their available viewport');
});

test('rotation and CSS-only size changes update backing pixels, not CSS or aspect ratio', () => {
  const s = setup(); s.frame();
  s.dimensions(390, 844); s.window.emit('orientationchange'); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [1170, 2532]);
  s.dimensions(844, 390); s.observe(); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [2532, 1170]);
  assert.equal(s.canvas.style, undefined);
});

test('unchanged event bursts do not clear the canvas or start a permanent loop', () => {
  const s = setup(); s.frame(); const before = s.writes.length;
  for (let i = 0; i < 10; i++) {s.observe(); s.window.emit('resize'); s.window.visualViewport.emit('resize');}
  assert.equal(s.frames.size, 1); s.frame();
  s.settle(250); s.frame(); s.settle(1000); s.frame();
  assert.equal(s.writes.length, before);
  assert.equal(s.frames.size, 0); assert.equal(s.timers.size, 0);
});

test('late launch measurements and a restored page recover without a window resize', () => {
  const s = setup({observer: false}); s.frame();
  s.dimensions(844, 393); s.settle(250); s.frame();
  assert.equal(s.canvas.height, 1179);
  s.window.emit('pagehide'); assert.equal(s.timers.size, 0);
  s.dimensions(393, 844); s.window.emit('pageshow'); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [1179, 2532]);
});

test('backgrounding suspends checks and resuming refreshes the viewport', () => {
  const s = setup(); s.document.hidden = true; s.document.emit('visibilitychange');
  assert.equal(s.frames.size, 0); assert.equal(s.timers.size, 0);
  s.dimensions(390, 844); s.window.emit('resize'); s.observe();
  assert.equal(s.frames.size, 0);
  s.document.hidden = false; s.document.emit('visibilitychange'); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [1170, 2532]);
});

test('browser tabs and installed/fullscreen modes select their own viewport sizing', () => {
  const s = setup(); assert.ok(!s.classes.has('abyssal-standalone'));
  const standalone = s.media.get('(display-mode: standalone)');
  standalone.matches = true; standalone.emit('change'); assert.ok(s.classes.has('abyssal-standalone'));
  standalone.matches = false; standalone.emit('change'); assert.ok(!s.classes.has('abyssal-standalone'));
  const full = s.media.get('(display-mode: fullscreen)');
  full.matches = true; s.document.emit('fullscreenchange'); assert.ok(s.classes.has('abyssal-standalone'));
  full.matches = false; s.document.emit('webkitfullscreenchange'); assert.ok(!s.classes.has('abyssal-standalone'));
});

test('density changes stay sharp and transient zero-size rectangles are ignored', () => {
  const s = setup(); s.frame();
  s.window.devicePixelRatio = 1.25; s.dimensions(801, 601); s.window.emit('resize'); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [1001, 751]);
  s.dimensions(0, 0); s.observe(); s.frame();
  assert.deepEqual([s.canvas.width, s.canvas.height], [1001, 751]);
});

test('web safe-area fractions use the displayed canvas instead of stale window dimensions', () => {
  const gd = fs.readFileSync(path.join(__dirname, '../game/native/platform/safe_margins.gd'), 'utf8');
  const script = gd.match(/JavaScriptBridge\.eval\("""([\s\S]*?)""",true\)/)[1];
  const probe = {style: {}, remove() {}};
  const context = {window: {innerWidth: 844, innerHeight: 325},
    getComputedStyle: () => ({paddingLeft: '47px', paddingRight: '47px', paddingTop: '0px', paddingBottom: '21px'}),
    document: {createElement: () => probe, body: {appendChild() {}},
      getElementById: () => ({getBoundingClientRect: () => ({width: 844, height: 390})})},
  };
  assert.equal(vm.runInNewContext(script, context), '47,47,0,21,844,390');
});
