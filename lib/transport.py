#!/usr/bin/env python3
"""Network transport for the Slack plugin: nothing but bytes on the wire.

The QML side owns every decision; this process only does what QML cannot:
HTTPS with the session cookie (QML's XMLHttpRequest drops `Cookie`), a
WebSocket it can also write to, files to disk, the sign-in window's cookie
database and the system keyring. One process per workspace, spoken to in
JSON lines:

  stdin   {"id": 7, "op": "call", "method": "auth.test", "params": {...}}
  stdout  {"id": 7, "ok": true, "status": 200, "body": {...}}

Ops: creds, call, download, video_frame, stream, post_file, multipart, read_cookie, write_private,
secret_store, secret_lookup, secret_clear, ws_open, ws_send, ws_close. Socket
traffic comes back unprompted as
{"ws": "open"}, {"ws": "msg", "data": {...}}, {"ws": "closed", "reason": ...}.
Credentials only ever arrive on stdin and only ever go to slack.com hosts.
"""

import base64
import gzip
import hmac
import json
import os
import random
import secrets
import shutil
import socket
import sqlite3
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import zlib
from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPSConnection, HTTPException
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def chrome_ua():
    """A current desktop Chrome's user agent, reduced as Chrome sends it: the
    major from the date (140 shipped on 2025-09-02, 1756771200 UTC, then one
    every 4 weeks), one less so it's never one that isn't out yet. The same
    sum as lib/Util.js chromeUa."""
    major = max(140, 140 + int((time.time() - 1756771200) // (28 * 86400)) - 1)
    return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%d.0.0.0 Safari/537.36" % major


# Handed in by Transport.qml (lib/Util.js chromeUa); one line of plain text.
UA = os.environ.get("OMASLACK_UA", "").strip()
if not UA or not UA.isascii() or not UA.isprintable():
    UA = chrome_ua()
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


def request(method, url, body=None, headers=None, stream_to=None, progress=None, limit=0):
    """One request on this thread's kept-alive connection; a stale one is
    reopened once. Returns (status, headers, bytes or None). `progress`
    (with `stream_to`): called with (bytes so far, total or 0) as it goes.
    `limit`: at most that much of a body is read (the rest is dropped with
    the connection), for a Range a server may answer with the whole file."""
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
                # A retry starts the file over, not after what came before.
                stream_to.seek(0)
                stream_to.truncate()
                enc = rh.get("content-encoding", "")
                if enc:
                    data = decode(r.read(), enc)
                    stream_to.write(data)
                elif progress:
                    try:
                        total = int(rh.get("content-length") or 0)
                    except ValueError:
                        total = 0
                    done = 0
                    while True:
                        chunk = r.read(1 << 16)
                        if not chunk:
                            break
                        stream_to.write(chunk)
                        done += len(chunk)
                        progress(done, total)
                else:
                    shutil.copyfileobj(r, stream_to, 1 << 16)
                return r.status, rh, None
            if limit and stream_to is None:
                data = r.read(limit)
                if not r.isclosed():
                    drop_conn(host)
                return r.status, rh, data
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
    url = "https://%s/api/%s" % (API_HOST, method)
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
    # `progress`: {"id", "progress": bytes, "total": bytes or 0} lines
    # before the answer, a few a second at most.
    report = None
    if msg.get("progress"):
        last = [0.0]

        def report(done, total):
            now = time.monotonic()
            if now - last[0] >= 0.2:
                last[0] = now
                emit({"id": msg.get("id"), "progress": done, "total": total})
    for _ in range(6):
        u = urllib.parse.urlsplit(url)
        headers = auth_headers() if is_slack(u.hostname) else {}
        tmp = dest + ".part"
        try:
            with open(tmp, "wb") as f:
                status, rh, data = request("GET", url, None, headers, stream_to=f, progress=report)
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
        # `no_clobber` (a save to Downloads): a file already there stays, and
        # this one becomes "name (1).ext", "name (2).ext"…
        if msg.get("no_clobber"):
            dest = free_name(dest)
        os.replace(tmp, dest)
        return {"ok": True, "path": dest, "mime": mime}
    return {"ok": False, "error": "redirects"}


# A video's cover: a frame from its first second, blurred, without the whole
# file. Its start comes by Range, and an mp4's index (the `moov` box) too
# when it sits after the media; both go into a sparse file of the video's
# size, which ffmpeg reads as if it were all there.
COVER_HEAD = 8 << 20
COVER_TAIL_MAX = 24 << 20


def get_range(url, start, end):
    """Bytes start..end (inclusive; end None: to the file's end) and the
    file's total size, following redirects."""
    want = (end - start + 1) if end is not None else COVER_TAIL_MAX
    for _ in range(6):
        u = urllib.parse.urlsplit(url)
        headers = auth_headers() if is_slack(u.hostname) else {}
        headers["Range"] = "bytes=%d-%s" % (start, "" if end is None else end)
        headers["Accept-Encoding"] = "identity"
        status, rh, data = request("GET", url, None, headers, limit=want + 1)
        if status in (301, 302, 303, 307, 308) and rh.get("location"):
            url = urllib.parse.urljoin(url, rh["location"])
            continue
        if status != 206:
            raise OSError("no range (http %d)" % status)
        total = int(rh.get("content-range", "").rpartition("/")[2] or 0)
        return data[:want], total
    raise OSError("redirects")


def moov_after(head, total):
    """Where an mp4's boxes past `head` begin when its `moov` isn't in it,
    else None (found, or not an mp4)."""
    if head[4:8] != b"ftyp":
        return None
    off = 0
    while off + 8 <= len(head):
        size, kind = struct.unpack(">I4s", head[off:off + 8])
        if size == 1 and off + 16 <= len(head):
            size = struct.unpack(">Q", head[off + 8:off + 16])[0]
        elif size == 0:
            size = total - off
        if kind == b"moov" or size < 8:
            return None
        off += size
    return off if off < total else None


def op_video_frame(msg):
    dest = msg["dest"]
    try:
        if os.path.getsize(dest) > 0:
            os.utime(dest)
            return {"ok": True, "path": dest, "cached": True}
    except OSError:
        pass
    if not shutil.which("ffmpeg"):
        return {"ok": False, "error": "no ffmpeg"}
    url = msg["url"]
    head, total = get_range(url, 0, COVER_HEAD - 1)
    tail_at = moov_after(head, total) if total > len(head) else None
    tail = b""
    if tail_at is not None:
        if total - tail_at > COVER_TAIL_MAX:
            return {"ok": False, "error": "index too far"}
        tail, _ = get_range(url, tail_at, None)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    fd, sparse = tempfile.mkstemp(dir=os.path.dirname(dest), suffix=".part")
    try:
        with os.fdopen(fd, "wb") as f:
            f.truncate(max(total, len(head)))
            f.write(head)
            if tail:
                f.seek(tail_at)
                f.write(tail)
        tmp = dest + ".part.jpg"
        # A second in (the first frames are often black), else the start.
        for at in (msg.get("at", 1.0), 0):
            r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-ss", str(at), "-i", sparse, "-frames:v", "1",
                                "-vf", "scale=640:-2,gblur=sigma=%s" % msg.get("blur", 6), "-q:v", "4", tmp],
                               capture_output=True, timeout=40)
            if r.returncode == 0 and os.path.exists(tmp) and os.path.getsize(tmp) > 0:
                os.replace(tmp, dest)
                return {"ok": True, "path": dest}
        return {"ok": False, "error": "no frame"}
    finally:
        for p in (sparse, dest + ".part.jpg"):
            try:
                os.unlink(p)
            except OSError:
                pass


