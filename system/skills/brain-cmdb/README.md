---
date: 2026-08-15
type: system
tags: [skill, brain-cmdb]
id: 5d8e4e77-cb81-5efa-a450-341af841895b
---

# brain-cmdb

Note-native CMDB query skill over `vault/devices/` + `vault/integrations/`.

## Purpose

See what runs on a host, what depends on a CI, and keep each CI's `## Relations`
section generated from its authoritative frontmatter relations.

## Usage

```
/brain-cmdb [--space <slug>] list | register <ci>|--backfill | show <ci> | runs-on <host> | what-depends-on <ci> | resolve <ci|ci-id> | rename <old> <new> | sync
```
