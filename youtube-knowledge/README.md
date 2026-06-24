---
date: 2026-05-18
type: system
tags: [youtube, knowledge, meta]
id: 355de54b-9bfe-538a-b4e6-f78163dcba57
---

# YouTube Knowledge

YouTube video transcripts and notes. Real content lives in `local/youtube-knowledge/`.

## Structure

```
local/youtube-knowledge/
├── ai-ml/           ← AI/ML related videos
├── development/     ← Software development videos
└── ...              ← Categories created automatically
```

## How it works

Agents use `youtube_transcript_download` to fetch subtitles and save them here. The tool automatically:

1. Downloads subtitles via yt-dlp
2. Converts VTT to clean text
3. Saves as markdown with frontmatter in the appropriate category folder

## Privacy

- This public folder is a placeholder only
- All transcript content goes to `local/youtube-knowledge/` (gitignored)
- No personal watch history or account info is stored
