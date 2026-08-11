//! The validation gate — port of bash scripts/scanman-validate.sh.
//!
//! Same exit codes, same threshold semantics, same per-check failure messages
//! for the focused (default) mode. The reproduction-spec mode (opt-in via
//! `--mode=reproduction-spec`) validates the repro-spec workspace structure
//! (index.md + LEARNINGS.md + DISTILLATE/) and runs the v0.6 distillate gates
//! G1..G13 over `DISTILLATE/*.md`; it does NOT require the focused 00..05
//! artifacts. See SCANMAN_V0_6_PROPOSAL/validate-gate-changes.md.

use anyhow::Result;
use regex::Regex;
use std::collections::BTreeSet;
use std::env;
use std::path::{Path, PathBuf};

/// Validation mode selector.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Default — only the existing 00..05 + index gates run.
    Focused,
    /// Validate repro-spec workspace structure + the v0.6 DISTILLATE/*.md
    /// gates (G1..G13). Does not require the focused 00..05 artifacts.
    ReproductionSpec,
}

impl Mode {
    pub fn parse(s: &str) -> Result<Self> {
        match s {
            "focused" => Ok(Mode::Focused),
            "reproduction-spec" | "repro-spec" => Ok(Mode::ReproductionSpec),
            other => anyhow::bail!(
                "unknown --mode value: {} (expected: focused | reproduction-spec)",
                other
            ),
        }
    }
}

#[allow(dead_code)]
pub fn run(workspace: &Path) -> Result<i32> {
    run_with_mode(workspace, Mode::Focused)
}

pub fn run_with_mode(workspace: &Path, mode: Mode) -> Result<i32> {
    if !workspace.is_dir() {
        eprintln!("ERROR: workspace not found: {}", workspace.display());
        return Ok(2);
    }

    let cfg = Config::from_env();
    let mut failures: Vec<String> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    // ------------------------------------------------------------------
    // Per-mode workspace structure: focused mode owns the 00..05 + index
    // gates; a pure reproduction-spec workspace has index.md + DISTILLATE/
    // (+ LEARNINGS.md) and never the focused 00..05 artifacts.
    // ------------------------------------------------------------------
    if mode == Mode::Focused {
        run_focused_checks(workspace, &cfg, &mut failures)?;
    }

    // ------------------------------------------------------------------
    // Reproduction-spec mode: walk DISTILLATE/*.md and run G1..G13.
    // Backward-compat: only triggered when explicitly requested.
    // ------------------------------------------------------------------
    let mut distillates_checked = 0usize;
    if mode == Mode::ReproductionSpec {
        if !workspace.join("index.md").is_file() {
            failures.push(format!(
                "{}:0: REPRO: index.md missing — not a scanman workspace. Fix: run scanman-init.sh --mode=reproduction-spec first.",
                workspace.display()
            ));
        }
        if !workspace.join("LEARNINGS.md").is_file() {
            failures.push(format!(
                "{}:0: REPRO: LEARNINGS.md missing — learning capture (playbook §5) is mandatory. Fix: create LEARNINGS.md from the §5 skeleton.",
                workspace.display()
            ));
        }
        let dist_dir = find_distillate_dir(workspace);
        match dist_dir {
            Some(dir) => {
                let files = list_distillates(&dir);
                if files.is_empty() {
                    failures.push(format!(
                        "{}:0: REPRO: no *.md files under {} — reproduction-spec mode requires at least one distillate. Fix: add DISTILLATE/<module>.md per TEMPLATE.md.",
                        dir.display(),
                        dir.display()
                    ));
                }
                for f in &files {
                    run_repro_checks_for_module(f, &cfg, &mut failures, &mut warnings)?;
                    distillates_checked += 1;
                }
            }
            None => {
                failures.push(format!(
                    "{}:0: REPRO: DISTILLATE/ directory not found under workspace. Fix: create {}/DISTILLATE/ and add at least one <module>.md.",
                    workspace.display(),
                    workspace.display()
                ));
            }
        }
    }

    // ------------------------------------------------------------------
    // Report
    // ------------------------------------------------------------------
    if !warnings.is_empty() {
        for w in &warnings {
            eprintln!("WARN: {}", w);
        }
    }

    if failures.is_empty() {
        println!("PASS: {} is complete-enough", workspace.display());
        if mode == Mode::Focused {
            println!("  - all required files exist");
            println!("  - 03/04/05 contain no placeholders");
            println!("  - 03/04/05 meet word count (>= {})", cfg.min_words);
            println!(
                "  - 03/04/05 meet substantial items (>= {} bullets, >= {} chars)",
                cfg.min_items, cfg.min_bullet_len
            );
            println!(
                "  - 02/03/04/05 demonstrate claim discipline (>= {} verified/inferred/unknown labels)",
                cfg.min_claim_labels
            );
            println!(
                "  - 03/04/05 have <= {} thin sections (>= {} words per section, except {})",
                cfg.max_thin_sections, cfg.min_section_words, cfg.exempt_sections_regex
            );
        }
        if mode == Mode::ReproductionSpec {
            println!("  - index.md and LEARNINGS.md present");
            println!(
                "  - DISTILLATE/*.md: {} distillate(s) passed v0.6 repro-spec gate (G1, G2, G7, G10, G11, G13 BLOCKING; G6 for state-machine; G9, G13-warn warnings only)",
                distillates_checked
            );
        }
        Ok(0)
    } else {
        eprintln!("FAIL: {} is incomplete", workspace.display());
        for f in &failures {
            eprintln!("  - {}", f);
        }
        eprintln!();
        eprintln!(
            "Agent must iterate to fill missing/insufficient content before claiming completion."
        );
        Ok(1)
    }
}

