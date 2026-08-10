---
date: 2026-07-07
type: system
tags: [templates, reference]
id: 76bf15b1-2b68-5edd-b565-c9828898521e
---

# Templates

Reusable fill-in templates. Copy a template into the appropriate `local/`
location and fill it in — the originals here stay generic (no user, project,
or client specifics; those belong in `local/`).

| Template | Copy to | Purpose |
| --- | --- | --- |
| `war-game-mission-template.md` | `local/projects/<project>/war-games/<mission>.md` | Wargame a mission on paper (moves, forks, abort conditions) before feeding it to a cheaper executor model |
| `device-template.md` | `local/devices/<hostname>.md` | One note per owned device (role, specs, network by name, services, lifecycle) — hostnames are canonical for wikilinks; maintain a `local/devices/index.md` hop-page with one line per device |
| `integration-template.md` | `local/integrations/<service>.md` | One note per external service (instance, auth by helper/env NAME — never values, common commands) — agents check here before asking for credentials |

Privacy rule (applies to every template): structure ships publicly here;
knowledge stays private in `local/`. Credentials are referenced by helper,
env-var, or keychain-item NAME — never by value, not even in `local/`.
