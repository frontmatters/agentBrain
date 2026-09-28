---
date: 2026-08-16
type: system
tags: [skill, brain-ops, itsm, kedb]
id: 7406399b-f3c4-5edf-a563-04ac34064c5a
---

# brain-ops

The ops-records layer: incident /
problem / known-error / postmortem notes, CI-anchored via the CMDB. Answers
"what broke, why, and the fix" — the counterpart to `brain-cmdb` ("what exists
and how it connects"). Self-contained bash + awk, space-scoped exactly like
`brain-cmdb`.

## Install

Bundled system skill — no install. Invoke via the CLI or the `/brain-ops` skill.

## Quick use

```bash
bin=system/skills/brain-ops/bin/brain-ops
bash "$bin" new incident 2026-01-10-web-reboot    # scaffold, then fill CI(s) + body
bash "$bin" known-errors --ci web-host            # consult the KEDB before re-solving
bash "$bin" on web-host                           # everything that broke on this CI
bash "$bin" timeline web-host                     # chronological incidents + postmortems
```

Prefix `--space <slug>` to scope to a client space.

## Good fits

- A note-native KEDB you consult before re-solving a recurring failure.
- Per-CI incident history joined to the CMDB via the stable ci-id.
- Solo-scale ITIL/SRE hygiene without enterprise ticketing.

## Privacy

`local` — all ops data is private. Records live under `vault/[spaces/<slug>/]ops/`.
A client's records stay sealed in that client's space and sync to its own remote,
never the personal vault. There is no command that lifts records out of a client
space.

## Status

The query + scaffold surface (`on`/`incidents`/`known-errors`/`problems`/
`timeline`/`show`/`new`) with hermetic tests. `save-troubleshoot` does not write
here; create a known-error record with `new known-error <slug>`.
