#!/usr/bin/env python3
"""Loopback relay for exercising the app's reconnect path against real ntfy.sh.

The first subscriber receives an open event and a clean EOF. Later subscriptions
and publishes are relayed to ntfy.sh. It binds loopback only and uses stdlib.
"""
import http.server
import json
import sys
import threading
import urllib.error
import urllib.request


TOPIC = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 18765
UPSTREAM = f"https://ntfy.sh/{TOPIC}"
counter_lock = threading.Lock()
stream_requests = 0


class Relay(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_GET(self):
        global stream_requests
        with counter_lock:
            stream_requests += 1
            request_number = stream_requests
        if self.path != f"/{TOPIC}/json":
            self.send_error(404)
            return

        if request_number == 1:
            event = json.dumps({"id": "relay-open", "time": 1792648000, "event": "open", "topic": TOPIC}).encode() + b"\n"
            self.send_response(200)
            self.send_header("Content-Type", "application/stream+json; charset=utf-8")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(event)
            self.wfile.flush()
            self.close_connection = True
            return

        upstream = urllib.request.Request(UPSTREAM + "/json", headers={"Accept": "application/stream+json"})
        try:
            response = urllib.request.urlopen(upstream, timeout=180)
        except urllib.error.HTTPError as error:
            self.send_error(error.code)
            return
        self.send_response(response.status)
        self.send_header("Content-Type", response.headers.get("Content-Type", "application/stream+json"))
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            while True:
                chunk = response.read1(4096)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            response.close()
            self.close_connection = True

    def do_POST(self):
        if self.path != f"/{TOPIC}":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        headers = {"Content-Type": self.headers.get("Content-Type", "text/plain; charset=utf-8")}
        for name in ("Title", "Priority", "Tags", "Authorization"):
            if self.headers.get(name):
                headers[name] = self.headers[name]
        request = urllib.request.Request(UPSTREAM, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
                self.send_response(response.status)
                self.send_header("Content-Type", response.headers.get("Content-Type", "application/json"))
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
        except urllib.error.HTTPError as error:
            payload = error.read()
            self.send_response(error.code)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)


server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Relay)
print(f"READY {server.server_address[1]}", flush=True)
server.serve_forever()
