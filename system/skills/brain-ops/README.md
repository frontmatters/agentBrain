---
date: 2026-08-16
type: system
tags: [skill, brain-ops, itsm, kedb]
id: 7406399b-f3c4-5edf-a563-04ac34064c5a
---

# brain-ops

The ops-records layer (block 2 of the IT-frameworks alignment): incident /
problem / known-error / postmortem notes, CI-anchored via the CMDB. Answers
"what broke, why, and the fix" — the counterpart to `brain-cmdb` ("what exists
and how it connects"). Self-contained bash + awk, space-scoped exactly like
`brain-cmdb`.

## Install

Bundled system skill — no install. Invoke via the CLI or the `/brain-ops` skill.

## Quick use

```bash
bin=system/skills/brain-ops/bin/brain-ops
bash "$bin" new incident 2026-08-16-gitea-reboot   # scaffold, then fill CI(s) + body
bash "$bin" known-errors --ci gitea-host            # consult the KEDB before re-solving
bash "$bin" on gitea-host                            # everything that broke on this CI
bash "$bin" timeline gitea-host                      # chronological incidents + postmortems
```

Prefix `--space <slug>` to scope to a client space.

## Good fits

- A note-native KEDB you consult before re-solving a recurring failure.
- Per-CI incident history joined to the CMDB via the stable ci-id.
- Solo-scale ITIL/SRE hygiene without enterprise ticketing.

## Privacy

`local` — all ops data is private. Records live under `vault/[spaces/<slug>/]ops/`.
A client's records stay sealed in that client's space and sync to its own remote,
never the personal vault. `promote` (anonymized space→personal lift) is deferred
and, when built, is explicit + human-gated + privacy-scan-backstopped (spec §7).

## Status

MVP: the query + scaffold surface (`on`/`incidents`/`known-errors`/`problems`/
`timeline`/`show`/`new`) with hermetic tests. Deferred: `promote` (§7) and the
`save-troubleshoot` → known-error redirect (§6). Design:
the maintainer's vault (design record `2026-08-16-ops-records-design`).
