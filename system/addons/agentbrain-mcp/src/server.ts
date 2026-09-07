#!/usr/bin/env bun
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { canonRel } from "./brain";
import { search, read, recent, rules } from "./search";
import { recordAccess } from "./access";
import { saveLearning, projectUpdate } from "./write";
import { listFindings } from "./findings";
import { status } from "./status";

const server = new Server(
  { name: "agentbrain", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

const TOOLS = [
  {
    name: "brain_search",
    description:
      "Search agentBrain notes by content or path. Returns matches with title + snippet. " +
      "Matching is lexical (words, not meaning): before searching, enrich the query with " +
      "synonyms and domain terms for the concept, not just the literal word — a query for " +
      "'verwijderen' will not find a note that only says 'opschonen' unless you include it.",
    inputSchema: { type: "object", properties: { query: { type: "string" }, limit: { type: "number" } }, required: ["query"] },
  },
  {
    name: "brain_read",
    description: "Read a note's full content by brain-relative path (e.g. system/rules.md).",
    inputSchema: { type: "object", properties: { path: { type: "string" } }, required: ["path"] },
  },
  {
    name: "brain_recent",
    description: "List the most-recently-modified notes (default 10).",
    inputSchema: { type: "object", properties: { n: { type: "number" } } },
  },
  {
    name: "brain_rules",
    description: "Return the brain's rules + skills index (HOW/WHERE conventions).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "brain_save_learning",
    description: "Save a durable learning into local/learnings/ (frontmatter + UUID5 added).",
    inputSchema: { type: "object", properties: { title: { type: "string" }, body: { type: "string" }, tags: { type: "array", items: { type: "string" } } }, required: ["title", "body"] },
  },
  {
    name: "brain_project_update",
    description: "Create/update a project note under local/projects/<name>/ (index.md or a named section).",
    inputSchema: { type: "object", properties: { name: { type: "string" }, section: { type: "string" }, body: { type: "string" } }, required: ["name", "body"] },
  },
  {
    name: "brain_status",
    description: "Read-only framework status: active checkout, version (git describe), release, update channel/mode/auto_update. Lifecycle mutations (update, wire, doctor) stay on the host's brain CLI.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "brain_findings_list",
    description: "List structured detector findings from local/findings/<detector>.json. Optional filters: detector (e.g. 'check-vault-content'), severity ('error'|'warning'|'info'|'opportunity'), status ('open'|'auto_closed'). No filter = aggregated across all detectors.",
    inputSchema: { type: "object", properties: { detector: { type: "string" }, severity: { type: "string" }, status: { type: "string" } } },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name } = req.params;
  const a = (req.params.arguments ?? {}) as Record<string, any>;
  const text = (s: string) => ({ content: [{ type: "text", text: s }] });
  try {
    switch (name) {
      case "brain_search": return text(JSON.stringify(await search(a.query, a.limit), null, 2));
      case "brain_read": {
        const content = await read(canonRel(a.path));
        // Ranking hint only — a failed counter must never turn a good read into an error.
        try { recordAccess(canonRel(a.path)); } catch { /* ignore */ }
        return text(content);
      }
      case "brain_recent": return text(JSON.stringify(await recent(a.n), null, 2));
      case "brain_rules": return text(await rules());
      case "brain_save_learning": return text(`Saved: ${await saveLearning(a.title, a.body, a.tags)}`);
      case "brain_project_update": return text(`Updated: ${await projectUpdate(a.name, a.section, a.body)}`);
      case "brain_status": return text(JSON.stringify(await status(), null, 2));
      case "brain_findings_list": return text(JSON.stringify(await listFindings({ detector: a.detector, severity: a.severity, status: a.status }), null, 2));
      default: return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
    }
  } catch (e: any) {
    return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
  }
});

await server.connect(new StdioServerTransport());