# Videos and sounds played as they come: a server on 127.0.0.1 (a port of
# its own, a random secret in every path) that hands the player what it asks
# for, Range and all, fetched from Slack with the session. The player gets
# http://127.0.0.1:port/<secret>/<n>, never the session.
stream = {"server": None, "base": "", "token": "", "urls": {}, "ids": {}}
stream_lock = threading.Lock()
STREAM_HEADERS = ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag")


class StreamHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_HEAD(self):
        self.relay(False)

    def do_GET(self):
        self.relay(True)

    def relay(self, body):
        parts = self.path.split("/")
        url = stream["urls"].get(parts[2]) if len(parts) == 3 and hmac.compare_digest(parts[1], stream["token"]) else None
        if not url:
            self.send_error(404)
            return
        rng = self.headers.get("Range")
        c = r = None
        for _ in range(6):
            u = urllib.parse.urlsplit(url)
            headers = auth_headers() if is_slack(u.hostname) else {}
            headers["User-Agent"] = UA
            headers["Accept-Encoding"] = "identity"
            if rng:
                headers["Range"] = rng
            c = HTTPSConnection(u.hostname, u.port or 443, timeout=40, context=ctx)
            try:
                c.request("GET" if body else "HEAD", (u.path or "/") + ("?" + u.query if u.query else ""), headers=headers)
                r = c.getresponse()
            except (HTTPException, OSError):
                c.close()
                self.send_error(502)
                return
            if r.status in (301, 302, 303, 307, 308) and r.getheader("location"):
                url = urllib.parse.urljoin(url, r.getheader("location"))
                c.close()
                continue
            break
        else:
            self.send_error(502)
            return
        try:
            self.send_response(r.status)
            for h in STREAM_HEADERS:
                v = r.getheader(h)
                if v:
                    self.send_header(h, v)
            if not r.getheader("Content-Length"):
                self.send_header("Connection", "close")
                self.close_connection = True
            self.end_headers()
            if body:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except OSError:
            # The player went elsewhere (a seek) or away.
            self.close_connection = True
        finally:
            c.close()


