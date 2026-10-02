---
date: 2026-09-29
type: reference
tags: [onboarding, web]
id: 45ba70af-0b88-56d6-9fed-cc058e32cadc
---

# Local web onboarding

A model-free browser front end for the fixed-choice intake in
`system/skills/onboard/choices.json`. It deliberately delegates all writes to
`scripts/onboard-wizard.sh`: there is no second preference-file formatter.

```sh
python3 scripts/onboard-web/server.py
```

The command prints a random loopback URL and opens it in the default browser.
It uses a free port on `127.0.0.1`, stops after a successful submission or
Ctrl-C, and requires only Python 3 and the existing wizard's Bash dependencies.
For headless testing, use `--no-browser`; `--root` selects a throwaway checkout.
No third-party assets or requests are embedded in the page. The browser sends
its choices to the local server; the wizard runs in plain terminal mode on a
private pseudo-terminal and makes the same writes as an interactive terminal.
The server requires a per-launch token and rejects non-loopback origins.

The form uses three short steps, keyboard-focusable controls, a polite status
region, and persistent System/Light/Dark plus preset/custom palette settings.
**The appearance is replaceable:** `theme.css` owns the flat
palette, typography and corner tokens; `ui.css` owns structure and responsive
layout; `ui.js` owns progression/theme preference but never writes answers.
Replace the skin without editing the wizard, choices, or server-side contract.
The theme names its preferred fonts but does not bundle them: a machine without
them installed renders a fallback font.

The page uses the wizard's **no profile / full flow**. Profile-based
shortcuts and automatic device/editor detection in the page are not implemented;
users choose every field explicitly. There is no `brain onboard --web`
command; start the page with the command above.

In a source checkout, `scripts/tests/test-onboard-web.sh` validates this: it builds two isolated
throwaway installs, submits the same answers by terminal and HTTP, compares
all output bytes, and includes a deliberately different answer as a negative
control. It never touches the personal vault.
