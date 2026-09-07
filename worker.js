// Serves the exported Web build from the static asset store.
//
// Assets above Cloudflare's 25 MiB limit are stored by tools/prepare_web_host.py
// as sequential .part0, .part1, ... files. Stored assets are served directly by
// the platform, so this only runs for paths with no stored asset: it streams the
// parts back together under the requested name.
//
// The parts are stored uncompressed on purpose. Cloudflare negotiates its own
// Content-Encoding for the response, and it strips a Content-Encoding set here,
// so serving pre-compressed bytes reaches the browser undecoded.

const CONTENT_TYPES = {
  wasm: 'application/wasm',
  js: 'text/javascript; charset=utf-8',
  json: 'application/json; charset=utf-8',
  pck: 'application/octet-stream',
  zip: 'application/zip',
};

function joinParts(env, origin, pathname, first) {
  const { readable, writable } = new TransformStream();
  (async () => {
    let response = first;
    let index = 0;
    try {
      while (response && response.ok) {
        await response.body.pipeTo(writable, { preventClose: true });
        index += 1;
        response = await env.ASSETS.fetch(new URL(`${pathname}.part${index}`, origin));
      }
      await writable.close();
    } catch (error) {
      await writable.abort(error);
    }
  })();
  return readable;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const first = await env.ASSETS.fetch(new URL(`${url.pathname}.part0`, url.origin));
    if (!first.ok) {
      return env.ASSETS.fetch(request);
    }
    const headers = new Headers();
    const extension = url.pathname.split('.').pop().toLowerCase();
    if (CONTENT_TYPES[extension]) {
      headers.set('Content-Type', CONTENT_TYPES[extension]);
    }
    headers.set('X-Content-Type-Options', 'nosniff');
    headers.set('Cache-Control', 'public, max-age=604800');
    return new Response(joinParts(env, url.origin, url.pathname, first), { status: 200, headers });
  },
};
