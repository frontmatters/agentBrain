#!/usr/bin/env python3
"""serve-lan-handler.py — serve the LAN installer, rebuilt when main has moved.

`python3 -m http.server` would serve whatever was on disk when the server
started. That is how a long-running LAN server ends up handing out a tree three
weeks old while reporting nothing: it has no reason to notice, and neither does
the person who started it.

So the check happens per request, and it is cheap: compare main's SHA against
the one recorded at the last build. Only a real move triggers a rebuild, so a
poll costs one `git rev-parse` rather than a 4 MB bundle.

The build itself stays in serve-lan.sh (--build-only). One implementation, in
the language the rest of the installer is written in.

Usage: serve-lan-handler.py <serve-dir> <port> <repo-root> <serve-lan.sh>
"""
import http.server
import pathlib
import subprocess
import sys
import threading

SRV, PORT, ROOT, SCRIPT = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
STAMP = pathlib.Path(SRV) / ".built-from"
WATCHED = ("/agentBrain.bundle", "/install.sh")

# One rebuild at a time. Two clients arriving together would otherwise both
# start a build, and the second would rename over the first mid-write.
_lock = threading.Lock()


def head_sha():
    """main's current SHA, or empty when git cannot answer."""
    try:
        r = subprocess.run(["git", "-C", ROOT, "rev-parse", "main"],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def built_from():
    try:
        return STAMP.read_text().strip()
    except OSError:
        return ""


def refresh_if_moved():
    """Rebuild when main has moved. Serving a stale tree is worse than a slow
    request, but a failed rebuild is worse than either: on failure the previous
    files stay in place and are served unchanged."""
    now = head_sha()
    if not now or now == built_from():
        return
    with _lock:
        if head_sha() == built_from():      # another thread got there first
            return
        try:
            subprocess.run(["bash", SCRIPT, "--build-only"],
                           check=True, timeout=180,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"rebuilt: main at {now[:9]}", flush=True)
        except (OSError, subprocess.SubprocessError) as e:
            print(f"rebuild failed ({e}); serving the previous bundle", flush=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=SRV, **kw)

    def do_GET(self):
        if self.path in WATCHED:
            refresh_if_moved()
        super().do_GET()

    def do_HEAD(self):
        if self.path in WATCHED:
            refresh_if_moved()
        super().do_HEAD()

    def log_message(self, fmt, *args):
        # The default logs every request to stderr; launchd would collect them
        # forever. Keep the rebuild lines, drop the access log.
        pass


if __name__ == "__main__":
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"serving {SRV} on :{PORT}, rebuilding when main moves", flush=True)
    srv.serve_forever()
