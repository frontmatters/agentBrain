---
date: {{date}}
type: system
tags: [meta, private, local]
id: {{uuid5}}
---

# Private Local Layer

This is the private layer of agentBrain. Nothing here is ever committed to git.

## Structure

| Folder               | Purpose                                               |
| -------------------- | ----------------------------------------------------- |
| `projects/`          | Project notes — one subfolder per active project      |
| `learnings/`         | Real technical discoveries, patterns, troubleshooting |
| `preferences/`       | Your actual work style, tech stack, design philosophy |
| `integrations/`      | Tool configs, bot configs, API key references         |
| `security/`          | Auth setup notes, credential guides                   |
| `memories/`          | Personal agent context                                |
| `research/`          | Research notes                                        |
| `setup-history/`     | Machine setup history                                 |
| `youtube-digest/`    | Downloaded transcripts (youtube-digest add-on)        |
| `sessions/`          | Session logs                                          |
| `backlog/`           | Personal backlog items                                |

## Rules

- Real project notes → `projects/<name>/index.md`
- Real learnings → `learnings/troubleshooting.md` or `learnings/patterns.md`
- Never store token values here — use keychain + `integrations/*.md` for references only
