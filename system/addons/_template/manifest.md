---
id: your-addon-id
name: Your Addon Name
version: 0.1.0
install: bash system/addons/your-addon-id/install.sh
command: your-command
privacy: local
install_method: self
# Attribution (required, lowercase handle). `addons.sh new` seeds this with the vault
# maintainer from brain.json; change it when adopting someone else's addon and add
# `upstream: <url>` for provenance.
author: your-handle
# Optional SPDX license id (e.g. Apache-2.0, MIT, PolyForm-Noncommercial-1.0.0).
# Absent = the framework default (Apache-2.0). Set it when adopting an addon under
# a different license.
# license: Apache-2.0
# Optional addon dependencies (space/comma-separated ids). Each must be a known
# addon; check-addons enforces that. Runtime is soft — `addons.sh check` warns when
# a required addon isn't enabled, it never blocks install. (Distinct from the nested
# onboard.requires below, which gates the onboard offer on a platform capability.)
# requires: event-bus
# Optional external runtime prerequisites (space/comma-separated capability
# tokens: ollama, uv, devbox, …). Each must be a known platform_has capability.
# check-addons validates; addons.sh check warns when missing; enable offers to
# install (opt-in, package-manager auto-run; services/pipe-to-shell shown only).
# runtime_requires: ollama
# Optional agentBrain shorthand for this addon (lowercase). While the addon is
# enabled, the shorthand addon surfaces it as a term (`<short>` -> this addon's
# name) in the shared glossary. Core (ab, moc) and the user's local layer win.
# shorthand: your-short
# Optional: a test suite run from the add-on dir by `addons.sh test` when its
# runtime (first word) is on PATH. e.g. `bun test` or
# `bash tests/test-install.sh && bash tests/test-build.sh`. Remove if unused.
# test: bun test
# Optional: an interactive first-time setup step, offered after install and
# runnable later via `addons.sh onboard <id>`. The run script must be idempotent
# (detect-before-ask). `requires:` (optional) gates the offer via platform_has.
# onboard:
#   run: bash system/addons/your-addon-id/onboard.sh
#   requires: <platform_has-capability>
#   prompt: "Set up your-addon-id now?"
support:
  pi: full
  claude: unknown
  copilot: unknown
  codex: unknown
outputs:
  - local/your-addon-id/*.json
---

# Your Addon Name

Replace every placeholder before registering the addon.
