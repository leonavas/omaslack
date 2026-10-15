#!/usr/bin/env python3
"""Network transport for the Slack plugin: nothing but bytes on the wire.

The QML side owns every decision; this process only does what QML cannot:
HTTPS with the session cookie (QML's XMLHttpRequest drops `Cookie`), a
WebSocket it can also write to, files to disk, and the sign-in window's
cookie database. One process per workspace, spoken to in JSON lines:

  stdin   {"id": 7, "op": "call", "method": "auth.test", "params": {...}}
  stdout  {"id": 7, "ok": true, "status": 200, "body": {...}}

Ops: creds, call, download, post_file, multipart, read_cookie, ws_open,
ws_send, ws_close. Socket traffic comes back unprompted as
{"ws": "open"}, {"ws": "msg", "data": {...}}, {"ws": "closed", "reason": ...}.
Credentials only ever arrive on stdin and only ever go to slack.com hosts.
"""

import base64
import gzip
import json
import os
import random
import shutil
import socket
import sqlite3
import ssl
import struct
import sys
import tempfile
import threading
import time
import urllib.parse
import zlib
from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPSConnection, HTTPException

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
API_HOST = "slack.com"
WS_PING_EVERY = 30
WS_DEAD_AFTER = 95

out_lock = threading.Lock()
creds = {"token": "", "cookie": ""}
ctx = ssl.create_default_context()
local = threading.local()


def emit(obj):
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    with out_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def is_slack(host):
    host = (host or "").lower()
    return host == "slack.com" or host.endswith(".slack.com")


def auth_headers():
    h = {}
    if creds["token"]:
        h["Authorization"] = "Bearer " + creds["token"]
    if creds["cookie"]:
        h["Cookie"] = "d=" + creds["cookie"]
    return h


def decode(body, encoding):
    encoding = (encoding or "").lower()
    if encoding == "gzip":
        return gzip.decompress(body)
    if encoding == "deflate":
        return zlib.decompress(body)
    return body


def conn_for(host):
    pool = getattr(local, "pool", None)
    if pool is None:
        pool = local.pool = {}
    c = pool.get(host)
    if c is None:
        c = pool[host] = HTTPSConnection(host, 443, timeout=40, context=ctx)
    return c


def drop_conn(host):
    pool = getattr(local, "pool", {})
    c = pool.pop(host, None)
    if c is not None:
        try:
            c.close()
        except Exception:
            pass


def request(method, url, body=None, headers=None, stream_to=None):
    """One request on this thread's kept-alive connection; a stale one is
    reopened once. Returns (status, headers, bytes or None)."""
    u = urllib.parse.urlsplit(url)
    host = u.hostname
    path = u.path or "/"
    if u.query:
        path += "?" + u.query
    hdrs = {"User-Agent": UA, "Accept-Encoding": "gzip"}
    if headers:
        hdrs.update(headers)
    for attempt in range(2):
        c = conn_for(host)
        try:
            c.request(method, path, body=body, headers=hdrs)
            r = c.getresponse()
            rh = {k.lower(): v for k, v in r.getheaders()}
            if stream_to is not None and r.status == 200:
                enc = rh.get("content-encoding", "")
                if enc:
                    data = decode(r.read(), enc)
                    stream_to.write(data)
                else:
                    shutil.copyfileobj(r, stream_to, 1 << 16)
                return r.status, rh, None
            data = decode(r.read(), rh.get("content-encoding", ""))
            if rh.get("connection", "").lower() == "close":
                drop_conn(host)
            return r.status, rh, data
        except (HTTPException, OSError):
            drop_conn(host)
            if attempt == 1:
                raise
    raise OSError("unreachable")


def op_call(msg):
    method = msg.get("method", "")
    params = dict(msg.get("params") or {})
    if creds["cookie"] and creds["token"]:
        params.setdefault("token", creds["token"])
    for k, v in list(params.items()):
        if isinstance(v, (dict, list)):
            params[k] = json.dumps(v, separators=(",", ":"))
        elif isinstance(v, bool):
            params[k] = "true" if v else "false"
        elif v is None:
            del params[k]
        else:
            params[k] = str(v)
    body = urllib.parse.urlencode(params).encode()
    host = msg.get("host") or API_HOST
    url = "https://%s/api/%s" % (host, method)
    headers = auth_headers()
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    net_tries = 0
    for _ in range(8):
        try:
            status, rh, data = request("POST", url, body, headers)
        except Exception as e:
            net_tries += 1
            if net_tries >= 3:
                return {"ok": False, "error": "network: %s" % e}
            time.sleep(1.5 * net_tries)
            continue
        if status == 429:
            try:
                wait = int(rh.get("retry-after", "2"))
            except ValueError:
                wait = 2
            time.sleep(min(30, max(1, wait)))
            continue
        try:
            parsed = json.loads(data.decode("utf-8", "replace") or "null")
        except ValueError:
            return {"ok": False, "status": status, "error": "http %d" % status}
        return {"ok": True, "status": status, "body": parsed}
    return {"ok": False, "error": "ratelimited"}