def op_stream(msg):
    url = msg["url"]
    with stream_lock:
        if not stream["server"]:
            srv = ThreadingHTTPServer(("127.0.0.1", 0), StreamHandler)
            srv.daemon_threads = True
            stream["server"] = srv
            stream["token"] = secrets.token_urlsafe(24)
            stream["base"] = "http://127.0.0.1:%d/%s/" % (srv.server_address[1], stream["token"])
            threading.Thread(target=srv.serve_forever, daemon=True).start()
        n = stream["ids"].get(url)
        if n is None:
            n = stream["ids"][url] = str(len(stream["ids"]) + 1)
            stream["urls"][n] = url
    return {"ok": True, "url": stream["base"] + n}


def free_name(dest):
    """`dest`, or the first "name (n).ext" not taken, claimed on the spot
    (O_EXCL) so two saves never pick the same one."""
    stem, ext = os.path.splitext(dest)
    n = 0
    while True:
        cand = dest if n == 0 else "%s (%d)%s" % (stem, n, ext)
        try:
            os.close(os.open(cand, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644))
            return cand
        except FileExistsError:
            n += 1


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


def xdg_dir(var, fallback):
    return os.path.join(os.environ.get(var) or os.path.join(os.path.expanduser("~"), fallback), "omaslack")


def run_dir():
    """The session's runtime dir (a tmpfs, gone at logout), or "" without
    one: Service.qml's runDir."""
    base = os.environ.get("XDG_RUNTIME_DIR")
    return os.path.join(base, "omaslack") if base else ""


COOKIE_SQL = ("select value, host_key from cookies where name = 'd' and (host_key = '.slack.com' or host_key like '%.slack.com'"
              " or host_key = 'slack.com') order by length(value) desc")


def cookie_rows(db, readonly):
    if readonly:
        con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(db), uri=True)
    else:
        con = sqlite3.connect(db)
    try:
        return con.execute(COOKIE_SQL).fetchall()
    finally:
        con.close()