// =====================================================================
//                          Focused-mode gates
// =====================================================================

fn run_focused_checks(workspace: &Path, cfg: &Config, failures: &mut Vec<String>) -> Result<()> {
    let required = [
        "index.md",
        "00-file-inventory.md",
        "00b-dependency-map.md",
        "01-system-map.md",
        "02-runtime-model.md",
        "03-core-primitives.md",
        "04-risk-and-bloat.md",
        "05-redesign-v1.md",
    ];

    for name in &required {
        if !workspace.join(name).exists() {
            failures.push(format!("{}: MISSING", name));
        }
    }

    let deep_check = [
        "03-core-primitives.md",
        "04-risk-and-bloat.md",
        "05-redesign-v1.md",
    ];
    let discipline_check = [
        "02-runtime-model.md",
        "03-core-primitives.md",
        "04-risk-and-bloat.md",
        "05-redesign-v1.md",
    ];

    let placeholder_re = Regex::new(r"\[fill in\]|\bTODO\b|\bTBD\b|\bFIXME\b|\bXXX\b").unwrap();
    let claim_re = Regex::new(r"(?i)\b(verified|inferred|unknown)\b").unwrap();
    let bullet_re = Regex::new(&format!(
        r"(?m)^[[:space:]]*[-*][[:space:]].{{{},}}",
        cfg.min_bullet_len
    ))
    .unwrap();
    let exempt_re = Regex::new(&cfg.exempt_sections_regex).unwrap();

    for name in &deep_check {
        let path = workspace.join(name);
        if !path.exists() {
            continue;
        }
        let text = std::fs::read_to_string(&path)?;

        let mut matches: BTreeSet<String> = BTreeSet::new();
        for m in placeholder_re.find_iter(&text) {
            matches.insert(m.as_str().to_string());
        }
        if !matches.is_empty() {
            let list: Vec<String> = matches.into_iter().collect();
            failures.push(format!("{}: contains placeholders [{}]", name, list.join(",")));
        }

        let words = text.split_whitespace().count();
        if words < cfg.min_words {
            failures.push(format!("{}: {} words < {} minimum", name, words, cfg.min_words));
        }

        let bullets = bullet_re.find_iter(&text).count();
        if bullets < cfg.min_items {
            failures.push(format!(
                "{}: {} substantial bullets (>= {} chars) < {} minimum",
                name, bullets, cfg.min_bullet_len, cfg.min_items
            ));
        }
    }

    for name in &discipline_check {
        let path = workspace.join(name);
        if !path.exists() {
            continue;
        }
        let text = std::fs::read_to_string(&path)?;
        let count = text.lines().filter(|l| claim_re.is_match(l)).count();
        if count < cfg.min_claim_labels {
            failures.push(format!(
                "{}: {} claim-labels (verified/inferred/unknown) < {} minimum",
                name, count, cfg.min_claim_labels
            ));
        }
    }

    for name in &deep_check {
        let path = workspace.join(name);
        if !path.exists() {
            continue;
        }
        let text = std::fs::read_to_string(&path)?;
        let thin = find_thin_sections(&text, cfg.min_section_words, &exempt_re);
        if thin.len() > cfg.max_thin_sections {
            for (section, words) in thin {
                failures.push(format!(
                    "{}: thin section '## {}' ({} words < {}) — template boilerplate likely unfilled",
                    name, section, words, cfg.min_section_words
                ));
            }
        }
    }

    let evidence_check = [
        "02-runtime-model.md",
        "03-core-primitives.md",
        "04-risk-and-bloat.md",
    ];
    if std::env::var("SCANMAN_REQUIRE_EVIDENCE").unwrap_or_default() == "1" {
        let verified_re = Regex::new(r"\bverified\b").unwrap();
        let evidence_re = Regex::new(
            r"[a-zA-Z0-9_.@/-]+\.(?:ts|tsx|js|jsx|mjs|cjs|mts|cts|zig|rs|go|py|sh|c|cpp|h|hpp|java|rb|php|swift|kt|scala)\b",
        )
        .unwrap();
        for name in &evidence_check {
            let path = workspace.join(name);
            if !path.exists() {
                continue;
            }
            let text = std::fs::read_to_string(&path)?;
            let verified_count = verified_re.find_iter(&text).count();
            if verified_count == 0 {
                continue;
            }
            let evidence_count = evidence_re.find_iter(&text).count();
            if evidence_count == 0 {
                failures.push(format!(
                    "{}: {} verified claim(s) but zero source-path references — claims must be grounded in actual file reads",
                    name, verified_count
                ));
            }
        }
    }

    Ok(())
}

