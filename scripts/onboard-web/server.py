#!/usr/bin/env python3
"""One-shot, loopback-only web front end for the existing terminal onboarding wizard."""
import argparse
import html
import json
import os
import pty
import re
import secrets
import select
import signal
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHOICES = ROOT / "system/skills/onboard/choices.json"
WIZARD = ROOT / "scripts/onboard-wizard.sh"
FIELDS = ("language", "artifactLanguage", "verbosity", "askFirst", "autonomy",
          "design", "decision", "channel", "updateMode", "os", "editor", "languages", "hosting")
QUESTIONS = {
    "language": "Conversation language", "artifactLanguage": "Language for code and docs",
    "verbosity": "Answer length", "askFirst": "When to ask", "autonomy": "Autonomy",
    "design": "Theme", "decision": "Decisions", "channel": "Release channel",
    "updateMode": "Update behaviour", "os": "Primary operating system",
    "editor": "Editor", "languages": "Languages and frameworks", "hosting": "Code hosting",
}


def available(field, root):
    opts = field["options"]
    # Match onboard-wizard.sh's insider predicate exactly: a public origin
    # cannot offer edge even if this program was launched from a worktree.
    try:
        url = subprocess.run(["git", "-C", str(root), "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        url = ""
    insider = bool(url) and not any(h in url for h in ("github.com", "gitlab.com", "codeberg.org"))
    out = [o for o in opts if o.get("requires") != "insider" or insider]
    return out or opts


def answer_lines(payload, choices, root):
    """Validate user input, then encode the wizard's plain-TTY *full* flow."""
    if not isinstance(payload, dict) or set(payload) != set(FIELDS):
        raise ValueError("Missing or unexpected answers")
    fields = choices["fields"]
    lines = [str(next(i + 1 for i, o in enumerate(choices["profiles"]["options"])
                      if o.get("full")))]  # no profile -> full flow
    order = FIELDS[:9] + FIELDS[9:]
    for name in order:
        field = fields[name]
        opts = available(field, root) if field["type"] == "choice" else field["options"]
        val = payload[name]
        if name == "artifactLanguage" and payload["language"] == "English":
            if val != "english-artifacts":
                raise ValueError("Artifact language must be English when conversation is English")
            continue
        if field["type"] == "choice":
            if not isinstance(val, str) or len(val) > 160 or "\n" in val or "\r" in val:
                raise ValueError("Invalid choice")
            idx = next((i for i, o in enumerate(opts) if o["value"] == val), None)
            if idx is not None and not opts[idx].get("custom"):
                lines.append(str(idx + 1))
            elif any(o.get("custom") for o in opts) and val.strip():
                lines.extend([str(next(i + 1 for i, o in enumerate(opts) if o.get("custom"))), val])
            else:
                raise ValueError("Choice is not offered")
        else:
            if not isinstance(val, list) or len(val) > 20 or not val:
                raise ValueError("Select at least one option")
            allowed = {o["value"] for o in opts if not o.get("custom")}
            if any(not isinstance(v, str) or not v.strip() or len(v) > 80 or
                   any(c in v for c in "\r\n,") for v in val):
                raise ValueError("Invalid multi-value")
            # Plain wizard accepts labels as typed answers, including custom
            # labels. Do not use numeric indices here: they vary with options.
            lines.append(", ".join(dict.fromkeys(val)))
    return lines


def run_wizard(root, lines, timeout=45):
    """Drive the *real* wizard through its controlling TTY, not a second writer."""
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, VAULT=str(root), AB_WIZARD_PLAIN="1",
                   AB_CHOICES_JSON=str(root / "system/skills/onboard/choices.json"), TERM="dumb")
        os.execvpe("bash", ["bash", str(root / "scripts/onboard-wizard.sh")], env)
    deadline = time.monotonic() + timeout
    prompt = re.compile(rb"(?:choice \[\d+\]|numbers, comma-separated[^\r\n]*\[\d+\]|your own): $")
    try:
        # Wait for each prompt before sending its answer. This avoids TTY
        # canonical-buffer limits and ensures a failed wizard never receives
        # unattended input intended for a later question.
        pending = b""
        for answer in lines:
            while not prompt.search(pending.split(b"\n")[-1]):
                if time.monotonic() >= deadline:
                    raise TimeoutError("wizard did not prompt")
                ready, _, _ = select.select([fd], [], [], min(1, max(0, deadline - time.monotonic())))
                if ready:
                    try:
                        chunk = os.read(fd, 65536)
                        pending += chunk
                    except OSError as exc:
                        raise RuntimeError("wizard ended early") from exc
                    if len(pending) > 262144:
                        pending = pending[-8192:]
            os.write(fd, answer.encode("utf-8") + b"\n")
            pending = b""
        while time.monotonic() < deadline:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                return os.waitstatus_to_exitcode(status)
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                try:
                    os.read(fd, 65536)
                except OSError:
                    pass
        raise TimeoutError("wizard timed out")
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        os.close(fd)


def page(choices, token, root):
    ui = Path(__file__).parent
    steps = (("Your preferences", "Choose how agentBrain speaks and works with you.", FIELDS[:7]),
             ("Updates", "Set the release channel and how updates are applied.", FIELDS[7:9]),
             ("Your tools", "Help agentBrain recognise your workspace.", FIELDS[9:]))
    parts = ["<!doctype html><html lang='en' data-mode='auto' data-palette='frontmatters'><head><meta charset='utf-8'>",
             "<meta name='viewport' content='width=device-width,initial-scale=1'>",
             "<title>Set up agentBrain</title><style>",
             (ui / 'theme.css').read_text(), (ui / 'ui.css').read_text(), "</style></head><body>",
             "<div class='shell'><header class='topbar'><div class='wordmark'>agent<span>Brain</span></div>",
             "<details class='settings' id='settings'><summary aria-label='Appearance settings'><svg viewBox='0 0 24 24' aria-hidden='true'><path d='M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z'/></svg>Appearance</summary>",
             "<div class='settings-panel'><label for='mode'>Mode<select id='mode'><option value='auto'>System</option><option value='light'>Light</option><option value='dark'>Dark</option></select></label>",
             "<label for='palette'>Palette<select id='palette'><option value='frontmatters'>Frontmatters orange</option><option value='ocean'>Ocean blue</option><option value='forest'>Forest green</option><option value='mono'>Monochrome</option><option value='custom'>Custom</option></select></label>",
             "<label for='custom-accent' id='accent-setting'>Custom accent<input id='custom-accent' type='color' value='#dd4b12'></label></div></details></header>",
             "<main><div class='intro'><h1>Make agentBrain yours.</h1><p>Choose the defaults that suit your work. You can change them later.</p>",
             "<div class='proof'><span><strong>Local setup.</strong> No account or cloud connection.</span><span>The existing terminal wizard saves your answers.</span></div></div>",
             "<div class='form-layout'><ol class='steps' aria-label='Setup progress'>" + "".join(
                 "<li" + (" class='current' aria-current='step'" if i == 0 else "") + "><span>" + str(i + 1).zfill(2) + "</span>" + html.escape(step[0]) + "</li>"
                 for i, step in enumerate(steps)) + "</ol>",
             "<noscript><p>This setup needs JavaScript in your local browser. No answers have been saved.</p><style>#onboard{display:none}</style></noscript>",
             "<form id='onboard' novalidate><input type='hidden' id='token' value='" + html.escape(token, quote=True) + "'>"]
    for i, (title, description, names) in enumerate(steps):
        parts.append("<section class='step' id='step-" + str(i) + "' aria-labelledby='step-title-" + str(i) + "'><div class='section-head'><h2 id='step-title-" + str(i) + "' tabindex='-1'>" + html.escape(title) + "</h2><p>" + html.escape(description) + "</p></div>")
        for name in names:
            f = choices["fields"][name]
            parts.append("<fieldset id='group-" + name + "'><legend>" + html.escape(QUESTIONS[name]) + "</legend>")
            if f["type"] == "choice":
                parts.append("<label for='" + name + "'>Choose one</label><select id='" + name + "'>")
                for o in available(f, root):
                    if o.get("custom"):
                        continue
                    parts.append("<option value='" + html.escape(o["value"], quote=True) + "'>" + html.escape(o["value"] + " - " + o.get("desc", "")) + "</option>")
                if any(o.get("custom") for o in f["options"]):
                    parts.append("<option value='__custom__'>Other (type below)</option>")
                parts.append("</select><input type='text' id='custom-" + name + "' class='hidden custom' placeholder='Your own answer' aria-label='Your own " + html.escape(QUESTIONS[name]) + "'>")
            else:
                for o in f["options"]:
                    if o.get("custom"):
                        continue
                    parts.append("<label class='check'><input type='checkbox' name='" + name + "' value='" + html.escape(o["value"], quote=True) + "'><span>" + html.escape(o["value"]) + "<small>" + html.escape(o.get("desc", "")) + "</small></span></label>")
                parts.append("<label for='custom-" + name + "'>Other (optional, comma separated)</label><input type='text' id='custom-" + name + "'>")
            parts.append("</fieldset>")
        parts.append("</section>")
    parts += ["<div class='actions'><button type='button' id='previous'>Back</button><button type='button' id='next' class='primary'>Continue</button><button type='submit' id='save' class='primary'>Save answers</button></div>",
              "<p role='status' id='status' class='status' aria-live='polite'></p></form></div></main></div>",
              "<script>const fields=" + json.dumps(FIELDS) + ";const types=" + json.dumps({n: choices['fields'][n]['type'] for n in FIELDS}) + ";", (ui / 'ui.js').read_text(), "</script></body></html>"]
    return "".join(parts).encode("utf-8")


def serve(root, open_browser=True):
    choices = json.loads((root / "system/skills/onboard/choices.json").read_text())
    token = secrets.token_urlsafe(32)
    class Handler(BaseHTTPRequestHandler):
        def allowed_host(self):
            return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

        def do_GET(self):
            if not self.allowed_host():
                self.send_error(403)
                return
            if self.path != "/":
                self.send_error(404)
                return
            body = page(choices, token, root)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            origin = self.headers.get("Origin", "")
            if (not self.allowed_host() or self.path != "/submit" or self.headers.get("X-Onboard-Token") != token or
                self.headers.get("Content-Type", "").split(";")[0] != "application/json" or
                (origin and origin != f"http://127.0.0.1:{self.server.server_port}")):
                self.send_error(403)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size < 1 or size > 16384:
                    raise ValueError("Invalid form size")
                payload = json.loads(self.rfile.read(size))
                lines = answer_lines(payload, choices, root)
                if run_wizard(root, lines) != 0:
                    raise RuntimeError("Terminal wizard failed")
            except (ValueError, RuntimeError, TimeoutError) as exc:
                self.send_error(400, str(exc))
                return
            body = b"Saved by the terminal wizard. You can close this tab."
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.server.done = True

        def log_message(self, format, *args):
            pass  # Never log personal answers or launch token.

    server = HTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = 0.3
    server.done = False
    url = f"http://127.0.0.1:{server.server_port}/"
    print(url, flush=True)
    if open_browser:
        import webbrowser
        webbrowser.open(url)
    try:
        while not server.done:
            server.handle_request()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="checkout with wizard and choices")
    parser.add_argument("--no-browser", action="store_true", help="print the URL without opening a browser")
    args = parser.parse_args()
    serve(args.root.resolve(), not args.no_browser)
