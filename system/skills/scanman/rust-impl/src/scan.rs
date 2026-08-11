//! `scan` subcommand — port of bash scripts/scanman-scan.sh.
//!
//! Generates bootstrap layers 00/00b/01/02 by walking the target repo,
//! parsing package.json files, and scanning imports in hotspot source files.
//! Preserves existing YAML frontmatter on every write.

use crate::frontmatter;
use crate::init::find_agentbrain_dir;
use anyhow::{Context, Result};
use ignore::WalkBuilder;
use regex::Regex;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

pub fn run(repo_path: &Path, slug: &str) -> Result<()> {
    let repo_path = repo_path
        .canonicalize()
        .with_context(|| format!("canonicalize {}", repo_path.display()))?;
    let agentbrain_dir = find_agentbrain_dir()?;
    let target = agentbrain_dir
        .join("local/research/repo-distill")
        .join(slug);

    if !target.is_dir() {
        anyhow::bail!(
            "Scanman target missing: {}\nRun: scanman init {} '{}'",
            target.display(),
            slug,
            repo_path.display()
        );
    }

    let version = fs::read_to_string(
        agentbrain_dir.join("system/skills/scanman/VERSION"),
    )
    .map(|s| s.trim().to_string())
    .unwrap_or_else(|_| "unknown".to_string());

    let inv = inventory(&repo_path, slug)?;

    // Write inventory snapshot (matches bash `find ... > /tmp/<slug>-...txt`)
    let snapshot_path = std::env::temp_dir().join(format!("{}-scanman-file-inventory.txt", slug));
    fs::write(&snapshot_path, inv.paths_text())?;

    // 00-file-inventory.md
    let inv_md = render_inventory_md(&inv);
    write_preserving_frontmatter(&target.join("00-file-inventory.md"), &inv_md)?;

    // 00b-dependency-map.md
    let dep_md = render_dependency_md(&inv);
    write_preserving_frontmatter(&target.join("00b-dependency-map.md"), &dep_md)?;

    // 01-system-map.md (only if no enriched preserve)
    let system_path = target.join("01-system-map.md");
    if !is_enriched(&system_path) {
        let sys_md = render_system_md(&inv);
        write_preserving_frontmatter(&system_path, &sys_md)?;
    }

    // 02-runtime-model.md (only if no enriched preserve)
    let runtime_path = target.join("02-runtime-model.md");
    if !is_enriched(&runtime_path) {
        let rt_md = render_runtime_md();
        write_preserving_frontmatter(&runtime_path, &rt_md)?;
    }

    // Index touch-up: reconcile method version + checkboxes + stack-detection lines.
    touch_index(&target.join("index.md"), &inv, &version)?;

    println!("Generated scanman bootstrap files:");
    println!("  {}", target.join("00-file-inventory.md").display());
    println!("  {}", target.join("00b-dependency-map.md").display());
    println!("Inventory snapshot: {}", snapshot_path.display());

    Ok(())
}

/// Inventory of the analyzed repo: paths, packages, languages, frameworks, etc.
struct Inventory {
    repo: PathBuf,
    /// Workspace slug — used as the root label in tree displays (matches bash).
    slug: String,
    /// All inventoried paths, relative to repo root (sorted)
    paths: Vec<String>,
    /// Counts per top-level directory: (files, code_files)
    top_counts: BTreeMap<String, (usize, usize)>,
    /// Package manifests discovered
    packages: Vec<PackageInfo>,
    /// Detected languages with counts
    languages: Vec<(String, usize)>,
    /// Detected frameworks/tooling
    frameworks: Vec<String>,
    /// Likely entrypoint files (priority names)
    entrypoints: Vec<String>,
    /// Hotspot files by import-count, sorted descending
    hotspots: Vec<(usize, String)>,
    /// Tree entries with marker showing whether they are directories.
    /// Each entry is (relative_path, is_directory).
    tree_entries: Vec<(String, bool)>,
    /// State/storage candidate directories present
    state_dirs: Vec<String>,
}

impl Inventory {
    fn paths_text(&self) -> String {
        let mut s = self.paths.join("\n");
        s.push('\n');
        s
    }
}

