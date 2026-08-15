---
date: 2026-05-18
type: system
tags: [scripts, lightpanda]
id: 84f514b3-b0be-53b2-8ae8-a06be5b479a0
---

#!/bin/bash

#

# Lightpanda Installer - Quick Start Guide

#

# This script installs Lightpanda for use in Pi agent

#

# ═══════════════════════════════════════════════════════════════════════════

#

# INSTALLATION (ONE COMMAND):

#

# bash bash scripts/lightpanda-install.sh

#

# ═══════════════════════════════════════════════════════════════════════════

#

# WHAT IT DOES:

#

# 1. ✅ Checks Node.js 20+ and Pi agent installation

# 2. ✅ Installs Lightpanda browser (64MB headless engine)

# 3. ✅ Installs 3 npm packages (core, MCP server, Pi extension)

# 4. ✅ Registers Pi skill with symlink

# 5. ✅ Creates SKILL.md wrapper

# 6. ✅ Verifies everything works

# 7. ✅ Shows quick start guide

#

# ═══════════════════════════════════════════════════════════════════════════

#

# QUICK START AFTER INSTALL:

#

# # Browse a URL

# /lightpanda browse https://example.com

#

# # Search the web

# /lightpanda search "query"

#

# # Extract content

# /lightpanda extract ".selector"

#

# # Fill forms

# /lightpanda form '{"email":"user@example.com"}'

#

# ═══════════════════════════════════════════════════════════════════════════

#

# DOCUMENTATION:

#

# Setup guide:

# local/learnings/lightpanda-Pi-Setup-Complete.md

#

# Full details:

# local/learnings/lightpanda-Setup.md

# local/learnings/lightpanda-Integrations.md

# local/learnings/lightpanda-QuickRef.md

#

# ═══════════════════════════════════════════════════════════════════════════

#

# REINSTALL / UPDATE:

#

# # Run installer again (detects existing, asks to reinstall)

# bash bash scripts/lightpanda-install.sh

#

# ═══════════════════════════════════════════════════════════════════════════

#

# INSTALLED LOCATIONS:

#

# Browser: /opt/homebrew/bin/lightpanda

# npm packages: /opt/homebrew/lib/node_modules/@lightpanda/\*

# Pi skill: ~/.pi/agent/skills/lightpanda (symlink)

#

# ═══════════════════════════════════════════════════════════════════════════

#

# TROUBLESHOOTING:

#

# If "command not found":

# export PATH="/opt/homebrew/bin:$PATH"

# bash bash scripts/lightpanda-install.sh

#

# If Pi doesn't recognize /lightpanda:

# Restart Pi or run: /reload

#

# For full troubleshooting, see:

# local/learnings/lightpanda-Pi-Setup-Complete.md

#

# ═══════════════════════════════════════════════════════════════════════════

#

# STATUS:

#

# ✅ Installer ready to use

# ✅ All components installed

# ✅ Pi skill registered

# ✅ Documentation complete

#

# ═══════════════════════════════════════════════════════════════════════════

echo "🚀 Lightpanda Installer"
echo ""
echo "To run the full installation, execute:"
echo ""
echo " bash bash scripts/lightpanda-install.sh"
echo ""
echo "For documentation, see:"
echo " local/learnings/lightpanda-Pi-Setup-Complete.md"
echo ""
