/* Keep startup readable by older WebViews so unsupported converters report why. */
(function (scope) {
  'use strict';
  var failed = false;
  var match = /(?:Chrome|Chromium)\/([\d.]+)/.exec(scope.navigator.userAgent);
  var version = match ? ' (Chromium ' + match[1] + ')' : '';
  var recovery = 'Update the active Android System WebView and try your JAR again.';

  function fail(message, error) {
    if (failed) return;
    failed = true;
    console.error('Offline importer startup failed:', message, error || '');
    AbyssalNative.failed(message + version);
  }

  if (!scope.globalThis) scope.globalThis = scope;
  if (typeof scope.WebAssembly !== 'object') {
    fail('Android System WebView cannot run the JAR converter. ' + recovery);
    return;
  }
  var runtime = 'vendor/';
  try {
    // Probe syntax as a string: a parse failure in pyodide.js otherwise hides
    // its cause behind the next script's "loadPyodide is not defined" error.
    new Function('var x = {}; x.value ??= 0; x.value ||= 1; x.value &&= 2; return x?.value ?? 0;')();
    if (typeof scope.WebAssembly.Tag !== 'function'
        || typeof scope.WebAssembly.Exception !== 'function' || typeof scope.BigInt !== 'function'
        || typeof scope.BigInt64Array !== 'function') {
      throw new Error('Required WebAssembly features are unavailable.');
    }
  } catch (error) {
    // This runtime predates logical assignment, Wasm BigInt integration and
    // Wasm exceptions. Both runtimes execute the same resource-only decoder.
    runtime = 'vendor-compat/';
  }
  scope.AbyssalImporterRuntime = {indexURL: new URL(runtime, scope.location.href).href};
  console.info('Bundled importer runtime:', runtime, version);

  // A script's load event can fire even when its JavaScript failed to parse.
  // Keep this handler installed for pyodide.asm.js, loaded during conversion.
  scope.addEventListener('error', function (event) {
    var source = event.filename || '';
    if (source.indexOf(scope.location.origin + '/') !== 0) return;
    fail('The bundled converter could not start: ' + (event.message || 'Script error.') + ' ' + recovery, event.error);
  });

  var scripts = [
    [runtime + 'pyodide.js', function () { return typeof scope.loadPyodide === 'function'; }],
    ['vendor/amrnb.js', function () { return scope.AMR && typeof scope.AMR.toWAV === 'function'; }],
    ['audio.js', function () { return scope.AbyssalAudio && typeof scope.AbyssalAudio.midiWav === 'function'; }],
    ['import.js', function () { return true; }]
  ];
  function load(index) {
    if (failed || index === scripts.length) return;
    var entry = scripts[index];
    var script = scope.document.createElement('script');
    script.src = entry[0];
    script.onload = function () {
      if (failed) return;
      if (!entry[1]()) {
        fail('The bundled converter did not initialize: ' + entry[0] + '. ' + recovery);
        return;
      }
      load(index + 1);
    };
    script.onerror = function () {
      fail('A bundled converter file could not load: ' + entry[0] + '. Reinstall the APK and try your JAR again.');
    };
    scope.document.head.appendChild(script);
  }
  AbyssalNative.progress('Loading bundled converter scripts…');
  load(0);
})(window);
