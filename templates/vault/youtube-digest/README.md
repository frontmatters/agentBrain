---
date: {{date}}
type: system
tags: [youtube, knowledge, meta]
id: {{uuid5}}
---

# YouTube Digest

Public placeholder for YouTube transcript ingestion. Real content lives in
`vault/youtube-digest/` (gitignored).

## Structure

```
vault/youtube-digest/
├── ai-ml/           ← AI/ML related videos
├── development/     ← Software development videos
└── ...              ← <category>/<channel>/<year>/<date>-<slug>-<videoId>.md
```

## How it works

Transcripts are pulled in by the `youtube-digest` add-on
(`system/addons/youtube-digest/`, CLI `yt-digest`):

1. `yt-digest sync` — iterate configured channels (`vault/addons/youtube-digest/channels.json`), fetch the latest videos, dedup against state
2. `yt-digest fetch <url|id>` — single video, ad-hoc
3. `yt-digest learn` — extract learnings from saved transcripts into `vault/learnings/extracted/`

The pipeline downloads metadata + transcript via `yt-dlp`, summarizes, and saves
markdown with frontmatter into the appropriate category folder. See
`system/addons/youtube-digest/README.md` for setup and details.

## Privacy

- This public folder is a placeholder only
- All transcript content goes to `vault/youtube-digest/` (gitignored)
- No personal watch history or account info is stored
