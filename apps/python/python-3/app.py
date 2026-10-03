import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


def burn():
    n = 0
    while True:
        n = (n * 1103515245 + 12345) & 0x7FFFFFFF


if __name__ == "__main__":
    threads = int(os.environ.get("CPU_THREADS", "1"))
    for _ in range(threads):
        threading.Thread(target=burn, daemon=True).start()
    port = int(os.environ.get("PORT", "8080"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
