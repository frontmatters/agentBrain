#!/bin/bash

###############################################################################
# Lightpanda Complete Installer
#
# Installs and configures Lightpanda for use in Pi agent
# - Lightpanda browser (headless engine)
# - npm packages (core, MCP server, Pi extension)
# - Pi skill registration and wrapper
# - Verification and tests
#
# Usage: bash lightpanda-install.sh
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
	echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
	echo -e "${GREEN}✓${NC}  $1"
}

log_warn() {
	echo -e "${YELLOW}⚠${NC}  $1"
}

log_error() {
	echo -e "${RED}✗${NC}  $1"
}

###############################################################################
# STEP 1: Check Prerequisites
###############################################################################

log_info "Checking prerequisites..."

# Check Node.js
if ! command -v node &>/dev/null; then
	log_error "Node.js is not installed. Please install Node.js 20.0 or later."
	exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
	log_error "Node.js version must be 20.0 or later. Current: $(node -v)"
	exit 1
fi
log_success "Node.js $(node -v) found"

# Check npm
if ! command -v npm &>/dev/null; then
	log_error "npm is not installed."
	exit 1
fi
log_success "npm $(npm -v) found"

# Check Pi agent directory
PI_AGENT_DIR="${HOME}/.pi/agent"
if [ ! -d "$PI_AGENT_DIR" ]; then
	log_error "Pi agent directory not found at $PI_AGENT_DIR"
	log_info "Install Pi first: https://github.com/mariozechner/pi"
	exit 1
fi
log_success "Pi agent directory found at $PI_AGENT_DIR"

###############################################################################
# STEP 2: Install Lightpanda Browser
###############################################################################

log_info "Installing Lightpanda browser engine..."

if command -v lightpanda &>/dev/null; then
	CURRENT_VERSION=$(lightpanda --version 2>/dev/null || echo "unknown")
	log_warn "Lightpanda browser already installed (version: $CURRENT_VERSION)"
	read -p "  Reinstall? (y/n) " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		log_info "Reinstalling Lightpanda..."
		curl -fsSL https://pkg.lightpanda.io/install.sh | bash
	fi
else
	log_info "Downloading and installing Lightpanda..."
	curl -fsSL https://pkg.lightpanda.io/install.sh | bash
fi

# Verify installation
if command -v lightpanda &>/dev/null; then
	LIGHTPANDA_VERSION=$(lightpanda --version)
	LIGHTPANDA_PATH=$(which lightpanda)
	log_success "Lightpanda browser $LIGHTPANDA_VERSION installed at $LIGHTPANDA_PATH"
else
	log_error "Lightpanda installation failed. Please check the install script."
	exit 1
fi

###############################################################################
# STEP 3: Install npm Packages
###############################################################################

log_info "Installing npm packages globally..."

PACKAGES=(
	"@lightpanda/browser@1.2.0"
	"@daanrongen/lightpanda-mcp@1.1.5"
	"@the-forge-flow/lightpanda-pi@0.2.1"
)

for package in "${PACKAGES[@]}"; do
	if npm list -g "$package" &>/dev/null; then
		log_warn "$package already installed"
	else
		log_info "Installing $package..."
		npm install -g "$package"
		log_success "Installed $package"
	fi
done

###############################################################################
# STEP 4: Register Pi Skill
###############################################################################

log_info "Registering Lightpanda as Pi skill..."

PI_SKILLS_DIR="$PI_AGENT_DIR/skills"
LIGHTPANDA_SKILL_DIR="$PI_SKILLS_DIR/lightpanda"

# Get the actual installed location
LIGHTPANDA_PKG_PATH=$(npm list -g @the-forge-flow/lightpanda-pi --json 2>/dev/null |
	grep -o '"resolved":"[^"]*' | cut -d'"' -f4 | head -1)

if [ -z "$LIGHTPANDA_PKG_PATH" ]; then
	# Fallback to standard location
	LIGHTPANDA_PKG_PATH="/opt/homebrew/lib/node_modules/@the-forge-flow/lightpanda-pi"
	if [ ! -d "$LIGHTPANDA_PKG_PATH" ]; then
		LIGHTPANDA_PKG_PATH="$(npm list -g @the-forge-flow/lightpanda-pi 2>/dev/null |
			head -1 | grep -o '/.*' | cut -d' ' -f1)"
	fi
fi

if [ ! -d "$LIGHTPANDA_PKG_PATH" ]; then
	log_error "Could not find Lightpanda package location"
	exit 1
fi

log_info "Found Lightpanda package at: $LIGHTPANDA_PKG_PATH"

# Remove existing symlink if it exists
if [ -L "$LIGHTPANDA_SKILL_DIR" ]; then
	rm "$LIGHTPANDA_SKILL_DIR"
	log_info "Removed old symlink"
fi

# Remove existing directory if it exists (but not if it's a symlink with content)
if [ -d "$LIGHTPANDA_SKILL_DIR" ] && [ ! -L "$LIGHTPANDA_SKILL_DIR" ]; then
	log_warn "Backing up existing $LIGHTPANDA_SKILL_DIR to ${LIGHTPANDA_SKILL_DIR}.bak"
	mv "$LIGHTPANDA_SKILL_DIR" "${LIGHTPANDA_SKILL_DIR}.bak"
fi

# Create symlink
ln -sf "$LIGHTPANDA_PKG_PATH" "$LIGHTPANDA_SKILL_DIR"
log_success "Created symlink: $LIGHTPANDA_SKILL_DIR → $LIGHTPANDA_PKG_PATH"