def op_download(msg):
    url = msg["url"]
    dest = msg["dest"]
    # `reuse`: a file already in the cache is used again, and its
    # modification time becomes its last use, so what keeps being looked at
    # never expires (the plugin deletes what's a week unseen).
    if msg.get("reuse"):
        try:
            if os.path.getsize(dest) > 0:
                os.utime(dest)
                return {"ok": True, "path": dest, "mime": "", "cached": True}
        except OSError:
            pass
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    for _ in range(6):
        u = urllib.parse.urlsplit(url)
        headers = auth_headers() if is_slack(u.hostname) else {}
        tmp = dest + ".part"
        try:
            with open(tmp, "wb") as f:
                status, rh, data = request("GET", url, None, headers, stream_to=f)
        except Exception as e:
            return {"ok": False, "error": str(e)}
        if status in (301, 302, 303, 307, 308) and rh.get("location"):
            url = urllib.parse.urljoin(url, rh["location"])
            continue
        if status != 200:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return {"ok": False, "error": "http %d" % status}
        mime = rh.get("content-type", "")
        if mime.startswith("text/html") and not msg.get("html_ok"):
            os.unlink(tmp)
            return {"ok": False, "error": "html"}
        os.replace(tmp, dest)
        return {"ok": True, "path": dest, "mime": mime}
    return {"ok": False, "error": "redirects"}


def op_post_file(msg):
    """The bytes of a file to an upload URL (files.getUploadURLExternal)."""
    path = msg["path"]
    with open(path, "rb") as f:
        data = f.read()
    url = msg["url"]
    u = urllib.parse.urlsplit(url)
    headers = auth_headers() if is_slack(u.hostname) else {}
    headers["Content-Type"] = "application/octet-stream"
    try:
        status, rh, body = request("POST", url, data, headers)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": 200 <= status < 300, "status": status, "text": (body or b"")[:2000].decode("utf-8", "replace")}


def op_multipart(msg):
    """A Web API method that only takes multipart (users.setPhoto)."""
    boundary = "slackqs%x" % random.getrandbits(64)
    parts = []
    fields = dict(msg.get("fields") or {})
    if creds["cookie"] and creds["token"]:
        fields.setdefault("token", creds["token"])
    for k, v in fields.items():
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    path = msg.get("path")
    if path:
        name = os.path.basename(path).replace('"', "")
        mime = msg.get("mime") or "application/octet-stream"
        with open(path, "rb") as f:
            data = f.read()
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                      % (boundary, msg.get("field", "file"), name, mime)).encode() + data + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode())
    headers = auth_headers()
    headers["Content-Type"] = "multipart/form-data; boundary=" + boundary
    try:
        status, rh, body = request("POST", "https://%s/api/%s" % (API_HOST, msg["method"]), b"".join(parts), headers)
        return {"ok": True, "status": status, "body": json.loads(body.decode("utf-8", "replace") or "null")}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def op_read_cookie(msg):
    """The `d` cookie the sign-in window's browser profile saved (HttpOnly:
    the page itself can never read it)."""
    db = msg["db"]
    if not os.path.exists(db):
        return {"ok": False, "error": "no cookie database"}
    tmpdir = tempfile.mkdtemp()
    try:
        copy = os.path.join(tmpdir, "Cookies")
        shutil.copyfile(db, copy)
        if os.path.exists(db + "-journal"):
            shutil.copyfile(db + "-journal", copy + "-journal")
        con = sqlite3.connect(copy)
        rows = con.execute(
            "select value, host_key from cookies where name = 'd' and (host_key = '.slack.com' or host_key like '%.slack.com' or host_key = 'slack.com') order by length(value) desc").fetchall()
        con.close()
    except Exception as e:
        return {"ok": False, "error": str(e)}
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    for value, host in rows:
        if value:
            return {"ok": True, "cookie": value}
    return {"ok": False, "error": "no d cookie"}


