//! UUID5 helper that produces bit-exact output as bash scripts/uuid5-gen.sh.
//!
//! Convention: uuid5(namespace_from_brain_json, "agentBrain/{vault_relative_path}")

use anyhow::{Context, Result};
use std::path::Path;
use uuid::Uuid;

/// Read the canonical namespace UUID from brain.json.
pub fn agentbrain_namespace(agentbrain_dir: &Path) -> Result<Uuid> {
    let brain_json = std::fs::read_to_string(agentbrain_dir.join("brain.json"))
        .with_context(|| format!("read brain.json under {}", agentbrain_dir.display()))?;
    let parsed: serde_json::Value = serde_json::from_str(&brain_json)?;
    let ns = parsed["namespace"]
        .as_str()
        .context("namespace field missing in brain.json")?;
    Uuid::parse_str(ns).context("namespace is not a valid UUID")
}

/// Compute the UUID5 for a vault-relative path (without `.md` extension).
pub fn uuid5_for_path(namespace: &Uuid, vault_rel_path_no_ext: &str) -> Uuid {
    let name = format!("agentBrain/{}", vault_rel_path_no_ext);
    Uuid::new_v5(namespace, name.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_bash_output() {
        // Reference value computed by bash uuid5-gen.sh on the agentBrain vault:
        //   bash scripts/uuid5-gen.sh "system/skills/scanman/CHANGELOG"
        //   -> c990a86d-20e7-5aec-9f4e-8376fd8567dc
        let ns = Uuid::parse_str("e37d107c-934a-4626-806e-8da1b442c8e4").unwrap();
        let uid = uuid5_for_path(&ns, "system/skills/scanman/CHANGELOG");
        assert_eq!(uid.to_string(), "c990a86d-20e7-5aec-9f4e-8376fd8567dc");
    }
}