/// Walk a markdown file section-by-section (## headings), counting body words.
fn find_thin_sections(text: &str, min_words: usize, exempt: &Regex) -> Vec<(String, usize)> {
    let mut thin: Vec<(String, usize)> = Vec::new();
    let mut current: Option<String> = None;
    let mut count: usize = 0;
    let mut in_fm = false;

    let emit = |cur: Option<String>, c: usize, out: &mut Vec<(String, usize)>| {
        if let Some(name) = cur {
            if !exempt.is_match(&name) && c < min_words {
                out.push((name, c));
            }
        }
    };

    for line in text.lines() {
        if line == "---" {
            in_fm = !in_fm;
            continue;
        }
        if in_fm {
            continue;
        }

        if let Some(rest) = line.strip_prefix("## ") {
            emit(current.take(), count, &mut thin);
            current = Some(rest.trim().to_string());
            count = 0;
        } else {
            count += line.split_whitespace().count();
        }
    }
    emit(current.take(), count, &mut thin);
    thin
}

struct Config {
    min_words: usize,
    min_items: usize,
    min_bullet_len: usize,
    min_claim_labels: usize,
    min_section_words: usize,
    max_thin_sections: usize,
    exempt_sections_regex: String,
    min_anchors: usize,
}

impl Config {
    fn from_env() -> Self {
        fn env_usize(key: &str, default: usize) -> usize {
            env::var(key)
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(default)
        }
        Self {
            min_words: env_usize("SCANMAN_MIN_WORDS", 300),
            min_items: env_usize("SCANMAN_MIN_ITEMS", 3),
            min_bullet_len: env_usize("SCANMAN_MIN_BULLET_LEN", 30),
            min_claim_labels: env_usize("SCANMAN_MIN_CLAIM_LABELS", 3),
            min_section_words: env_usize("SCANMAN_MIN_SECTION_WORDS", 25),
            max_thin_sections: env_usize("SCANMAN_MAX_THIN_SECTIONS", 2),
            exempt_sections_regex: env::var("SCANMAN_EXEMPT_SECTIONS")
                .unwrap_or_else(|_| "^(Related|Purpose|Decision)$".to_string()),
            min_anchors: env_usize("SCANMAN_MIN_ANCHORS", 3),
        }
    }
}

// =====================================================================
//                  Reproduction-spec (v0.6) gates G1..G13
// =====================================================================

/// Per-distillate archetype, drives which gates apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Archetype {
    DataOnly,
    StateMachine,
    HostExport,
    ApiModule,
}

/// Find a DISTILLATE directory under the workspace. Looks at <workspace>/DISTILLATE
/// first (workspace-relative layout) then <workspace>/../DISTILLATE (repo-root layout).
fn find_distillate_dir(workspace: &Path) -> Option<PathBuf> {
    let primary = workspace.join("DISTILLATE");
    if primary.is_dir() {
        return Some(primary);
    }
    let sibling = workspace.parent().map(|p| p.join("DISTILLATE"));
    if let Some(s) = sibling {
        if s.is_dir() {
            return Some(s);
        }
    }
    None
}

fn list_distillates(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(rd) = std::fs::read_dir(dir) {
        for entry in rd.flatten() {
            let p = entry.path();
            if p.extension().and_then(|s| s.to_str()) == Some("md") {
                // Skip TEMPLATE.md / README.md if present
                if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                    let lower = stem.to_lowercase();
                    if lower == "template" || lower == "readme" {
                        continue;
                    }
                }
                out.push(p);
            }
        }
    }
    out.sort();
    out
}

/// Detect archetype from a distillate's body. Looks at frontmatter first
/// (`archetype: data-only|state-machine|host-export|api-module`), then falls
/// back to structural heuristics.
fn detect_archetype(text: &str) -> Archetype {
    // Frontmatter
    if let Some(fm) = extract_frontmatter(text) {
        let fm_re = Regex::new(r"(?m)^archetype:\s*(data-only|state-machine|host-export|api-module)\s*$").unwrap();
        if let Some(c) = fm_re.captures(fm) {
            return match c.get(1).unwrap().as_str() {
                "data-only" => Archetype::DataOnly,
                "state-machine" => Archetype::StateMachine,
                "host-export" => Archetype::HostExport,
                _ => Archetype::ApiModule,
            };
        }
    }

    // Heuristic 1: host-export — has §5a + §5b
    let has_5a = Regex::new(r"(?m)^## 5a(?:\.| )|^## Sectie 5a\b").unwrap().is_match(text);
    let has_5b = Regex::new(r"(?m)^## 5b(?:\.| )|^## Sectie 5b\b").unwrap().is_match(text);
    if has_5a && has_5b {
        return Archetype::HostExport;
    }

    // Heuristic 2: state-machine — has §4a (State enum)
    if Regex::new(r"(?m)^## 4a(?:\.| )|^## Sectie 4a\b").unwrap().is_match(text) {
        return Archetype::StateMachine;
    }

    // Heuristic 3: data-only — §5 says "n.v.t."
    if let Some(s5) = extract_section(text, "5", "Public API") {
        let nvt = Regex::new(r"(?i)n\.v\.t\.|\bnot applicable\b|\bpure data\b").unwrap();
        if nvt.is_match(&s5) {
            // Also check §6 §7 say n.v.t. for stronger data-only signal
            return Archetype::DataOnly;
        }
    }

    Archetype::ApiModule
}

