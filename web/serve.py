#!/usr/bin/env python3
"""Auslieferung des Godot-Web-Exports.

Braucht Cross-Origin-Opener/Embedder-Policy-Header, weil der Godot-Web-Export
Threads nutzt (SharedArrayBuffer funktioniert ohne diese Header nicht).

    python3 web/serve.py [port]
"""

from __future__ import annotations

import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB_DIR = Path(__file__).resolve().parent


class GodotHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".ogg": "audio/ogg",
        ".svg": "image/svg+xml",
    }

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    handler = partial(GodotHandler, directory=str(WEB_DIR))
    server = ThreadingHTTPServer(("0.0.0.0", port), handler)
    print(f"Lóng Chéng Web-Export: http://0.0.0.0:{port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
