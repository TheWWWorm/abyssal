#!/usr/bin/env python3
"""Serve only an engine Web export on localhost. Private .abyss files are never served."""
import argparse, functools, http.server, pathlib
class EngineHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map={**http.server.SimpleHTTPRequestHandler.extensions_map,'.wasm':'application/wasm','.pck':'application/octet-stream','.js':'text/javascript'}
    def do_GET(self):
        from urllib.parse import urlsplit, unquote
        suffix=pathlib.Path(unquote(urlsplit(self.path).path)).suffix.lower()
        if suffix not in {'','.html','.js','.wasm','.pck','.png','.ico','.svg','.css','.md','.txt','.zip','.json'}:self.send_error(403);return
        super().do_GET()
    def list_directory(self,path):self.send_error(403);return None
    def end_headers(self):
        self.send_header('Cache-Control','no-store');super().end_headers()
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',required=True,type=pathlib.Path);p.add_argument('--port',type=int,default=8060);args=p.parse_args()
    directory=args.directory.expanduser().resolve()
    if not (directory/'index.html').is_file():p.error('Choose a Web export directory containing index.html.')
    server=http.server.ThreadingHTTPServer(('127.0.0.1',args.port),functools.partial(EngineHandler,directory=str(directory)))
    print(f'Open http://localhost:{args.port} (Ctrl+C to stop)',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