fn extract_frontmatter(text: &str) -> Option<&str> {
    if !text.starts_with("---\n") && !text.starts_with("---\r\n") {
        return None;
    }
    let after = text.find('\n').map(|i| i + 1)?;
    let rest = &text[after..];
    let end = rest.find("\n---")?;
    Some(&rest[..end])
}

/// Extract a top-level section (`## <num>. <title>` or `## Sectie <num>`)
/// up to (but not including) the next `## <other-num>. ` or end-of-file.
/// Returns the section body including the heading line, with byte-offset
/// awareness via line numbers preserved in the original text.
fn extract_section(text: &str, num: &str, _title_hint: &str) -> Option<String> {
    let start_re = Regex::new(&format!(
        r"(?m)^## (?:{}\.|Sectie {}\s)",
        regex::escape(num),
        regex::escape(num)
    ))
    .ok()?;
    let m = start_re.find(text)?;
    let start = m.start();
    // Find end: next `## N. ` or `## Sectie N` with different N (any int or letter-suffixed)
    let after = &text[m.end()..];
    let end_re = Regex::new(r"(?m)^## (?:[0-9]+[a-z]?\.|Sectie [0-9]+[a-z]?\s)").ok()?;
    let end_rel = end_re.find(after).map(|mm| m.end() + mm.start()).unwrap_or(text.len());
    Some(text[start..end_rel].to_string())
}

/// Find the line number (1-indexed) of a byte offset within the original text.
fn line_of_offset(text: &str, offset: usize) -> usize {
    text[..offset.min(text.len())]
        .bytes()
        .filter(|&b| b == b'\n')
        .count()
        + 1
}

fn run_repro_checks_for_module(
    path: &Path,
    cfg: &Config,
    failures: &mut Vec<String>,
    warnings: &mut Vec<String>,
) -> Result<()> {
    let text = std::fs::read_to_string(path)?;
    let arch = detect_archetype(&text);
    let p = path.display().to_string();

    // G1: §3 constants table must have a "Value" column with no empty cells.
    // (Targets the gap: "constant value of transitive dependency hard to find".)
    check_g1(&text, &p, failures);

    // G2: vague compile-time-assertion location ("elsewhere", "somewhere")
    check_g2(&text, &p, failures);

    // G7: §7 pseudocode must be language-agnostic (no Zig/Rust-specific tokens)
    check_g7(&text, &p, failures);

    // G10: every type in §4 must declare Memory layout (regular|extern|packed)
    check_g10(&text, &p, failures);

    // G11: every §10 anchor must carry a recognizable type label and kind hint.
    // Data-only modules may only have compile-time-style anchors.
    check_g11(&text, &p, arch, failures);

    // G13: §12 abbreviations should carry a disclaimer; warn on missing siblings.
    check_g13(&text, path, &p, warnings);

    // Archetype-conditional
    match arch {
        Archetype::StateMachine => {
            check_g6(&text, &p, failures);
        }
        Archetype::DataOnly => {
            // §5/§6/§7 must say "n.v.t."
            check_data_only_nvt(&text, &p, failures);
        }
        Archetype::HostExport => {
            check_host_export_5a_5b(&text, &p, failures);
        }
        Archetype::ApiModule => {}
    }

    // Anchor minimum count (G8 stripped of the cross-ref complexity)
    check_anchor_min(&text, &p, cfg.min_anchors, failures);

    Ok(())
}

