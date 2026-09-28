---
date: 2026-07-07
type: system
tags: [templates, reference]
id: 76bf15b1-2b68-5edd-b565-c9828898521e
---

# Templates

Reusable fill-in templates. The originals here stay generic — no user,
project or client specifics; those belong in `vault/`.

**Copy the body, never the file.** Each template carries a real `id`
derived from its own path under `system/`, because every note in the public
layer must pass the frontmatter check. Copying the file into `vault/` therefore
carries that id along, and the validate-hook rejects it as a mismatch. Create
the note first, then paste the body in:

```sh
bash scripts/new-note.sh device vault/devices/<hostname>
bash scripts/new-note.sh integration vault/integrations/<service>
```

The war-game template has no matching type; create it as `spec` and adjust
the tags.

| Template | Copy to | Purpose |
| --- | --- | --- |
| `war-game-mission-template.md` | `vault/projects/<project>/war-games/<mission>.md` | Wargame a mission on paper (moves, forks, abort conditions) before feeding it to a cheaper executor model |
| `device-template.md` | `vault/devices/<hostname>.md` | One note per owned device (role, specs, network by name, services, lifecycle) — hostnames are canonical for wikilinks; maintain a `vault/devices/index.md` hop-page with one line per device |
| `integration-template.md` | `vault/integrations/<service>.md` | One note per external service (instance, auth by helper/env NAME — never values, common commands) — agents check here before asking for credentials |

Privacy rule (applies to every template): structure ships publicly here;
knowledge stays private in `vault/`. Credentials are referenced by helper,
env-var, or keychain-item NAME — never by value, not even in `vault/`.