def op_read_cookie(msg):
    """The `d` cookie the sign-in window's browser profile saved (HttpOnly:
    the page itself can never read it). That profile is the plugin's own
    (login/Login.qml, under $XDG_RUNTIME_DIR/omaslack/webview, else
    $XDG_DATA_HOME/omaslack/webview), never one of the user's browsers: any
    other path is refused."""
    base = os.path.realpath(os.path.join(run_dir() or xdg_dir("XDG_DATA_HOME", ".local/share"), "webview"))
    db = os.path.realpath(msg.get("db") or base)
    if db == base or os.path.commonpath([base, db]) != base:
        return {"ok": False, "error": "not the sign-in profile"}
    if not os.path.isfile(db):
        return {"ok": False, "error": "no cookie database"}
    try:
        rows = cookie_rows(db, True)
    except sqlite3.Error:
        rows = None
    if rows is None:
        # Read-only refused (a journal to roll back, a lock): a copy in a
        # private (0700) temp dir, gone as soon as it's read.
        tmpdir = tempfile.mkdtemp(prefix="omaslack-")
        try:
            copy = os.path.join(tmpdir, "Cookies")
            shutil.copyfile(db, copy)
            if os.path.exists(db + "-journal"):
                shutil.copyfile(db + "-journal", copy + "-journal")
            rows = cookie_rows(copy, False)
        except Exception as e:
            return {"ok": False, "error": str(e)}
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
    for value, host in rows:
        if value:
            return {"ok": True, "cookie": value}
    return {"ok": False, "error": "no d cookie"}


def op_write_private(msg):
    """A file of the plugin's config dir (accounts.json: the sessions), the
    user's alone from its first byte: a 0600 temp file beside it (mkstemp),
    synced, then renamed over it in one step. The dir is made 0700."""
    name = msg.get("name") or ""
    if not name or name != os.path.basename(name) or name.startswith("."):
        return {"ok": False, "error": "bad name"}
    d = xdg_dir("XDG_CONFIG_HOME", ".config")
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    fd, tmp = tempfile.mkstemp(prefix="." + name + ".", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(msg.get("text") or "")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, os.path.join(d, name))
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return {"ok": True}


# A locked keyring asks for its password first.
SECRET_WAIT = 120


def secret_tool(verb, team, extra=(), data=b""):
    """secret-tool (libsecret) on the session's Secret Service, for one
    workspace's entry (application=omaslack team=<id>). The secret only
    goes through its stdin and stdout, never its arguments."""
    if not team or not team.isascii() or not team.isalnum():
        raise ValueError("bad team")
    return subprocess.run(["secret-tool", verb] + list(extra) + ["application", "omaslack", "team", team],
                          input=data, capture_output=True, timeout=SECRET_WAIT)


def tool_error(p, fallback):
    return p.stderr.decode("utf-8", "replace").strip() or fallback


def op_secret_store(msg):
    label = "--label=" + (msg.get("label") or "Omaslack")
    p = secret_tool("store", msg.get("team") or "", [label], (msg.get("secret") or "").encode("utf-8"))
    if p.returncode != 0:
        return {"ok": False, "error": tool_error(p, "secret-tool store failed")}
    return {"ok": True}


def op_secret_lookup(msg):
    p = secret_tool("lookup", msg.get("team") or "")
    secret = p.stdout.decode("utf-8", "replace")
    if p.returncode != 0 or not secret:
        return {"ok": False, "error": tool_error(p, "not in the keyring")}
    return {"ok": True, "secret": secret}


def op_secret_clear(msg):
    p = secret_tool("clear", msg.get("team") or "")
    return {"ok": p.returncode == 0}


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
    # The token rides in the URL: only ever to a Slack host.
    u = urllib.parse.urlsplit(msg.get("url") or "")
    if u.scheme != "wss" or not is_slack(u.hostname):
        emit({"ws": "closed", "reason": "connect: not a slack.com socket"})
        return None
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
    "video_frame": op_video_frame,
    "stream": op_stream,
    "post_file": op_post_file,
    "multipart": op_multipart,
    "read_cookie": op_read_cookie,
    "secret_store": op_secret_store,
    "secret_lookup": op_secret_lookup,
    "secret_clear": op_secret_clear,
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
        elif op == "write_private":
            # Here, in order: two saves in a row land in that order.
            try:
                res = op_write_private(msg)
            except Exception as e:
                res = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
            res["id"] = msg.get("id")
            emit(res)
        elif op in OPS:
            run(pool, msg)
    op_ws_close({})
    os._exit(0)


if __name__ == "__main__":
    main()