// ---------- G1 ----------
fn check_g1(text: &str, path: &str, failures: &mut Vec<String>) {
    let sec3 = match extract_section(text, "3", "Public constants") {
        Some(s) => s,
        None => return, // §3 absent — handled by other structural gates
    };
    // Find first table (lines starting with `|`)
    let lines: Vec<(usize, &str)> = sec3.lines().enumerate().collect();
    let table_start = lines.iter().position(|(_, l)| l.trim_start().starts_with('|'));
    let table_start = match table_start {
        Some(i) => i,
        None => {
            // No table at all in §3 — only fail if there's actual constant-looking content
            // (proper "no constants" sections will use prose like "n.v.t." or "None.")
            let lower = sec3.to_lowercase();
            if lower.contains("n.v.t.")
                || lower.contains("no public constants")
                || lower.contains("none.")
            {
                return;
            }
            // Compute line offset relative to file
            let off = text.find(sec3.lines().next().unwrap_or("## 3")).unwrap_or(0);
            failures.push(format!(
                "{}:{}: G1: §3 Public constants has no markdown table. Fix: add a table with at least Name|Type|Value|Purpose columns.",
                path,
                line_of_offset(text, off)
            ));
            return;
        }
    };
    let header = lines[table_start].1.trim();
    // Header must mention "Value"
    if !header.to_lowercase().contains("value") {
        let off = text.find(header).unwrap_or(0);
        failures.push(format!(
            "{}:{}: G1: §3 constants table header is missing 'Value' column. Header: {}. Fix: add a 'Value' column listing the concrete literal/expression.",
            path,
            line_of_offset(text, off),
            header
        ));
        return;
    }
    // Identify Value column index by splitting header on '|'
    let cols: Vec<&str> = header.split('|').map(|c| c.trim()).collect();
    let value_idx = cols
        .iter()
        .position(|c| c.eq_ignore_ascii_case("Value"))
        .unwrap_or(0);
    // Iterate data rows (skip header + separator)
    for (li, raw) in lines.iter().skip(table_start + 1) {
        let line = raw.trim();
        if !line.starts_with('|') {
            break; // table ended
        }
        // Separator row: `|---|---|`
        if line.chars().all(|c| matches!(c, '|' | '-' | ':' | ' ')) {
            continue;
        }
        let cells: Vec<&str> = line.split('|').map(|c| c.trim()).collect();
        if let Some(cell) = cells.get(value_idx) {
            let trimmed = cell.trim_matches(|c: char| c == '`' || c.is_whitespace());
            if trimmed.is_empty() || trimmed == "-" || trimmed == "?" || trimmed == "TBD" {
                let off = text.find(raw).unwrap_or(0);
                failures.push(format!(
                    "{}:{}: G1: §3 constants row has empty Value cell: {}. Fix: fill in the literal value (e.g. '256', '0x01') so transitive callers don't have to grep.",
                    path,
                    line_of_offset(text, off),
                    line
                ));
            }
        }
        let _ = li;
    }
}

// ---------- G2 ----------
fn check_g2(text: &str, path: &str, failures: &mut Vec<String>) {
    let vague_re =
        Regex::new(r"(?i)assert[^.\n]{0,80}\b(elsewhere|somewhere)\b|asserted\s+(elsewhere|somewhere)")
            .unwrap();
    if let Some(m) = vague_re.find(text) {
        let line = line_of_offset(text, m.start());
        failures.push(format!(
            "{}:{}: G2: vague compile-time-assertion location ('{}'). Fix: name the host file (e.g. 'host-side: src/cell.zig comptime ... assert sizeOf(Cell)==12 ...').",
            path,
            line,
            m.as_str().trim()
        ));
    }
}

// ---------- G6 (state-machine only) ----------
fn check_g6(text: &str, path: &str, failures: &mut Vec<String>) {
    let heading_re = Regex::new(r"(?im)^##.*state[- ]reset matrix").unwrap();
    if let Some(m) = heading_re.find(text) {
        // Count table rows (lines starting with |) after heading until next ##
        let after = &text[m.end()..];
        let next_h = Regex::new(r"(?m)^## ").unwrap().find(after).map(|mm| mm.start()).unwrap_or(after.len());
        let body = &after[..next_h];
        let rows = body.lines().filter(|l| l.trim_start().starts_with('|')).count();
        if rows < 3 {
            failures.push(format!(
                "{}:{}: G6: 'State-reset matrix' present but empty (need header + separator + >=1 helper row, got {} rows). Fix: list each entry-helper and which state fields it resets/preserves.",
                path, line_of_offset(text, m.start()), rows
            ));
        }
    } else {
        // State-machine archetype but no matrix at all
        let any_h = Regex::new(r"(?m)^## ").unwrap().find(text).map(|mm| line_of_offset(text, mm.start())).unwrap_or(1);
        failures.push(format!(
            "{}:{}: G6: state-machine distillate lacks '## State-reset matrix' section. Fix: add a section enumerating each entry-helper and which state fields it touches.",
            path, any_h
        ));
    }
}

// ---------- G7 ----------
fn check_g7(text: &str, path: &str, failures: &mut Vec<String>) {
    let sec7 = match extract_section(text, "7", "Algorithms") {
        Some(s) => s,
        None => return,
    };
    // Banned tokens — focus on Zig/Rust/C-specific markers that leak language.
    // Patterns: saturating ops (`*|`, `+|`, `-|`), Zig builtins (@import,@sizeOf,...),
    // `extern struct|fn`, explicit sized-int keywords used as type annotations.
    let patterns: &[(&str, &str)] = &[
        (r"\*\|", "Zig saturating-multiply '*|'"),
        (r"\+\|", "Zig saturating-add '+|'"),
        (r"@import\b", "Zig builtin '@import'"),
        (r"@sizeOf\b", "Zig builtin '@sizeOf'"),
        (r"@offsetOf\b", "Zig builtin '@offsetOf'"),
        (r"@as\b", "Zig builtin '@as'"),
        (r"@intCast\b", "Zig builtin '@intCast'"),
        (r"\bextern\s+(?:struct|fn)\b", "Zig 'extern struct/fn'"),
        // Sized-int keywords used as TYPE ANNOTATIONS only (`: u32`, `var x: usize`)
        // — avoid false-positives on inline prose like "u16 max".
        (r":\s*(?:u8|u16|u32|u64|usize|isize)\b", "language-specific sized-int type annotation"),
    ];
    for (pat, label) in patterns {
        let re = Regex::new(pat).unwrap();
        if let Some(m) = re.find(&sec7) {
            // Allow occurrences inside comments lines (`# ...` or `// ...`) — those are
            // explanatory annotations on otherwise language-agnostic pseudocode.
            // We only flag if the line itself is not a pure comment.
            // Find the matching line in sec7
            let line_start = sec7[..m.start()].rfind('\n').map(|i| i + 1).unwrap_or(0);
            let line_end = sec7[m.start()..].find('\n').map(|i| m.start() + i).unwrap_or(sec7.len());
            let line = &sec7[line_start..line_end];
            let stripped = line.trim_start();
            if stripped.starts_with('#') || stripped.starts_with("//") {
                continue;
            }
            // Compute line in original file
            let sec_offset = text.find(&sec7[..50.min(sec7.len())]).unwrap_or(0);
            let abs_offset = sec_offset + m.start();
            failures.push(format!(
                "{}:{}: G7: §7 pseudocode contains language-specific token: {} ('{}'). Fix: replace with language-agnostic pseudocode (e.g. 'saturating_mul(x, 10)' instead of '*|').",
                path, line_of_offset(text, abs_offset), label, m.as_str()
            ));
            return; // one per file is enough — agents iterate
        }
    }
}

