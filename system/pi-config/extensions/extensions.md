---
date: 2026-05-18
type: reference
tags: [pi, extensions, api]
id: 30e91b2f-dfe9-5e95-9674-c3eadda6409e
---

# Pi Extensions

Custom Pi extensions stored in `system/pi-config/extensions/`.  
Symlinked to `~/.pi/agent/extensions/` by `scripts/bootstrap-macos.sh`.

## Setup

Run the bootstrap once per machine to:

- Symlink extensions into `~/.pi/agent/extensions/`
- Generate the machine-specific `tsconfig.json` for editor type-checking
- Verify that the Pi API symbols these extensions depend on still exist

```bash
bash scripts/bootstrap-macos.sh
```

> `tsconfig.json` is **gitignored** (machine-specific paths).  
> `tsconfig.template.json` is the tracked source — bootstrap fills in `__PI_MODULES__`.

## Extensions

| File                    | What it does                                                            | Pi events / methods used                                                                                  |
| ----------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `agentbrain.ts`         | Injects agentBrain project context into every agent session             | `session_start`, `before_agent_start`, `registerTool`                                                     |
| `session-continuity.ts` | Archives/starts the session journal on Pi session start                 | `session_start`                                                                                           |
| `extract-learnings.ts`  | Auto-extracts learnings from sessions before compaction                 | `session_before_compact`, `session_shutdown`, `ctx.getModel()`, `ctx.modelRegistry.getApiKeyAndHeaders()` |
| `youtube-transcript.ts` | `youtube_transcript_info` + `youtube_transcript_download` tools         | `registerTool`                                                                                            |
| `pi-cloak/index.ts`     | Redacts secrets from tool output based on `~/.pi-cloak.yml`             | `tool_result`, `session_start`, `registerCommand`                                                         |
| `glm.ts`                | GLM / z.ai provider with keychain fallback                              | `registerProvider`                                                                                        |
| `ollama-cloud.ts`       | Ollama Cloud provider with keychain fallback                            | `registerProvider`                                                                                        |
| `ollama-discovery.ts`   | Discovers local Ollama models at startup and registers provider models  | `registerProvider`                                                                                        |
| `flow-title.ts`         | Animated gradient session header                                        | `session_start`, `model_change`, `registerCommand`                                                        |
| `tps-tracker.ts`        | Live tokens/s display during generation                                 | `agent_start/end`, `message_start/update/end`                                                             |
| `git-status-widget.ts`  | Git status widget in the Pi sidebar                                     | `session_start`, `tool_execution_end`, `registerWidget`                                                   |
| `copy-all.ts`           | `/copy-all` command — copies full conversation to clipboard             | `registerCommand`                                                                                         |
| `lg.ts`                 | `/lg` command — summarizes unstaged git changes                         | `registerCommand`                                                                                         |
| `usage.ts`              | `/usage` command — Pi session usage report                              | `registerCommand`                                                                                         |
| `git-interceptor.ts`    | Blocks `--no-verify`, injects `GIT_EDITOR=true` to prevent editor hangs | `tool_call`, `isToolCallEventType`                                                                        |
| `incognito-guard.ts`    | Blocks Write/Edit/MultiEdit to `local/` knowledge while incognito is on | `tool_call`                                                                                              |
| `note-id-validator.ts`  | Pre-write BLOCK of a Write carrying a mismatched note-`id:` (tool_call); post-write advisory net for Edit/MultiEdit (tool_result). Shells out to `scripts/validate-note-id.sh` | `tool_call`, `tool_result`                                                 |
| `zsh-user-bash.ts`      | Runs user bash via zsh login shell (fixes PATH on macOS)                | `registerTool`                                                                                            |

> **Addon-provided extensions** are not listed above and do not live in this
> directory. Example: `voice.ts` (the `/voice` command) is symlinked into
> `~/.pi/agent/extensions/` by the **voice addon**'s own install step — see
> that addon's docs; this directory's bootstrap does not manage it.

## Pi API compatibility

These are the Pi API symbols actively called by the extensions above.  
If a Pi update breaks an extension, check these first:

| Symbol                                    | Used by                                                      | Where in types.d.ts                 |
| ----------------------------------------- | ------------------------------------------------------------ | ----------------------------------- |
| `ctx.getModel()`                          | `extract-learnings.ts`                                       | `ExtensionContext.getModel`         |
| `ctx.modelRegistry.getApiKeyAndHeaders()` | `extract-learnings.ts`                                       | `ModelRegistry.getApiKeyAndHeaders` |
| `ctx.modelRegistry`                       | `extract-learnings.ts`                                       | `ExtensionContext.modelRegistry`    |
| `pi.registerTool()`                       | `agentbrain.ts`, `youtube-transcript.ts`, `zsh-user-bash.ts` | `ExtensionAPI.registerTool`         |
| `pi.registerCommand()`                    | most extensions                                              | `ExtensionAPI.registerCommand`      |
| `pi.registerProvider()`                   | `glm.ts`, `ollama-cloud.ts`, `ollama-discovery.ts`           | `ExtensionAPI.registerProvider`     |
| `pi.on("session_start", ...)`             | multiple                                                     | `ExtensionAPI.on`                   |
| `pi.on("before_agent_start", ...)`        | `agentbrain.ts`                                              | `ExtensionAPI.on`                   |
| `pi.on("session_before_compact", ...)`    | `extract-learnings.ts`                                       | `ExtensionAPI.on`                   |
| `pi.on("tool_result", ...)`               | `pi-cloak/index.ts`, `note-id-validator.ts`                  | `ExtensionAPI.on`                   |
| `pi.on("tool_call", ...)`                 | `git-interceptor.ts`, `incognito-guard.ts`, `note-id-validator.ts` | `ExtensionAPI.on`             |
| `isToolCallEventType()`                   | `git-interceptor.ts`                                         | exported from `pi-coding-agent`     |

The bootstrap script checks these symbols automatically after every Pi install/update:

```bash
# Runs automatically in bootstrap, or manually:
grep -q "getModel" \
  ~/.bun/install/global/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts \
  && echo "OK" || echo "CHANGED — check extract-learnings.ts"
```

## Adding an extension

1. Add `myext.ts` to `system/pi-config/extensions/`
2. Run `bash scripts/bootstrap-macos.sh` (or symlink manually)
3. Update the table above with the Pi API methods used
4. Add the critical symbols to the `required_symbols` list in `scripts/configure-pi.sh`

## pi-lens suppression

Pi-lens fact-rules fire on extensions just like on regular code.  
Suppress known false-positives inline — **only the rule ID, no trailing text**:

```ts
// pi-lens-ignore: high-complexity
export default function (pi: ExtensionAPI) {
```

```ts
// pi-lens-ignore: dynamic-regexp
const regex = new RegExp(pattern, "g");
```

> Trailing text after a comma works for multiple rules: `// pi-lens-ignore: high-complexity, high-fan-out`  
> Text after `—` breaks the suppression — the parser splits only on `,`.
