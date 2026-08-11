//! `init` subcommand — port of bash scripts/scanman-init.sh.
//!
//! Creates a canonical workspace under local/research/repo-distill/<slug>/ with
//! frontmatter that carries the correct UUID5 (so the agentBrain validate-hook
//! accepts subsequent agent edits without blockades).

use crate::templates;
use crate::uuid5;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};

pub fn run(slug: &str, repo_path: Option<&Path>, goal: &str) -> Result<()> {
    validate_slug(slug)?;

    let agentbrain_dir = find_agentbrain_dir()?;
    let target = agentbrain_dir
        .join("local/research/repo-distill")
        .join(slug);
    if target.exists() {
        anyhow::bail!("Scanman target already exists: {}", target.display());
    }
    fs::create_dir_all(&target).context("create target dir")?;

    let namespace = uuid5::agentbrain_namespace(&agentbrain_dir)?;
    let today = current_date();
    let version = read_scanman_version(&agentbrain_dir).unwrap_or_else(|_| "unknown".to_string());

    let templates: &[(&str, &str, &str)] = &[
        ("index.md", "index", templates::INDEX),
        ("00-file-inventory.md", "file-inventory", templates::FILE_INVENTORY),
        ("00b-dependency-map.md", "dependency-map", templates::DEPENDENCY_MAP),
        ("01-system-map.md", "system-map", templates::SYSTEM_MAP),
        ("02-runtime-model.md", "runtime-model", templates::RUNTIME_MODEL),
        ("03-core-primitives.md", "core-primitives", templates::CORE_PRIMITIVES),
        ("04-risk-and-bloat.md", "risk-and-bloat", templates::RISK_AND_BLOAT),
        ("05-redesign-v1.md", "redesign-v1", templates::REDESIGN_V1),
    ];

    for (filename, artifact, template) in templates {
        let stem = filename.strip_suffix(".md").unwrap();
        let rel = format!("local/research/repo-distill/{}/{}", slug, stem);
        let uid = uuid5::uuid5_for_path(&namespace, &rel);

        let mut text = template.to_string();

        if *filename == "index.md" {
            text = text.replace("YYYY-MM-DD", &today);
            text = text.replace("<UUID5>", &uid.to_string());
            text = text.replace("<repo-name>", slug);
        } else if !text.starts_with("---\n") {
            let fm = format!(
                "---\ndate: {}\ntype: research\ntags: [repo-distill, architecture, analysis]\nstatus: active\nid: {}\nrepo: {}\nartifact: {}\nsource: session\n---\n",
                today, uid, slug, artifact
            );
            text.insert_str(0, &fm);
        }

        if !text.ends_with('\n') {
            text.push('\n');
        }

        fs::write(target.join(filename), text)?;
    }

    // Index touch-up — match bash post-process semantics exactly.
    let index_path = target.join("index.md");
    let mut text = fs::read_to_string(&index_path)?;

    let repo_line = if let Some(rp) = repo_path {
        format!("- Repo URL/path: `{}`", rp.display())
    } else {
        "- Repo URL/path:".to_string()
    };
    text = text.replace("- Repo URL/path", &repo_line);
    text = text.replace("- Version/ref/commit analyzed", "- Version/ref/commit analyzed:");
    text = text.replace("- Related notes/docs", "- Related notes/docs:");
    text = text.replace(
        "- Scanman method version",
        &format!("- Scanman method version: `{}`", version),
    );
    text = text.replace("- Current phase", "- Current phase: initialized");
    text = text.replace("- Known blockers", "- Known blockers:");
    let next_action = if let Some(_rp) = repo_path {
        format!(
            "- Next action: run `bash scripts/scanman-scan.sh <repo-path> {}` and then manually enrich the generated docs",
            slug
        )
    } else {
        "- Next action: populate `00-file-inventory.md`".to_string()
    };
    text = text.replace("- Next action", &next_action);
    text = text.replace(
        "- Coverage status: sampled / selective / focused / broad / near-exhaustive",
        "- Coverage status: sampled",
    );
    text = text.replace(
        "- Bootstrap status: not started / bootstrap generated / manually enriched / verified enough for current conclusions",
        "- Bootstrap status: not started",
    );

    for name in [
        "00-file-inventory.md",
        "00b-dependency-map.md",
        "01-system-map.md",
        "02-runtime-model.md",
        "03-core-primitives.md",
        "04-risk-and-bloat.md",
        "05-redesign-v1.md",
    ] {
        text = text.replace(
            &format!("| `{}` | no | no | no | no | |", name),
            &format!("| `{}` | yes | no | no | no | template created |", name),
        );
    }

    if !goal.is_empty() {
        text = text.replace(
            "- What target system/use case the distillation serves",
            &format!("- {}", goal),
        );
    }

    if !text.ends_with('\n') {
        text.push('\n');
    }
    fs::write(&index_path, text)?;

    println!("Initialized scanman workspace: {}", target.display());
    if let Some(rp) = repo_path {
        println!("Next: scanman scan '{}' '{}'", rp.display(), slug);
    } else {
        println!("Next: run scanman scan with a repo path or fill files manually");
    }
    Ok(())
}

fn validate_slug(slug: &str) -> Result<()> {
    if slug.is_empty()
        || !slug
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        anyhow::bail!("repo-slug must be lowercase kebab-case: {}", slug);
    }
    Ok(())
}

fn current_date() -> String {
    // Shell out to `date +%F` to match bash exactly. Avoids pulling chrono.
    let out = std::process::Command::new("date")
        .args(["+%F"])
        .output()
        .expect("date command should exist");
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn read_scanman_version(agentbrain_dir: &Path) -> Result<String> {
    let path = agentbrain_dir.join("system/skills/scanman/VERSION");
    Ok(fs::read_to_string(path)?.trim().to_string())
}

pub fn find_agentbrain_dir() -> Result<PathBuf> {
    if let Ok(dir) = std::env::var("AGENTBRAIN_DIR") {
        return Ok(PathBuf::from(dir));
    }
    let home = std::env::var("HOME").context("HOME not set")?;
    Ok(PathBuf::from(home).join("agentBrain"))
}