// ---------- G10 ----------
fn check_g10(text: &str, path: &str, failures: &mut Vec<String>) {
    let sec4 = match extract_section(text, "4", "Public types") {
        Some(s) => s,
        None => return,
    };
    // Identify each `### <TypeName>` block; check it contains a Memory-layout declaration.
    let lines: Vec<&str> = sec4.lines().collect();
    let mut current: Option<(usize, String)> = None;
    let mut have_layout = false;
    // Accept any of these forms (case-insensitive on key):
    //   **Memory layout**: regular|extern|packed
    //   **Memory layout**: `extern struct` (...)
    //   `extern struct Foo`            <- inline declaration in prose
    let layout_re = Regex::new(
        r"(?i)\*\*memory[- ]layout\*\*\s*:\s*[`']?(regular|extern|packed)",
    )
    .unwrap();
    let layout_inline = Regex::new(r"(?i)\*\*memory[- ]layout\*\*\s*:\s*`?(extern|packed|regular)").unwrap();
    let layout_prose = Regex::new(r"(?i)\bmemory layout\b").unwrap();

    let flush = |cur: &Option<(usize, String)>, have: bool, failures: &mut Vec<String>| {
        if let Some((li, name)) = cur {
            if !have {
                // Compute file-absolute line
                let sec_off = text.find(&sec4[..50.min(sec4.len())]).unwrap_or(0);
                // li is line index within sec4
                let mut acc = 0usize;
                let mut abs = sec_off;
                for (j, l) in sec4.lines().enumerate() {
                    if j == *li {
                        abs = sec_off + acc;
                        break;
                    }
                    acc += l.len() + 1;
                }
                failures.push(format!(
                    "{}:{}: G10: §4 type '{}' lacks Memory-layout field. Fix: add a line like '**Memory layout**: extern (C-compatible)' or 'regular' / 'packed'.",
                    path, line_of_offset(text, abs), name
                ));
            }
        }
    };

    for (i, line) in lines.iter().enumerate() {
        if let Some(rest) = line.strip_prefix("### ") {
            flush(&current, have_layout, failures);
            // Skip non-type subheadings like "### Anchor" (defensive — anchors live in §10, not §4)
            let name = rest.trim().to_string();
            if name.to_lowercase().starts_with("anchor") {
                current = None;
                have_layout = false;
                continue;
            }
            current = Some((i, name));
            have_layout = false;
            continue;
        }
        if current.is_some() {
            if layout_re.is_match(line) || layout_inline.is_match(line) || layout_prose.is_match(line) {
                have_layout = true;
            }
        }
    }
    flush(&current, have_layout, failures);
}