struct PackageInfo {
    name: String,
    path: String,
    deps: Vec<String>,
}

#[derive(Deserialize)]
struct PackageJson {
    name: Option<String>,
    #[serde(default)]
    dependencies: BTreeMap<String, String>,
}

const CODE_EXTS: &[&str] = &[".ts", ".js", ".cjs", ".mjs", ".md", ".json", ".sh"];
const EXCLUDE_DIRS: &[&str] = &["node_modules", ".git", "dist", "build", "coverage"];
const PRIORITY_ENTRYPOINTS: &[&str] = &[
    "main.ts", "main.js", "index.ts", "index.js", "server.ts", "server.js", "app.ts", "app.js",
    "page.tsx", "page.jsx", "cli.ts", "cli.js",
];

fn inventory(repo: &Path, slug: &str) -> Result<Inventory> {
    let mut paths: Vec<String> = Vec::new();
    let mut top_counts: BTreeMap<String, (usize, usize)> = BTreeMap::new();
    let mut entrypoints: Vec<String> = Vec::new();
    let mut source_files: Vec<PathBuf> = Vec::new();
    // Track tree entries with their directory-or-file flag (matches bash's `is_dir` check)
    let mut tree_set: BTreeMap<String, bool> = BTreeMap::new();
    let mut package_paths: Vec<PathBuf> = Vec::new();

    // Walk respecting standard filters but with our extra exclude list as a custom matcher.
    let walker = WalkBuilder::new(repo)
        .hidden(false) // include .github etc. (matches bash behavior; we exclude .git separately)
        .filter_entry(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            !EXCLUDE_DIRS.iter().any(|d| name == *d)
        })
        .build();

    for entry in walker.flatten() {
        let path = entry.path();
        let is_file = entry.file_type().map(|ft| ft.is_file()).unwrap_or(false);
        let is_dir = entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false);
        if !is_file {
            // Capture top-2-level directory entries for the tree
            let rel = path.strip_prefix(repo).unwrap_or(path).to_path_buf();
            let depth = rel.components().count();
            if depth > 0 && depth <= 2 {
                tree_set.insert(rel.to_string_lossy().to_string(), is_dir);
            }
            continue;
        }
        let rel = path.strip_prefix(repo).unwrap_or(path).to_path_buf();
        let rel_str = rel.to_string_lossy().to_string();
        let depth = rel.components().count();
        if depth <= 2 {
            tree_set.insert(rel_str.clone(), false);
        }

        // Top-level area
        let top = rel
            .components()
            .next()
            .map(|c| {
                let s = c.as_os_str().to_string_lossy().to_string();
                if depth == 1 {
                    "(root)".to_string()
                } else {
                    s
                }
            })
            .unwrap_or_else(|| "(root)".to_string());
        let entry_counts = top_counts.entry(top).or_insert((0, 0));
        entry_counts.0 += 1;

        // Inventory filter (match bash find -name list)
        let is_code = CODE_EXTS
            .iter()
            .any(|ext| rel_str.ends_with(ext));
        if is_code {
            paths.push(rel_str.clone());
            entry_counts.1 += 1;
        }

        // Entrypoints
        if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
            if PRIORITY_ENTRYPOINTS.contains(&name) && !rel_str.starts_with("node_modules/") {
                entrypoints.push(rel_str.clone());
            }
        }

        // Source files (for import scanning)
        if matches!(path.extension().and_then(|s| s.to_str()), Some("ts" | "js" | "cjs" | "mjs")) {
            source_files.push(path.to_path_buf());
        }

        // Package manifests
        if path.file_name().and_then(|s| s.to_str()) == Some("package.json") {
            package_paths.push(path.to_path_buf());
        }
    }

    paths.sort();
    entrypoints.sort();
    entrypoints.truncate(20);

    // Tree representation (first 120 entries, lexicographic — BTreeMap is already sorted)
    let mut tree_entries: Vec<(String, bool)> = tree_set.into_iter().collect();
    tree_entries.truncate(120);

    // Packages
    let mut packages: Vec<PackageInfo> = Vec::new();
    for p in &package_paths {
        let parent = p.parent().unwrap_or(repo);
        let path_str = parent
            .strip_prefix(repo)
            .unwrap_or(parent)
            .to_string_lossy()
            .to_string();
        let path_str = if path_str.is_empty() { ".".to_string() } else { path_str };
        let text = match fs::read_to_string(p) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let parsed: PackageJson = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let name = parsed
            .name
            .clone()
            .unwrap_or_else(|| path_str.clone());
        let mut deps: Vec<String> = parsed.dependencies.keys().cloned().collect();
        deps.sort();
        packages.push(PackageInfo {
            name,
            path: path_str,
            deps,
        });
    }
    packages.sort_by(|a, b| a.name.cmp(&b.name));

    // Languages
    let mut ext_counts: BTreeMap<String, usize> = BTreeMap::new();
    for p in &paths {
        if let Some(dot) = p.rfind('.') {
            let ext = p[dot..].to_lowercase();
            *ext_counts.entry(ext).or_insert(0) += 1;
        }
    }
    let lang_rules: &[(&str, &[&str])] = &[
        ("TypeScript", &[".ts", ".tsx", ".mts", ".cts"]),
        ("JavaScript", &[".js", ".jsx", ".mjs", ".cjs"]),
        ("Python", &[".py"]),
        ("Go", &[".go"]),
        ("Rust", &[".rs"]),
        ("Zig", &[".zig"]),
        ("Shell", &[".sh"]),
    ];
    let mut languages: Vec<(String, usize)> = Vec::new();
    for (name, exts) in lang_rules {
        let total: usize = exts.iter().map(|e| ext_counts.get(*e).copied().unwrap_or(0)).sum();
        if total > 0 {
            languages.push(((*name).to_string(), total));
        }
    }

    // Frameworks
    let package_names: BTreeSet<String> = packages.iter().map(|p| p.name.clone()).collect();
    let all_deps: BTreeSet<String> = packages.iter().flat_map(|p| p.deps.iter().cloned()).collect();
    let mut frameworks: Vec<String> = Vec::new();
    if all_deps.contains("next") {
        frameworks.push("Next.js".to_string());
    }
    if all_deps.contains("react") || package_names.contains("@wterm/react") {
        frameworks.push("React".to_string());
    }
    if all_deps.contains("vue") || package_names.contains("@wterm/vue") {
        frameworks.push("Vue".to_string());
    }
    if all_deps.contains("ws") {
        frameworks.push("WebSocket".to_string());
    }
    if repo.join("turbo.json").exists() {
        frameworks.push("Turbo".to_string());
    }
    if repo.join("pnpm-workspace.yaml").exists() {
        frameworks.push("pnpm workspace".to_string());
    }
    // WASM detection: any .zig file present
    if walk_has_extension(repo, "zig") {
        frameworks.push("WASM".to_string());
    }

    // Hotspot import counts (TS/JS files only)
    let import_re = Regex::new(r"(?m)^(?:import |export .* from |const .*require\()").unwrap();
    let mut hotspots: Vec<(usize, String)> = Vec::new();
    for sf in &source_files {
        let text = match fs::read_to_string(sf) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let count = import_re.find_iter(&text).count();
        if count > 0 {
            let rel = sf.strip_prefix(repo).unwrap_or(sf).to_string_lossy().to_string();
            hotspots.push((count, rel));
        }
    }
    hotspots.sort_by(|a, b| b.0.cmp(&a.0));

    // State/storage candidate directories
    let mut state_dirs: Vec<String> = Vec::new();
    for candidate in [".a5c", "state", "runs", "logs", "cache", ".github", "scripts"] {
        if repo.join(candidate).is_dir() {
            state_dirs.push(format!("- `{}`", candidate));
        }
    }

    Ok(Inventory {
        repo: repo.to_path_buf(),
        slug: slug.to_string(),
        paths,
        top_counts,
        packages,
        languages,
        frameworks,
        entrypoints,
        hotspots,
        tree_entries,
        state_dirs,
    })
}

