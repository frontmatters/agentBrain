//! Minimal YAML frontmatter parsing/preserving helpers.
//!
//! Scanman only needs three operations:
//!   1. detect whether a markdown file starts with a `---\n...\n---\n` block
//!   2. preserve that block when regenerating the body (scan.sh re-writes 00/00b/01/02)
//!   3. read a single scalar field (e.g. `id:`) — line-based
//!
//! Full YAML parsing would be overkill and would pull in a heavy dep.

/// Split a markdown file into (frontmatter, body). Returns None if no frontmatter block.
/// The returned frontmatter includes both `---` lines and the trailing newline.
pub fn split(text: &str) -> Option<(&str, &str)> {
    if !text.starts_with("---\n") {
        return None;
    }
    let after_open = &text[4..];
    after_open.find("\n---\n").map(|rel_end| {
        let fm_end = 4 + rel_end + 5; // include the closing ---\n
        (&text[..fm_end], &text[fm_end..])
    })
}

/// Combine a frontmatter block with a body. Frontmatter is expected to end with the
/// closing `---\n` (and therefore a trailing newline); leading newlines on the body are
/// stripped so we get exactly one separator newline between them.
pub fn join(frontmatter: &str, body: &str) -> String {
    let body = body.trim_start_matches('\n');
    let mut out = String::with_capacity(frontmatter.len() + body.len());
    out.push_str(frontmatter);
    out.push_str(body);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_extracts_frontmatter() {
        let text = "---\ntitle: foo\nid: abc\n---\n# Body\nLine 2\n";
        let (fm, body) = split(text).expect("frontmatter present");
        assert_eq!(fm, "---\ntitle: foo\nid: abc\n---\n");
        assert_eq!(body, "# Body\nLine 2\n");
    }

    #[test]
    fn split_returns_none_when_missing() {
        assert!(split("# No frontmatter\n").is_none());
    }

    #[test]
    fn join_roundtrip() {
        let fm = "---\nid: x\n---\n";
        let body = "Body content\n";
        assert_eq!(join(fm, body), "---\nid: x\n---\nBody content\n");
    }
}
