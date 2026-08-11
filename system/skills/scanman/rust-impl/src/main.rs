//! scanman — agent-agnostic repo-distill skill (Rust re-implementation).
//!
//! Differential-tested against the bash reference implementation on the canonical
//! wterm/ workspace. See system/skills/scanman/CHANGELOG.md for behavior contract.

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;

mod frontmatter;
mod init;
mod scan;
mod templates;
mod uuid5;
mod validate;

#[derive(Parser, Debug)]
#[command(name = "scanman", version, about = "Agent-agnostic repo-distill skill")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Create a new canonical workspace from templates (with UUID5 frontmatter).
    Init {
        /// Workspace slug (lowercase-kebab-case)
        slug: String,
        /// Path to the repo being analyzed (optional)
        repo_path: Option<PathBuf>,
        /// Optional goal description (joined as trailing words)
        #[arg(trailing_var_arg = true)]
        goal: Vec<String>,
    },
    /// Re-generate bootstrap layers (00, 00b, 01, 02) — preserves enriched docs.
    Scan {
        /// Path to the repo being analyzed
        repo_path: PathBuf,
        /// Workspace slug
        slug: String,
    },
    /// Run the mandatory completeness gate. Exit 0 = pass, 1 = iterate, 2 = error.
    Validate {
        /// Workspace directory to check
        workspace: PathBuf,
        /// Validation mode: `focused` (default) runs the existing 00..05 gates;
        /// `reproduction-spec` validates index.md + LEARNINGS.md + DISTILLATE/
        /// and runs the v0.6 distillate gates (G1, G2, G6, G7, G8, G10, G11,
        /// G13) — without requiring the focused 00..05 artifacts.
        #[arg(long, default_value = "focused")]
        mode: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Init {
            slug,
            repo_path,
            goal,
        } => init::run(&slug, repo_path.as_deref(), &goal.join(" ")),
        Command::Scan { repo_path, slug } => scan::run(&repo_path, &slug),
        Command::Validate { workspace, mode } => {
            let m = validate::Mode::parse(&mode)?;
            let exit = validate::run_with_mode(&workspace, m)?;
            std::process::exit(exit);
        }
    }
}
