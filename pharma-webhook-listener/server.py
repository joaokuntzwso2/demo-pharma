from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        print("Webhook health check received", flush=True)
        body = b"UP"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length).decode("utf-8")

        print("\n=== WEBHOOK RECEIVED ===", flush=True)
        print("Path:", self.path, flush=True)
        print("Headers:", dict(self.headers), flush=True)
        print("Body:", raw_body, flush=True)

        try:
            body_json = json.loads(raw_body)
            print("Parsed JSON:", json.dumps(body_json, indent=2), flush=True)
        except Exception:
            print("Body is not valid JSON", flush=True)

        body = b"OK"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    print("Webhook listener running on 0.0.0.0:8099", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8099), Handler).serve_forever()