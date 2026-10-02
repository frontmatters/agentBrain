---
date: 2026-09-30
type: system
tags: [meta, addons, kind]
id: 99b1c915-dee3-530f-9575-8268698faf3e
---

# Add-on kinds: classification

Every manifest carries a `kind:` (see "Add-on kinds" in `README.md` for the fields
each kind requires; `scripts/checks/check-addons.sh` enforces them). This table
explains the classification. The kind comes
from the add-on's files, not from its name.

Rule of thumb applied where two kinds could fit: a third-party **program** the
add-on installs or calls (CLI, proxy, app) makes it an `adapter`; third-party
**content** (skills, rulesets, a copied script) that *is* the add-on makes it
`vendored`. Code in this directory, written for agentBrain, with no separate
repository or factory, is `framework`.

The manifest and the add-on's own public files are the source of truth; counts may change as the registry grows.

| id | kind | reason | evidence |
| --- | --- | --- | --- |
| agent-browser | adapter | Registry entry that installs Vercel Labs' standalone browser CLI from npm; no local code. Validated against 0.27.0. | `agent-browser/README.md` (Upstream, Version pinning) |
| agentbrain-imsg | adapter | `bin/agentbrain-imsg` is a send-guard that `exec`s the standalone `imsg` tool, which has its own (legacy) factory. | `agentbrain-imsg/bin/agentbrain-imsg`; `agentbrain-imsg/README.md` |
| agentbrain-mcp | framework | MCP server over the vault, written for agentBrain (`src/`), own `bun test`. | `agentbrain-mcp/src/`, `agentbrain-mcp/package.json` |
| agentbrain-pigeonpipe | adapter | README: "adapter around the standalone `pigeonpipe` tool"; pigeonpipe has its own factory. | `agentbrain-pigeonpipe/README.md` |
| anthropic-skills | vendored | Pointer to Anthropic's skill collection; the content is Anthropic's, installed from upstream. | `anthropic-skills/README.md` (Upstream & license) |
| bloop | framework | In-house agentBrain workflow skill (SKILL.md only), author frontmatters. No test suite exists yet. | `bloop/SKILL.md`, `bloop/README.md` |
| brain-explain | framework | agentBrain renderer for vault notes (`bin/`, `lib/`), own tests. | `brain-explain/lib/`, `brain-explain/tests/` |
| brain-infographic | framework | agentBrain renderer/scoring loop (`bin/`, `lib/`, `templates/`), own tests. | `brain-infographic/lib/`, `brain-infographic/tests/test.sh` |
| chatgpt-import | framework | Contributed by its author (ultimate_tagger) and maintained only here: there is no upstream repository. | `chatgpt-import/README.md` (credits), `chatgpt-import/tests/selftest.py` |
| claude-memory-redirect | framework | Hooks and scripts that route Claude memory into the vault; agentBrain-only. | `claude-memory-redirect/*.sh`, `tests/test-redirect.sh` |
| event-bus | framework | agentBrain's filesystem pub/sub transport, specified in `SPEC*.md`. | `event-bus/SPEC.md`, `event-bus/tests/` |
| extract-learnings | framework | Pre-compact hook plus `core.ts` that writes vault learnings. | `extract-learnings/core.ts`, `tests/core.test.ts` |
| git-email-guard | framework | Pre-commit hook shipped and installed by agentBrain. | `git-email-guard/hooks/`, `tests/` |
| goal | framework | Goal logic and CLI for agentBrain agents; consumed by the Pi extension in this repo. | `goal/lib/core.ts`, `goal/README.md` (Layout) |
| graphify | adapter | README: "wraps the upstream `graphifyy` PyPI package with an agentBrain-aware CLI"; upstream safishamsi/graphify. | `graphify/README.md`, `graphify/install.sh` |
| hallmark | vendored | Vendored copy of nutlope/hallmark v1.1.0 (MIT). | `hallmark/CHANGELOG.md` [0.1.0], `hallmark/manifest.md` |
| headroom-proxy | adapter | Wraps chopratejas/headroom, a standalone compression proxy; install pins `headroom>=0.22,<0.30`. | `headroom-proxy/README.md`, `headroom-proxy/install.sh:30` |
| impeccable | vendored | pbakaus/impeccable skill, vendored by hand from the skill-v4.0.4 tag (Apache-2.0). | `impeccable/CHANGELOG.md`, `impeccable/manifest.md` (`skill_version`) |
| incognito | framework | Incognito guard hooks for agentBrain sessions. | `incognito/*.sh`, `tests/test-incognito.sh` |
| llm-config | framework | Implements agentBrain's local-first LLM resolution from `system/security-policy.md`. | `llm-config/README.md` |
| lottie-animator | vendored | Snapshot of obeskay/lottie-animator-skill (MIT), vendored 2026-08-04. | `lottie-animator/SKILL.md` (PROVENANCE comment), `CHANGELOG.md` |
| pubcheck | framework | Its only source is this directory (`bin/pubcheck`; `~/.local/bin/pubcheck` links here); no separate repo or factory. Borderline: the README calls it "a plain CLI". | `pubcheck/README.md`, `pubcheck/bin/` |
| routa | adapter | Registry entry and skill for phodal/routa, a standalone CLI and desktop app (npm `routa-cli`, pin 0.18.1 recommended). | `routa/README.md` (Upstream & license, Install) |
| secrets-helper | adapter | README: "Thin integration addon for secrets-helper ... does not vendor the tool"; the tool has its own repo. | `secrets-helper/README.md` |
| security-pipeline | framework | agentBrain scaffolder for CI security workflows (own templates and injection-sink pack). It generates config for Semgrep, OSV and ZAP but does not wrap any of them. | `security-pipeline/templates/`, `tests/` |
| semantic-index | framework | Vault semantic search written for agentBrain (`src/cli.ts`, Ollama embeddings). No test suite exists yet. | `semantic-index/src/cli.ts` |
| session-journal | framework | Session journal hooks and scripts for agentBrain. | `session-journal/*.sh`, `tests/test-journal.sh` |
| session-map | framework | Session inventory and dashboard written for agentBrain (`lib/*.py`). No test suite exists yet. | `session-map/lib/` |
| shorthand | framework | agentBrain glossary and alias manager. | `shorthand/bin/`, `tests/test-shorthand.sh` |
| sitescope | adapter | README: "Optional adapter ... registers an existing `sitescope` CLI"; sitescope has its own factory. | `sitescope/README.md` |
| still-needed | framework | Its only source is this directory (`~/bin/still-needed` links here); no separate repo. | `still-needed/bin/`, `tests/test-still-needed.sh` |
| trailofbits-skills | vendored | Pointer to Trail of Bits' security skill collection (content authored by them); CC-BY-SA-4.0 per the upstream LICENSE, checked 2026-09-30. | `trailofbits-skills/README.md` |
| understand-anything | vendored | Pointer to Lum1104/Understand-Anything skills and plugin (MIT). | `understand-anything/README.md` (Upstream & license) |
| uxray | framework | README: "In-house methodology"; agentBrain skill only. No test suite exists yet. | `uxray/README.md`, `uxray/SKILL.md` |
| web-interface-guidelines | vendored | Verbatim snapshot of vercel-labs/web-interface-guidelines `command.md` (MIT), pulled 2026-07-26. | `web-interface-guidelines/README.md` (Snapshot provenance) |
| weekly-review | framework | Weekly vault summary written for agentBrain. | `weekly-review/bin/`, `tests/test-weekly-review.sh` |
| youtube-digest | framework | Ingestion code written for agentBrain (`src/`). It calls yt-dlp as a dependency but is not a thin layer over it. | `youtube-digest/src/`, `package.json` |
