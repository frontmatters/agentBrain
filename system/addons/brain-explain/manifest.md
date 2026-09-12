---
id: brain-explain
name: brain-explain
version: 0.1.2
author: frontmatters
install: bash system/addons/brain-explain/install.sh
# On by default in a fresh install; the user can untick it.
default_enabled: true
privacy: local
install_method: self
test: bash tests/test-brain-explain.sh
onboard:
  run: bash system/addons/brain-explain/onboard.sh
  prompt: "Geen persoonlijk theme gevonden. Beschrijf je stijl, dan maak ik er één. Of kies een meegeleverd theme (editorial, clean-flat, whiteboard)."
support:
  pi: full
  claude: full
  abh: unknown
outputs:
  - vault/explainers/**/*.html
---

# brain-explain

Render markdown explainers into themed, self-contained HTML. Markdown is the
source of truth; HTML is regenerable visual sugar. See README.md.