fn walk_has_extension(repo: &Path, ext: &str) -> bool {
    let walker = WalkBuilder::new(repo)
        .filter_entry(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            !EXCLUDE_DIRS.iter().any(|d| name == *d)
        })
        .build();
    for entry in walker.flatten() {
        if entry.path().extension().and_then(|s| s.to_str()) == Some(ext) {
            return true;
        }
    }
    false
}

fn render_inventory_md(inv: &Inventory) -> String {
    let mut out = String::new();
    out.push_str("# 00 File Inventory\n\n");
    out.push_str("## Purpose\n");
    out.push_str("Provide a coverage-oriented inventory so later analysis can show which files and areas were actually seen.\n\n");
    out.push_str("## Coverage Policy\n");
    out.push_str("- List all architecturally relevant files/paths that should be reviewed\n");
    out.push_str("- Separate full inventory from core-focus shortlist\n");
    out.push_str("- Mark deep/huge areas that were sampled instead of exhaustively read\n\n");
    out.push_str("## Inventory Summary\n");
    out.push_str(&format!("- Repo root: `{}`\n", inv.repo.display()));
    out.push_str(&format!(
        "- Total inventoried files (code/docs-ish filter): {}\n",
        inv.paths.len()
    ));
    out.push_str("- Inventory filter used: `*.ts, *.js, *.cjs, *.mjs, *.md, *.json, *.sh`\n\n");
    out.push_str("## Top-Level Counts\n");
    out.push_str("| Area | Total Files | Code/Docs-ish Files | Notes |\n");
    out.push_str("|---|---:|---:|---|\n");
    for (area, (files, code)) in &inv.top_counts {
        out.push_str(&format!("| {} | {} | {} | |\n", area, files, code));
    }
    out.push_str("\n## Core Focus Shortlist\n");
    out.push_str("- `README.md`\n");
    for pkg in inv.packages.iter().take(12) {
        let p = if pkg.path == "." {
            "package.json".to_string()
        } else {
            format!("{}/package.json", pkg.path)
        };
        out.push_str(&format!("- `{}`\n", p));
    }
    out.push_str("\n## Exhaustive/Generated/Content-Heavy Areas\n");
    let mut big_areas: Vec<(&String, &(usize, usize))> = inv.top_counts.iter().collect();
    big_areas.sort_by(|a, b| b.1 .1.cmp(&a.1 .1));
    let mut emitted_any = false;
    for (area, (_, code)) in big_areas.iter().take(8) {
        if *code >= 100 {
            out.push_str(&format!(
                "- `{}/` — large area; likely sample first rather than exhaustively read\n",
                area
            ));
            emitted_any = true;
        }
    }
    if !emitted_any {
        out.push_str("- No obviously huge areas detected by the bootstrap scan\n");
    }
    out.push_str("\n## Full Inventory\n");
    out.push_str("See generated source list snapshot at analysis time.\n\n");
    out.push_str("Representative tree/filter excerpt:\n```text\n");
    // Match bash: use the WORKSPACE SLUG as the tree root label (not the repo basename).
    out.push_str(&format!("{}/\n", inv.slug));
    out.push_str(&tree_lines(&inv.tree_entries));
    out.push_str("\n```\n\n");
    out.push_str("## Seen / Not Yet Seen\n");
    out.push_str("### Seen\n- Bootstrap inventory and package metadata scan completed\n- Top-level repo tree captured\n- Package manifests inventoried\n- Candidate import hotspots identified\n\n");
    out.push_str("### Not Yet Seen / Deferred\n- Deep semantic review of most source files is still pending\n- Any area not explicitly read in later notes remains deferred\n\n");
    out.push_str("## Notes\n- This file is the coverage guardrail: architectural conclusions should not pretend exhaustive review while major areas remain deferred.\n- For very large repos, explicit sampling is preferable to fake completeness.\n\n");
    out.push_str("## Related\n- `index.md`\n- `00b-dependency-map.md`\n- `01-system-map.md`\n");
    out
}