class Socket:
    """A WebSocket client, RFC 6455, just what Slack's socket needs."""

    def __init__(self, url):
        self.url = url
        self.sock = None
        self.wlock = threading.Lock()
        self.alive = False
        self.last_rx = time.time()
        self.ping_id = 0

    def connect(self):
        u = urllib.parse.urlsplit(self.url)
        host = u.hostname
        port = u.port or 443
        raw = socket.create_connection((host, port), timeout=30)
        sock = ctx.wrap_socket(raw, server_hostname=host)
        key = base64.b64encode(os.urandom(16)).decode()
        path = (u.path or "/") + ("?" + u.query if u.query else "")
        lines = [
            "GET %s HTTP/1.1" % path,
            "Host: %s" % host,
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: %s" % key,
            "Sec-WebSocket-Version: 13",
            "Origin: https://app.slack.com",
            "User-Agent: %s" % UA,
        ]
        if creds["cookie"] and is_slack(host):
            lines.append("Cookie: d=%s" % creds["cookie"])
        sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = sock.recv(4096)
            if not chunk:
                raise OSError("closed during handshake")
            head += chunk
            if len(head) > 65536:
                raise OSError("handshake too long")
        head, rest = head.split(b"\r\n\r\n", 1)
        status = head.split(b"\r\n", 1)[0].decode("latin-1")
        if " 101 " not in status + " ":
            raise OSError("handshake: " + status)
        sock.settimeout(None)
        self.sock = sock
        self.buf = rest
        self.alive = True
        self.last_rx = time.time()

    def read_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise OSError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send_frame(self, opcode, payload):
        header = bytearray([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += struct.pack("!H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack("!Q", n)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        with self.wlock:
            self.sock.sendall(bytes(header) + masked)

    def send_text(self, text):
        self.send_frame(0x1, text.encode("utf-8"))

    def close(self):
        self.alive = False
        try:
            self.send_frame(0x8, b"")
        except Exception:
            pass
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass

    def reader(self):
        parts = []
        reason = "closed"
        try:
            while self.alive:
                b0, b1 = self.read_exact(2)
                fin, opcode = b0 & 0x80, b0 & 0x0F
                n = b1 & 0x7F
                if n == 126:
                    n = struct.unpack("!H", self.read_exact(2))[0]
                elif n == 127:
                    n = struct.unpack("!Q", self.read_exact(8))[0]
                mask = self.read_exact(4) if b1 & 0x80 else None
                payload = self.read_exact(n) if n else b""
                if mask:
                    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                self.last_rx = time.time()
                if opcode == 0x9:
                    self.send_frame(0xA, payload)
                    continue
                if opcode == 0xA:
                    continue
                if opcode == 0x8:
                    reason = "server closed"
                    break
                if opcode in (0x1, 0x2, 0x0):
                    parts.append(payload)
                    if not fin:
                        continue
                    text = b"".join(parts).decode("utf-8", "replace")
                    parts = []
                    try:
                        data = json.loads(text)
                    except ValueError:
                        continue
                    emit({"ws": "msg", "data": data})
        except Exception as e:
            reason = str(e) or "error"
        self.alive = False
        try:
            self.sock.close()
        except Exception:
            pass
        emit({"ws": "closed", "reason": reason})

    def pinger(self):
        while self.alive:
            time.sleep(5)
            if not self.alive:
                return
            idle = time.time() - self.last_rx
            if idle > WS_DEAD_AFTER:
                self.close()
                return
            if idle >= WS_PING_EVERY:
                self.ping_id += 1
                try:
                    self.send_text(json.dumps({"id": self.ping_id, "type": "ping"}))
                except Exception:
                    self.close()
                    return


ws = {"cur": None}
ws_lock = threading.Lock()


def op_ws_open(msg):
    with ws_lock:
        old = ws["cur"]
        if old:
            old.close()
        s = Socket(msg["url"])
        ws["cur"] = s
    try:
        s.connect()
    except Exception as e:
        emit({"ws": "closed", "reason": "connect: %s" % e})
        return None
    emit({"ws": "open"})
    threading.Thread(target=s.reader, daemon=True).start()
    threading.Thread(target=s.pinger, daemon=True).start()
    return None


def op_ws_send(msg):
    s = ws["cur"]
    if s and s.alive:
        try:
            s.send_text(json.dumps(msg.get("data"), separators=(",", ":")))
        except Exception:
            s.close()
    return None


def op_ws_close(msg):
    with ws_lock:
        s = ws["cur"]
        ws["cur"] = None
    if s:
        s.close()
    return None


OPS = {
    "call": op_call,
    "download": op_download,
    "post_file": op_post_file,
    "multipart": op_multipart,
    "read_cookie": op_read_cookie,
}


def run(pool, msg):
    op = msg.get("op")
    rid = msg.get("id")

    def work():
        try:
            res = OPS[op](msg)
        except Exception as e:
            res = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        res["id"] = rid
        emit(res)

    pool.submit(work)


def main():
    pool = ThreadPoolExecutor(max_workers=6)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        op = msg.get("op")
        if op == "creds":
            creds["token"] = msg.get("token") or ""
            creds["cookie"] = msg.get("cookie") or ""
        elif op == "ws_open":
            threading.Thread(target=op_ws_open, args=(msg,), daemon=True).start()
        elif op == "ws_send":
            op_ws_send(msg)
        elif op == "ws_close":
            op_ws_close(msg)
        elif op in OPS:
            run(pool, msg)
    op_ws_close({})
    os._exit(0)


if __name__ == "__main__":
    main()