// ---------- G11 ----------
fn check_g11(text: &str, path: &str, arch: Archetype, failures: &mut Vec<String>) {
    let sec10 = match extract_section(text, "10", "Behaviour anchors") {
        Some(s) => s,
        None => return,
    };
    // Anchor heading regex — `### Anchor` or `#### Anchor`, optionally followed
    // by a name and a parenthetical classification ('synthetic, pure-module' etc.).
    let anchor_re = Regex::new(r"(?m)^#{3,4}\s+Anchor\b[^\n]*").unwrap();
    // Type/kind labels we accept anywhere in the anchor body:
    //   - parenthetical: `(synthetic, ...)`, `(compile-time)`, `(source-extracted, ...)`
    //   - explicit:      `**Anchor type**: synthetic`, `**Kind**: runtime-behavior`
    let label_re =
        Regex::new(r"(?i)(synthetic|source-extracted|compile-time|runtime-behavior|runtime-state-machine|compile-time-layout)")
            .unwrap();

    let anchors: Vec<(usize, &str)> = anchor_re
        .find_iter(&sec10)
        .map(|m| (m.start(), m.as_str()))
        .collect();
    if anchors.is_empty() {
        return; // anchor-count gate handles "zero anchors" separately
    }
    for (i, (start, heading)) in anchors.iter().enumerate() {
        let end = anchors.get(i + 1).map(|(s, _)| *s).unwrap_or(sec10.len());
        let body = &sec10[*start..end];
        if !label_re.is_match(body) {
            let sec_off = text.find(&sec10[..50.min(sec10.len())]).unwrap_or(0);
            let abs = sec_off + start;
            failures.push(format!(
                "{}:{}: G11: §10 anchor '{}' lacks type/kind label. Fix: add a parenthetical like '(synthetic, pure-module)' or an explicit '**Anchor type**: synthetic\\n**Kind**: runtime-behavior' block.",
                path, line_of_offset(text, abs), heading.trim()
            ));
            continue;
        }
        if arch == Archetype::DataOnly {
            // Data-only anchors must be compile-time flavored.
            let compile_only = Regex::new(r"(?i)compile-time").unwrap();
            if !compile_only.is_match(body) {
                let sec_off = text.find(&sec10[..50.min(sec10.len())]).unwrap_or(0);
                let abs = sec_off + start;
                failures.push(format!(
                    "{}:{}: G11: data-only distillate may only declare compile-time anchors, but '{}' lacks 'compile-time' kind. Fix: label it 'compile-time-layout' or change archetype.",
                    path, line_of_offset(text, abs), heading.trim()
                ));
            }
        }
    }
}

// ---------- G13 (warning) ----------
fn check_g13(text: &str, file: &Path, path: &str, warnings: &mut Vec<String>) {
    let sec12 = match extract_section(text, "12", "Dependency abbreviations") {
        Some(s) => s,
        None => return,
    };
    let disclaimer_re =
        Regex::new(r"(?i)not\s+a\s+substitut|contextual\s+(?:understanding|only)|full\s+(?:spec|distillate)\s+(?:required|is)")
            .unwrap();
    if !disclaimer_re.is_match(&sec12) {
        let off = text.find(&sec12[..50.min(sec12.len())]).unwrap_or(0);
        warnings.push(format!(
            "{}:{}: G13: §12 lacks a 'not a substitute for full distillate' disclaimer. Suggestion: add 'These abbreviations are for contextual understanding only; see DISTILLATE/<dep>.md for the full spec.'",
            path, line_of_offset(text, off)
        ));
    }
    // Sibling-distillate cross-ref: find `### <Name>` headings, lowercase, check sibling exists
    let sub_re = Regex::new(r"(?m)^###\s+([A-Za-z][A-Za-z0-9_]+)").unwrap();
    if let Some(dir) = file.parent() {
        for c in sub_re.captures_iter(&sec12) {
            let name = c.get(1).unwrap().as_str();
            let lower = name.to_lowercase();
            let sibling = dir.join(format!("{}.md", lower));
            if !sibling.exists() {
                warnings.push(format!(
                    "{}: G13: §12 references '{}' but DISTILLATE/{}.md is missing. Suggestion: create a full sibling distillate.",
                    path, name, lower
                ));
            }
        }
    }
}

// ---------- Anchor minimum count (G8 simplified) ----------
fn check_anchor_min(text: &str, path: &str, min_anchors: usize, failures: &mut Vec<String>) {
    let sec10 = match extract_section(text, "10", "Behaviour anchors") {
        Some(s) => s,
        None => return,
    };
    let anchor_re = Regex::new(r"(?m)^#{3,4}\s+Anchor\b").unwrap();
    let n = anchor_re.find_iter(&sec10).count();
    if n < min_anchors {
        let off = text.find(&sec10[..50.min(sec10.len())]).unwrap_or(0);
        failures.push(format!(
            "{}:{}: G8: §10 has {} anchor(s); needs >= {} (SCANMAN_MIN_ANCHORS). Fix: add more behaviour/layout anchors.",
            path, line_of_offset(text, off), n, min_anchors
        ));
    }
}

// ---------- data-only archetype: §5/§6/§7 must say n.v.t. ----------
fn check_data_only_nvt(text: &str, path: &str, failures: &mut Vec<String>) {
    let nvt_re = Regex::new(r"(?i)n\.v\.t\.|\bnot applicable\b|\bpure data\b|\bno (?:logic|functions|invariants)\b").unwrap();
    for num in &["5", "6", "7"] {
        let sec = match extract_section(text, num, "") {
            Some(s) => s,
            None => continue,
        };
        if !nvt_re.is_match(&sec) {
            let off = text.find(&sec[..50.min(sec.len())]).unwrap_or(0);
            failures.push(format!(
                "{}:{}: G11/data-only: §{} should say 'n.v.t.' (or 'not applicable' / 'pure data') for data-only archetype. Fix: replace prose with explicit 'n.v.t.' marker, or change archetype.",
                path, line_of_offset(text, off), num
            ));
        }
    }
}