fn tree_lines(entries: &[(String, bool)]) -> String {
    let mut out = String::new();
    for (item, is_dir) in entries {
        let depth = item.matches('/').count();
        let name = item.rsplit('/').next().unwrap_or(item);
        for _ in 0..depth {
            out.push_str("│  ");
        }
        out.push_str("├─ ");
        out.push_str(name);
        // Bash adds a trailing `/` when the item is a top-level directory entry
        // (no slash in the rel path AND the path is a directory). Mirror that.
        if *is_dir && !item.contains('/') {
            out.push('/');
        }
        out.push('\n');
    }
    out
}

fn render_dependency_md(inv: &Inventory) -> String {
    let mut out = String::new();
    out.push_str("# 00b Dependency Map\n\n## Purpose\nMake code-level and package-level dependencies explicit.\n\n");
    out.push_str("## Coverage Link\n- Source inventory: `00-file-inventory.md`\n- Analysis status: bootstrap\n- Files/areas used for this dependency map: package manifests and a bootstrap import-count scan\n- Major deferred areas affecting this map: deep intra-module dependencies and semantic/runtime-only edges\n\n");
    out.push_str("## Package Dependency Overview\n| Package/Module | Direct Depends On | Runtime Role | Risk Notes |\n|---|---|---|---|\n");
    for pkg in &inv.packages {
        let deps_str = if pkg.deps.is_empty() {
            "—".to_string()
        } else {
            let mut s: Vec<String> = pkg.deps.iter().take(5).cloned().collect();
            if pkg.deps.len() > 5 {
                s.push("...".to_string());
            }
            s.join(", ")
        };
        out.push_str(&format!("| `{}` | {} | | |\n", pkg.name, deps_str));
    }
    out.push_str("\n## Import/Relation Hotspots\n");
    if inv.hotspots.is_empty() {
        out.push_str("- No import hotspots detected by bootstrap\n");
    } else {
        for (count, rel) in inv.hotspots.iter().take(12) {
            out.push_str(&format!("- `{}` ({} import/export edges)\n", rel, count));
        }
    }
    out.push_str("\n## Package-Level Dependency Graph\n```text\n");
    let package_names: BTreeSet<&String> = inv.packages.iter().map(|p| &p.name).collect();
    for pkg in &inv.packages {
        out.push_str(&format!("{}\n", pkg.name));
        for dep in pkg.deps.iter().take(12) {
            let marker = if package_names.contains(dep) { " (workspace)" } else { "" };
            out.push_str(&format!("  -> {}{}\n", dep, marker));
        }
    }
    out.push_str("```\n\n");
    out.push_str("## External Dependencies\n| Dependency | Where Used | Why It Exists | Replaceable? | Notes |\n|---|---|---|---|---|\n");
    let mut external: BTreeMap<&String, BTreeSet<&String>> = BTreeMap::new();
    for pkg in &inv.packages {
        for dep in &pkg.deps {
            if !package_names.contains(dep) {
                external.entry(dep).or_default().insert(&pkg.name);
            }
        }
    }
    for (dep, users) in external.iter().take(40) {
        let mut where_list: Vec<&str> = users.iter().take(3).map(|s| s.as_str()).collect();
        if users.len() > 3 {
            where_list.push("...");
        }
        out.push_str(&format!("| `{}` | {} | | | |\n", dep, where_list.join(", ")));
    }
    out.push_str("\n## Internal Coupling Notes\n- Bootstrap scan captures package dependencies and first-pass import edges, not full semantic coupling\n- Thin wrappers and true hubs still need human confirmation\n\n");
    out.push_str("## Confidence\n- Coverage level for this dependency map: sampled\n- Highest-confidence dependency areas: package manifests, direct package dependencies, explicit static imports in hotspot files\n- Lowest-confidence dependency areas: deep file-to-file imports, aliased imports, dynamic/runtime-only relationships\n- Bootstrap-only claims still present: most runtime-role and coupling interpretation\n- Manual verification still needed for: true architectural hubs, dynamic imports, runtime-only edges\n\n");
    out.push_str("## Related\n- `index.md`\n- `00-file-inventory.md`\n- `01-system-map.md`\n- `02-runtime-model.md`\n");
    out
}