###############################################################################
# STEP 5: Create SKILL.md Wrapper
###############################################################################

log_info "Creating SKILL.md wrapper..."

# Ensure directory exists
mkdir -p "$LIGHTPANDA_SKILL_DIR"

cat >"$LIGHTPANDA_SKILL_DIR/SKILL.md" <<'EOF'
---
name: lightpanda
version: 0.2.1
description: Web search and browsing using Lightpanda headless browser for AI agents
tags: [web-search, browser, automation, data-extraction]
author: The Forge Flow
---

# Lightpanda Web Search Skill

Ultra-fast web search and browsing powered by [Lightpanda](https://lightpanda.io) — a 64MB headless browser written in Zig, 9x faster than Chrome with 16x less memory.

## Installation

The Lightpanda browser must be on your `PATH`:

```bash
# Install Lightpanda browser
curl -fsSL https://pkg.lightpanda.io/install.sh | bash

# Verify
lightpanda --version
```

npm packages installed:
- `@the-forge-flow/lightpanda-pi@0.2.1` — PI extension
- `@daanrongen/lightpanda-mcp@1.1.5` — MCP server (for Claude Code)
- `@lightpanda/browser@1.2.0` — Core browser library

## Usage

### Search the web
```bash
/lightpanda search "latest AI developments"
```

### Browse and extract
```bash
/lightpanda browse https://example.com
```

### Extract specific content
```bash
/lightpanda extract ".product-list"
```

### Fill and submit forms
```bash
/lightpanda form '{"email":"user@example.com","password":"secret"}'
```

### Take screenshot
```bash
/lightpanda screenshot
```

## Features

- ⚡ **10× faster** than Chrome headless
- 💾 **16× less memory** (6MB vs 100MB+)
- 🧹 **Clean output** with markdown formatting
- 📊 **Structured data** extraction as JSON
- 🔒 **Local-only** — no cloud APIs, no rate limits
- 🖥️ **Zero dependencies** — no Chromium/WebKit

## Documentation

See related learnings:
- `Lightpanda-Setup.md` — Full installation and configuration
- `Lightpanda-Integrations.md` — MCP server and integration details
- `Lightpanda-QuickRef.md` — Quick reference guide

## References

- **Official**: https://lightpanda.io
- **GitHub**: https://github.com/lightpanda-io/browser
- **PI Extension**: https://github.com/MonsieurBarti/Lightpanda-PI
- **MCP Server**: https://github.com/daanrongen/lightpanda-mcp

---

**Installed**: 2026-05-14  
**Status**: Ready for use ✅
EOF

log_success "Created SKILL.md wrapper at $LIGHTPANDA_SKILL_DIR/SKILL.md"

###############################################################################
# STEP 6: Verification
###############################################################################

log_info "Verifying installation..."

# Check Lightpanda browser
if command -v lightpanda &>/dev/null; then
	LIGHTPANDA_VERSION=$(lightpanda --version)
	log_success "Lightpanda browser: $LIGHTPANDA_VERSION"
else
	log_error "Lightpanda browser verification failed"
	exit 1
fi

# Check npm packages
log_info "Checking npm packages..."
for package in "${PACKAGES[@]}"; do
	if npm list -g "$package" &>/dev/null; then
		log_success "  $package"
	else
		log_error "  $package NOT FOUND"
		exit 1
	fi
done

# Check Pi skill registration
if [ -L "$LIGHTPANDA_SKILL_DIR" ]; then
	log_success "Pi skill symlink: $LIGHTPANDA_SKILL_DIR"
else
	log_error "Pi skill symlink not found"
	exit 1
fi

if [ -f "$LIGHTPANDA_SKILL_DIR/SKILL.md" ]; then
	log_success "SKILL.md wrapper created"
else
	log_error "SKILL.md wrapper not found"
	exit 1
fi

###############################################################################
# STEP 7: Test Command
###############################################################################

log_info "Testing basic functionality..."

# Test if lightpanda can start
if lightpanda --help &>/dev/null; then
	log_success "Lightpanda browser is functional"
else
	log_warn "Could not verify Lightpanda functionality (may need restart)"
fi

###############################################################################
# FINAL SUMMARY
###############################################################################

echo ""
log_success "Lightpanda installation complete! ✅"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Quick Start:"
echo ""
echo "  Browse a website:"
echo "    /lightpanda browse https://example.com"
echo ""
echo "  Search the web:"
echo "    /lightpanda search \"query\""
echo ""
echo "  Extract content:"
echo "    /lightpanda extract \".selector\""
echo ""
echo "  Fill form:"
echo "    /lightpanda form '{\"email\":\"user@example.com\"}'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 Documentation:"
echo "  - Setup guide:   ~/Developer/agentBrain/learnings/Lightpanda-Setup.md"
echo "  - Integrations:  ~/Developer/agentBrain/learnings/Lightpanda-Integrations.md"
echo "  - Quick ref:     ~/Developer/agentBrain/learnings/Lightpanda-QuickRef.md"
echo ""
echo "📍 Installation locations:"
echo "  - Browser:       $(which lightpanda)"
echo "  - Pi skill:      $LIGHTPANDA_SKILL_DIR"
echo "  - npm packages:  $(npm config get prefix)/lib/node_modules/"
echo ""
echo "🔧 Additional commands:"
echo "  - Start MCP server: lightpanda-mcp"
echo "  - Test Node.js API: npm run test:core"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
