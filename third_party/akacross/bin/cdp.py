#!/usr/bin/env python3
"""Tiny dependency-free Chrome DevTools Protocol client for the launcher's WebView2."""
import base64, hashlib, json, os, socket, ssl, struct, sys, time, urllib.request

HOST, PORT = "127.0.0.1", 9222

def targets():
    with urllib.request.urlopen(f"http://{HOST}:{PORT}/json", timeout=5) as r:
        return json.load(r)

class WS:
    def __init__(self, url):
        path = url.split(f"{HOST}:{PORT}", 1)[1]
        self.s = socket.create_connection((HOST, PORT), timeout=15)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               f"Origin: http://{HOST}:{PORT}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.s.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        if b"101" not in buf.split(b"\r\n")[0]:
            raise RuntimeError("handshake failed: " + buf.split(b"\r\n")[0].decode())
        self.buf = buf.split(b"\r\n\r\n", 1)[1]
        self.id = 0

    def _recv(self, n):
        while len(self.buf) < n:
            d = self.s.recv(65536)
            if not d: raise ConnectionError("closed")
            self.buf += d
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, method, **params):
        self.id += 1
        payload = json.dumps({"id": self.id, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        n = len(payload)
        hdr = b"\x81"
        if n < 126:   hdr += bytes([0x80 | n])
        elif n < 1<<16: hdr += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:         hdr += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        return self.id

    def recv(self):
        b0, b1 = self._recv(2)
        n = b1 & 0x7F
        if n == 126:   n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127: n = struct.unpack(">Q", self._recv(8))[0]
        return json.loads(self._recv(n).decode("utf-8", "replace"))
