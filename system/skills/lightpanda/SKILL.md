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

### Browse and extract (Smart URL handling)

All of these work automatically - URLs are normalized:

```bash
# Full URL
/lightpanda browse https://www.example.com

# With www (auto-adds https://)
/lightpanda browse www.example.com

# Domain only (auto-adds https://www.)
/lightpanda browse example.com

# Without www (auto-adds https://www.)
/lightpanda browse ninjatune.net
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
- 🎯 **Smart URL parsing** — automatically normalizes URLs

## Smart URL Normalization

The skill automatically normalizes URLs, so you can type any of these and they'll work:

### Input → Output

| Input | Normalized To |
|-------|---------------|
| `https://www.example.com` | `https://www.example.com` (unchanged) |
| `www.example.com` | `https://www.example.com` |
| `example.com` | `https://www.example.com` |
| `ninjatune.net` | `https://www.ninjatune.net` |
| `http://example.com` | `https://www.example.com` (upgrades to https, adds www) |

### Normalization Rules

1. **If URL already has `https://`** → Use as-is
2. **If URL starts with `http://`** → Upgrade to `https://`
3. **If URL has `www.`** → Add `https://` prefix
4. **If URL is just domain + extension** → Add `https://www.` prefix

### Examples

```bash
# All of these go to https://www.ninjatune.net
/lightpanda browse ninjatune.net
/lightpanda browse www.ninjatune.net
/lightpanda browse https://www.ninjatune.net
/lightpanda browse https://ninjatune.net
```

## Documentation

See related learnings:
- `Lightpanda-Setup.md` — Full installation and configuration
- `Lightpanda-Integrations.md` — MCP server and integration details
- `Lightpanda-QuickRef.md` — Quick reference guide

## Implementation: URL Normalization

Here's the logic used to normalize URLs:

```javascript
function normalizeUrl(input) {
  let url = input.trim();
  
  // Rule 1: Already a full HTTPS URL
  if (url.startsWith('https://')) {
    return url;
  }
  
  // Rule 2: HTTP URL - upgrade to HTTPS
  if (url.startsWith('http://')) {
    url = url.replace('http://', 'https://');
    // If no www, add it (unless it's localhost or IP)
    if (!url.includes('www.') && !url.startsWith('https://localhost') && !url.match(/https:\/\/\d/)) {
      url = url.replace('https://', 'https://www.');
    }
    return url;
  }
  
  // Rule 3: Starts with www - add https
  if (url.startsWith('www.')) {
    return 'https://' + url;
  }
  
  // Rule 4: Plain domain (has . but no //) - add https://www.
  if (url.includes('.') && !url.includes('//')) {
    return 'https://www.' + url;
  }
  
  // Fallback: Just add https://www.
  return 'https://www.' + url;
}
```

### Tests
```javascript
normalizeUrl('ninjatune.net')        // → 'https://www.ninjatune.net'
normalizeUrl('www.ninjatune.net')    // → 'https://www.ninjatune.net'
normalizeUrl('https://ninjatune.net') // → 'https://www.ninjatune.net' (adds www)
normalizeUrl('https://www.ninjatune.net') // → 'https://www.ninjatune.net'
```

## Workflow

When you call:
```
/lightpanda browse ninjatune.net
```

1. Skill receives: `ninjatune.net`
2. Normalize: `https://www.ninjatune.net`
3. Browse: Navigate to normalized URL
4. Extract: Return page content
5. Format: Return as markdown/JSON

## Examples

### Example 1: Quick Browse (Just Domain)
```bash
/lightpanda browse ninjatune.net
# Automatically becomes: https://www.ninjatune.net
```

### Example 2: With www (Still Works)
```bash
/lightpanda browse www.github.com
# Automatically becomes: https://www.github.com
```

### Example 3: Extract from Domain Only
```bash
/lightpanda extract ".artist-name"
# Uses the last browsed URL, normalizes if needed
```

### Example 4: Search + Browse
```bash
/lightpanda search "best music labels 2026"
# Then if you want to browse a result:
/lightpanda browse pitchfork.com
```

## References

- **Official**: https://lightpanda.io
- **GitHub**: https://github.com/lightpanda-io/browser
- **PI Extension**: https://github.com/MonsieurBarti/Lightpanda-PI
- **MCP Server**: https://github.com/daanrongen/lightpanda-mcp

---

**Installed**: 2026-05-14  
**Status**: Ready for use ✅