fn render_system_md(inv: &Inventory) -> String {
    let mut out = String::new();
    out.push_str("# 01 System Map\n\n## Purpose\nDescribe the system at rest: what exists, where it lives, and what each major part is responsible for.\n\n");
    out.push_str("## Coverage Link\n- Source inventory: `00-file-inventory.md`\n- Analysis status: bootstrap\n- Files/areas used for this map: package manifests, top-level tree, bootstrap dependency/import scan\n- Major deferred areas affecting this map: deep semantics of most source files and any large directories not yet manually reviewed\n\n");
    out.push_str("## Repo Shape\n");
    let mut big_areas: Vec<(&String, &(usize, usize))> = inv.top_counts.iter().collect();
    big_areas.sort_by(|a, b| b.1 .1.cmp(&a.1 .1));
    for (area, (_, code)) in big_areas.iter().take(8) {
        out.push_str(&format!("- `{}/` — {} code/docs-ish files\n", area, code));
    }
    out.push_str("\n## Repo Tree\n```text\n");
    // Match bash: use the WORKSPACE SLUG as the tree root label (not the repo basename).
    out.push_str(&format!("{}/\n", inv.slug));
    out.push_str(&tree_lines(&inv.tree_entries));
    out.push_str("\n```\n\n");
    out.push_str("## Major Components\n| Component | Path | Type | Responsibility | Evidence | Notes |\n|---|---|---|---|---|---|\n");
    if inv.packages.is_empty() {
        out.push_str("| | | | | | |\n");
    } else {
        for pkg in inv.packages.iter().take(20) {
            let role = classify_package_role(&pkg.path);
            out.push_str(&format!(
                "| `{}` | `{}` | {} | bootstrap-inferred | `package.json` | |\n",
                pkg.name, pkg.path, role
            ));
        }
    }
    out.push_str("\n## Entrypoints\n- Start with package manifests (`package.json`) and top import hotspots from `00b-dependency-map.md`\n- Confirm actual CLI/server/library entrypoints during manual review\n\n");
    out.push_str("## State and Storage\n");
    if inv.state_dirs.is_empty() {
        out.push_str("- No obvious state/storage dirs detected by bootstrap\n");
    } else {
        for line in &inv.state_dirs {
            out.push_str(line);
            out.push('\n');
        }
    }
    out.push_str("\n## Dependency Notes\n- See `00b-dependency-map.md` for bootstrap package/import dependency information\n\n");
    out.push_str("## Open Questions\n- Which packages are true runtime cores vs thin wrappers?\n- Which entrypoints are authoritative?\n- Which large areas should be sampled first?\n\n");
    out.push_str("## Related\n- `index.md`\n- `00-file-inventory.md`\n- `00b-dependency-map.md`\n- `02-runtime-model.md`\n- `03-core-primitives.md`\n");
    out
}

