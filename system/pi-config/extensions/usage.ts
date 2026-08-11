import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const USAGE_PROMPT = `Create an AI coding usage report for my Pi, Codex CLI, and Claude sessions over the last 1, 7, 30, and 90 days.

Goal:
- Produce a clean Markdown table for each window: 1 day, 7 days, 30 days, 90 days.
- For each model in each window, show:
  - source/app (Pi, Codex CLI, or Claude entrypoint)
  - model/provider
  - assistant messages or turns counted
  - uncached input tokens
  - output tokens
  - cache-read tokens
  - cache-creation/write tokens
  - reported prompt reuse percentage
  - total tokens
  - price in USD
- Include a grand total row for each window.
- Use current model pricing from models.dev, not stale local assumptions.

Detailed steps:
1. Find all Pi session JSONL files under ~/.pi/agent/sessions recursively.
2. Find Codex CLI session JSONL files under ~/.codex/sessions recursively and ~/.codex/archived_sessions if present. Codex CLI stores JSONL records like:
   - { type: "turn_context", payload: { model, ... } }
   - { type: "event_msg", payload: { type: "token_count", info: { total_token_usage, last_token_usage, model_context_window }, ... } }
   Use token_count payload.info.last_token_usage for per-turn usage to avoid double-counting cumulative total_token_usage. Use the most recent preceding turn_context/session_meta in that file to determine model/provider when the token_count entry does not include a model directly. Count one turn/message per token_count entry with last_token_usage.
3. Find Claude session JSONL files under ~/.claude/projects recursively. Claude records usually have type "assistant", message.role "assistant", message.model, message.usage, requestId, sessionId, and entrypoint. The same API response may be repeated across multiple content-block records with identical usage. Deduplicate before aggregation using requestId + message.id; if requestId is absent, use sessionId + message.id. Count and price each unique response exactly once. Label the source from entrypoint when present (for example Claude Code or Claude Desktop), otherwise "Claude".
4. Use filesystem and record timestamps to include responses from the last 1, 7, 30, and 90 days relative to now.
5. Parse every JSONL line safely. Ignore malformed lines, but mention if any were skipped, separated by source when useful.
6. Count assistant/turn records with model usage data. For Pi, also count toolResult records that carry nested LLM message.usage; these are separate provider calls and are not included in the surrounding assistant message usage.
7. Group by source plus a stable model key. Prefer provider + model from the record, for example "openai-codex/gpt-5.5", "codex-cli/openai/gpt-5.4", or "anthropic/claude-fable-5". If only model is present, use that.
8. For each Pi assistant message with usage, add:
   - messages/turns += 1
   - uncached input from usage.input
   - output from usage.output
   - cache read from usage.cacheRead
   - cache write from usage.cacheWrite when present, otherwise 0
   - prompt tokens for reuse math = input + cacheRead + cacheWrite
   - total from usage.totalTokens if present, otherwise input + cacheRead + cacheWrite + output
8b. For each Pi toolResult message with nested LLM usage, apply the same token mapping as 8 and count one nested turn. Prefer message.details.evaluatorModel as the stable provider/model key; otherwise use the most recent preceding assistant provider/model in that session. Do not count toolResult records without usage, and do not merge their usage into the surrounding assistant record before counting because that would hide the provider call boundary.
9. For each Codex CLI token_count event with last_token_usage, add:
   - messages/turns += 1
   - raw prompt tokens from input_tokens (this includes cached_input_tokens)
   - cache read from cached_input_tokens
   - normalized uncached input = max(input_tokens - cached_input_tokens, 0)
   - cache write = 0/unreported
   - output from output_tokens
   - prompt tokens for reuse math = raw input_tokens
   - total from total_tokens if present, otherwise raw input_tokens + output
   - Treat reasoning_output_tokens as included in output/total unless the schema clearly says otherwise; mention this in notes.
10. For each deduplicated Claude assistant response, add:
   - messages/turns += 1
   - uncached input from usage.input_tokens
   - cache read from usage.cache_read_input_tokens
   - cache write from usage.cache_creation_input_tokens
   - output from usage.output_tokens
   - prompt tokens for reuse math = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
   - total = prompt tokens + output_tokens
   - If usage.iterations exists, do not add it separately; it is a breakdown of the same top-level usage.
11. Compute Reported Reuse per source/model group as cache read divided by total prompt tokens, using only records that report cache fields. Format as one decimal percentage. A present zero is 0.0%; if no record reports cache fields, show "unreported". If only some records report them, calculate from those records and disclose partial coverage in Pricing notes. Sanity fixture: 200 uncached + 800 cache read + 0 cache write = 1,000 prompt tokens = 80.0% reported reuse; the equivalent Codex raw record is input_tokens=1,000 and cached_input_tokens=800.
12. Fetch/read pricing from models.dev for each model without loading the entire https://models.dev/api.json response into the agent context. IMPORTANT: do not scrape or paste the raw full api.json payload into the conversation because it is very large and can exceed the context window. Instead, use a shell script to fetch/process it outside the conversation and print only the small matched pricing records needed for the models present in the sessions. For example, use curl with a normal browser user-agent and jq/python to filter provider/model keys locally, or use targeted web search snippets. Prefer exact provider/model matches, and document any fuzzy mapping assumptions.
13. If fetching https://models.dev/api.json directly returns 403, try a browser-like User-Agent header from the shell, or use targeted search/scrape pages. Still only emit the filtered pricing rows for relevant models, never the full API JSON.
14. Compute price from normalized token counts and models.dev rates. Be careful about units: most prices are per 1M tokens. Charge normal input, cache-read, cache-write/creation, and output at their respective rates when available. Never price cached tokens again as normal input. If a rate is unavailable, use 0 for that component and add a note.
15. Present the result as concise Markdown:
   - One section per window: Last 1 day, Last 7 days, Last 30 days, Last 90 days
   - A table with columns: Source, Model, Messages/Turns, Input, Output, Cache Read, Cache Write, Reported Reuse, Total Tokens, Price
   - A total row at the bottom of each table
   - Format token counts with commas and USD with 4 decimal places unless larger amounts warrant 2 decimals.
16. Add a short "Pricing notes" section listing models.dev lookup date, unmatched models, assumptions, cache-field coverage, source-specific reuse denominators, Pi nested-tool usage counts, Claude deduplication counts, Codex parsing assumptions, and skipped/invalid session lines if any.

Helpful implementation hint:
- It is fine to write a temporary script in /tmp or use node/python from the shell to parse ~/.pi/agent/sessions/**/*.jsonl.
- For models.dev pricing, prefer a script that downloads/parses/filter-matches outside agent context and prints only compact JSON or table rows for relevant models. Avoid tool calls that return the complete api.json markdown/content to the agent.
- Do not modify any session files.`;

export default function (pi: ExtensionAPI) {
	pi.registerCommand("usage", {
		description:
			"Summarize Pi, Codex CLI, and Claude usage and cost for the last 1, 7, 30, and 90 days",
		handler: async (_args, ctx) => {
			await ctx.waitForIdle();
			pi.sendUserMessage(USAGE_PROMPT);
		},
	});
}
