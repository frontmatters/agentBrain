//! Embedded scanman templates (compile-time include from the canonical templates/ dir).
//!
//! Keep these in sync with the bash implementation's source. If templates change,
//! a rebuild is required — that's intentional: the binary IS the templates.

pub const INDEX: &str = include_str!("../../../../../templates/repo-distill-index.md");
pub const FILE_INVENTORY: &str = include_str!("../../../../../templates/repo-distill-file-inventory.md");
pub const DEPENDENCY_MAP: &str = include_str!("../../../../../templates/repo-distill-dependency-map.md");
pub const SYSTEM_MAP: &str = include_str!("../../../../../templates/repo-distill-system-map.md");
pub const RUNTIME_MODEL: &str = include_str!("../../../../../templates/repo-distill-runtime-model.md");
pub const CORE_PRIMITIVES: &str = include_str!("../../../../../templates/repo-distill-core-primitives.md");
pub const RISK_AND_BLOAT: &str = include_str!("../../../../../templates/repo-distill-risk-and-bloat.md");
pub const REDESIGN_V1: &str = include_str!("../../../../../templates/repo-distill-redesign-v1.md");