fn classify_package_role(path: &str) -> &'static str {
    let lower = path.to_lowercase();
    if lower.contains("plugin") {
        "adapter/plugin"
    } else if lower.contains("sdk") {
        "core package"
    } else if lower.contains("observer") || lower.contains("dashboard") {
        "ui/service"
    } else if path == "." || path.is_empty() {
        "root package"
    } else {
        "package"
    }
}

fn render_runtime_md() -> String {
    let mut out = String::new();
    out.push_str("# 02 Runtime Model\n\n## Purpose\nReconstruct how the system behaves over time.\n\n");
    out.push_str("## Coverage Link\n- Source inventory: `00-file-inventory.md`\n- Analysis status: bootstrap\n- Files/areas used for this runtime model: package manifests, bootstrap dependency/import scan, system map bootstrap, top import hotspots\n- Major deferred areas affecting this model: actual execution/replay internals, dynamic runtime behavior, most non-hotspot files\n\n");
    out.push_str("## Main Flow\n1. Bootstrap inference only: identify likely startup surfaces\n2. Bootstrap inference only: identify likely coordinators\n3. Bootstrap inference only: identify likely helpers/adapters\n4. Bootstrap inference only: identify likely trust/output boundaries\n5. Manual enrichment required before claiming real runtime reconstruction\n\n");
    out.push_str("Write the actual repo-specific flow here. If a step is inferred rather than verified, label it.\n\n");
    out.push_str("## Main Functions / Methods and Usage\n| Function / Method | Location | Role in Flow | How It Is Used | Claim Level |\n|---|---|---|---|---|\n| bootstrap hotspot | bootstrap scan result | candidate coordinator | manual enrichment required | unknown |\n\n");
    out.push_str("## Open Questions\n- Which detected entrypoints are the actual authoritative runtime entrypoints?\n- Which hotspot modules are true coordinators vs utility clusters?\n- Which state directories are runtime-critical vs incidental?\n\n");
    out.push_str("## Confidence\n- Coverage level for this runtime reconstruction: sampled\n- Bootstrap-only claims still present: almost all flow sequencing until manual review happens\n- Manual verification still needed for: startup path, steady-state loop, persistence, error/exit behavior\n");
    out
}

