---
id: your-addon-id
name: Your Addon Name
version: 0.1.0
install: bash system/addons/your-addon-id/install.sh
command: your-command
privacy: local
install_method: self
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
