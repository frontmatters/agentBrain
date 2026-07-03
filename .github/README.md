---
date: 2026-05-18
type: system
tags: [github, skills, meta]
id: f1100c7f-8ef5-5525-b889-7a127da9cc1c
---

# .github

GitHub-specific configuration for agentBrain.

## Structure

- `copilot-instructions.md` — Entry point for GitHub Copilot. Automatically loaded by Copilot in repos that reference agentBrain.
- `skills/` — Agent skills (slash commands), each in its own folder
- `workflows/` — GitHub Actions (if any)

## Skills

| Skill               | Purpose                                   |
| ------------------- | ----------------------------------------- |
| `doctor`            | Health audit for the agentBrain framework |
| `brain-review`      | Monthly review of agentBrain notes        |
| `onboard`           | Interactive first-setup for new users     |
| `project-update`    | Create or update project folders          |
| `save-learning`     | Save a technical insight                  |
| `save-troubleshoot` | Log a problem and solution                |
| `lightpanda`        | Install and configure Lightpanda browser  |