fn is_enriched(path: &Path) -> bool {
    let text = match fs::read_to_string(path) {
        Ok(t) => t,
        Err(_) => return false,
    };
    text.contains("Analysis status: manually enriched")
        || text.contains("Analysis status: verified")
        || text.contains("Claim discipline: verified-only main path")
}

fn write_preserving_frontmatter(path: &Path, body: &str) -> Result<()> {
    let combined = if path.exists() {
        let existing = fs::read_to_string(path)?;
        if let Some((fm, _)) = frontmatter::split(&existing) {
            frontmatter::join(fm, body)
        } else {
            body.to_string()
        }
    } else {
        body.to_string()
    };
    fs::write(path, combined)?;
    Ok(())
}

fn touch_index(index_path: &Path, inv: &Inventory, version: &str) -> Result<()> {
    if !index_path.exists() {
        return Ok(());
    }
    let mut text = fs::read_to_string(index_path)?;
    text = text.replace("- [ ] 00-file-inventory.md", "- [x] 00-file-inventory.md");
    text = text.replace("- [ ] 00b-dependency-map.md", "- [x] 00b-dependency-map.md");
    text = text.replace("- [ ] 01-system-map.md", "- [x] 01-system-map.md");
    text = text.replace("- [ ] 02-runtime-model.md", "- [x] 02-runtime-model.md");
    if !text.contains("complete enough for purpose") {
        text = text.replace(
            "- Bootstrap status: not started",
            "- Bootstrap status: bootstrap generated",
        );
    }

    let lang_line = if inv.languages.is_empty() {
        "- Languages: none detected".to_string()
    } else {
        let s = inv
            .languages
            .iter()
            .map(|(n, c)| format!("{} ({})", n, c))
            .collect::<Vec<_>>()
            .join(", ");
        format!("- Languages: {}", s)
    };
    let framework_line = if inv.frameworks.is_empty() {
        "- Frameworks / tooling: none detected".to_string()
    } else {
        format!("- Frameworks / tooling: {}", inv.frameworks.join(", "))
    };
    let entry_line = if inv.entrypoints.is_empty() {
        "- Entrypoint candidates: none detected".to_string()
    } else {
        let s = inv
            .entrypoints
            .iter()
            .take(8)
            .map(|p| format!("`{}`", p))
            .collect::<Vec<_>>()
            .join(", ");
        format!("- Entrypoint candidates: {}", s)
    };
    let assist_line = "- Context assist notes: use detected stack only as a heuristic lens; verify from source before concluding".to_string();

    let lang_re = Regex::new(r"(?m)^- Languages:.*$").unwrap();
    let fw_re = Regex::new(r"(?m)^- Frameworks / tooling:.*$").unwrap();
    let ep_re = Regex::new(r"(?m)^- Entrypoint candidates:.*$").unwrap();
    let assist_re = Regex::new(r"(?m)^- Context assist notes:.*$").unwrap();
    let version_re = Regex::new(r"(?m)^- Scanman method version: `[^`]*`.*$").unwrap();

    text = lang_re.replace(&text, lang_line.as_str()).into_owned();
    text = fw_re.replace(&text, framework_line.as_str()).into_owned();
    text = ep_re.replace(&text, entry_line.as_str()).into_owned();
    text = assist_re.replace(&text, assist_line.as_str()).into_owned();
    text = version_re
        .replace(
            &text,
            format!("- Scanman method version: `{}`", version).as_str(),
        )
        .into_owned();

    fs::write(index_path, text)?;
    Ok(())
}
