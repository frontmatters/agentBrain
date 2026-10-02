---
date: 2026-10-01
type: system
tags: [addon, changelog]
id: 17ef4d81-ee66-5b87-b6ae-5ed4931b6950
---

# Changelog

## [Unreleased]

### Fixed

- Avoid blocking identifier-shaped secret assignments while still blocking
  long varied literals; detect URL userinfo passwords from eight characters,
  except the literal `password` placeholder.
- Block URL userinfo credentials, secret assignments, curl Basic credentials
  and Authorization Basic values. Ignore obvious repeated-character key placeholders.
- Quote the hook path when registering/removing it, including paths with spaces.
- Document Pi's fail-closed behavior and unlink procedure.

## [0.1.0] - 2026-10-01

### Added

- Claude PreToolUse secret scanner and Pi tool_call mirror, opt-in installation,
  isolated-home installation tests, and detection/allowance regression tests.