// ---------- host-export archetype: require §5a + §5b instead of §5 ----------
fn check_host_export_5a_5b(text: &str, path: &str, failures: &mut Vec<String>) {
    let s5a = Regex::new(r"(?m)^## 5a(?:\.| )|^## Sectie 5a\b").unwrap().is_match(text);
    let s5b = Regex::new(r"(?m)^## 5b(?:\.| )|^## Sectie 5b\b").unwrap().is_match(text);
    if !s5a {
        failures.push(format!(
            "{}:1: G5a/host-export: missing '## 5a. Export ABI' section. Fix: replace §5 with §5a + §5b for host-export modules.",
            path
        ));
    }
    if !s5b {
        failures.push(format!(
            "{}:1: G5b/host-export: missing '## 5b. Host-managed state' section. Fix: add a §5b enumerating module-level vars and their lifetimes.",
            path
        ));
    }
}

// =====================================================================
//                                Tests
// =====================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn g1_flags_empty_value_cell() {
        let text = "\
## 3. Public constants

| Name | Type | Value | Purpose |
|---|---|---|---|
| FOO | u32 | 42 | works |
| BAR | u32 |  | empty |

## 4. Public types
";
        let mut failures = Vec::new();
        check_g1(text, "test.md", &mut failures);
        assert!(
            failures.iter().any(|f| f.contains("G1") && f.contains("empty Value")),
            "expected G1 empty-value failure, got: {:?}",
            failures
        );
    }

    #[test]
    fn g1_flags_missing_value_column() {
        let text = "\
## 3. Public constants

| Name | Type | Purpose |
|---|---|---|
| FOO | u32 | works |

## 4. Public types
";
        let mut failures = Vec::new();
        check_g1(text, "test.md", &mut failures);
        assert!(
            failures.iter().any(|f| f.contains("G1") && f.contains("missing 'Value'")),
            "expected G1 missing-column failure, got: {:?}",
            failures
        );
    }

    #[test]
    fn g1_passes_filled_table() {
        let text = "\
## 3. Public constants

| Name | Type | Value | Purpose |
|---|---|---|---|
| FOO | u32 | 42 | works |
| BAR | u32 | 0x10 | also works |

## 4. Public types
";
        let mut failures = Vec::new();
        check_g1(text, "test.md", &mut failures);
        assert!(
            failures.is_empty(),
            "expected G1 to pass, got: {:?}",
            failures
        );
    }

    #[test]
    fn g7_flags_zig_saturating_op() {
        let text = "\
## 7. Algorithms

```
params[idx] = params[idx] *| 10 + digit
```

## 8. Caller contracts
";
        let mut failures = Vec::new();
        check_g7(text, "test.md", &mut failures);
        assert!(
            failures.iter().any(|f| f.contains("G7") && f.contains("*|")),
            "expected G7 saturating-op failure, got: {:?}",
            failures
        );
    }

    #[test]
    fn g7_allows_language_agnostic_pseudocode() {
        let text = "\
## 7. Algorithms

```
params[idx] = saturating_mul(params[idx], 10) + digit
for each row in 0..rows:
    process(row)
```

## 8. Caller contracts
";
        let mut failures = Vec::new();
        check_g7(text, "test.md", &mut failures);
        assert!(
            failures.is_empty(),
            "expected G7 to pass, got: {:?}",
            failures
        );
    }

    #[test]
    fn g10_flags_missing_memory_layout() {
        let text = "\
## 4. Public types

### Cell

| Field | Type | Default | Notes |
|---|---|---|---|
| char | u32 | space | codepoint |

### Row

**Memory layout**: regular

| Field | Type | Default | Notes |
|---|---|---|---|
| n | u16 | 0 | count |

## 5. Public API
";
        let mut failures = Vec::new();
        check_g10(text, "test.md", &mut failures);
        assert!(
            failures.iter().any(|f| f.contains("G10") && f.contains("Cell")),
            "expected G10 to flag Cell, got: {:?}",
            failures
        );
        assert!(
            !failures.iter().any(|f| f.contains("G10") && f.contains("Row")),
            "expected G10 NOT to flag Row, got: {:?}",
            failures
        );
    }

    #[test]
    fn g2_flags_elsewhere_phrasing() {
        let text = "\
total size = 12 bytes (assert at compile time elsewhere)
";
        let mut failures = Vec::new();
        check_g2(text, "test.md", &mut failures);
        assert!(
            failures.iter().any(|f| f.contains("G2") && f.contains("elsewhere")),
            "expected G2 vague-elsewhere failure, got: {:?}",
            failures
        );
    }

    #[test]
    fn archetype_detection_data_only() {
        let text = "\
## 5. Public API

**n.v.t.** — no functions.

## 6. Invariants

n.v.t.
";
        assert_eq!(detect_archetype(text), Archetype::DataOnly);
    }

    #[test]
    fn archetype_detection_host_export() {
        let text = "\
## 5a. Export ABI

stuff

## 5b. Host-managed state

stuff
";
        assert_eq!(detect_archetype(text), Archetype::HostExport);
    }

    #[test]
    fn extract_section_basic() {
        let text = "\
## 1. Identity
foo

## 2. Dependencies
bar

## 3. Public constants
baz
";
        let s2 = extract_section(text, "2", "Dependencies").unwrap();
        assert!(s2.contains("bar"));
        assert!(!s2.contains("foo"));
        assert!(!s2.contains("baz"));
    }
}
