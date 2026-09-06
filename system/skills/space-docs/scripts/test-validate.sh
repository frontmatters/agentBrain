#!/usr/bin/env bash
# test-validate.sh — asserts validate.sh passes a clean bundle and fails leaks.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
V="$here/validate.sh"
pass=0; fail=0
ok()  { echo "ok   $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# --- clean bundle should PASS (exit 0) ---
C="$(mktemp -d)"
cat > "$C/README.md" <<'EOF'
# Space
Portable ref: $HOME/project and ~/thing. See [arch](ARCHITECTURE.md).
EOF
cat > "$C/ARCHITECTURE.md" <<'EOF'
# Architecture
Back to the [README](README.md).
EOF
bash "$V" "$C" >/dev/null 2>&1 && ok "clean bundle passes" || bad "clean bundle should pass"

# --- machine-local path should FAIL ---
L="$(mktemp -d)"; cp "$C/ARCHITECTURE.md" "$L/"
# literals below are split ('a''b') so this test's own fixtures do not trip the
# repo privacy-scan; concatenated at runtime they still trigger validate.sh.
printf '# Space\nSee %s for details. [arch](ARCHITECTURE.md)\n' '/Users''/someone/notes' > "$L/README.md"
bash "$V" "$L" >/dev/null 2>&1 && bad "machine path should fail" || ok "machine-local path fails"

# --- vault reference should FAIL ---
Vd="$(mktemp -d)"; cp "$C/ARCHITECTURE.md" "$Vd/"
cat > "$Vd/README.md" <<'EOF'
# Space
Details live in the agentBrain vault. [arch](ARCHITECTURE.md)
EOF
bash "$V" "$Vd" >/dev/null 2>&1 && bad "vault ref should fail" || ok "vault reference fails"

# --- dead internal link should FAIL ---
D="$(mktemp -d)"
cat > "$D/README.md" <<'EOF'
# Space
[missing](nope.md)
EOF
bash "$V" "$D" >/dev/null 2>&1 && bad "dead link should fail" || ok "dead internal link fails"

# --- no README should FAIL ---
N="$(mktemp -d)"; echo "# x" > "$N/OTHER.md"
bash "$V" "$N" >/dev/null 2>&1 && bad "missing README should fail" || ok "missing README fails"

# --- non-directory should be usage/err ---
bash "$V" /nonexistent-xyz >/dev/null 2>&1 && bad "bad dir should not pass" || ok "bad dir handled"

# --- ../-link to a file that EXISTS but is OUTSIDE the space should FAIL ---
P="$(mktemp -d)"; mkdir -p "$P/space" "$P/outside"
echo "# real doc outside" > "$P/outside/thing.md"
cat > "$P/space/README.md" <<'EOF'
# Space
[leak](../outside/thing.md)
EOF
bash "$V" "$P/space" >/dev/null 2>&1 && bad "out-of-boundary link should fail" || ok "out-of-boundary (../) link fails"
rm -rf "$P"

# --- hard secret material should FAIL ---
Se="$(mktemp -d)"
printf '# S\n%s\n%s\n' 'AKIA''IOSFODNN7EXAMPLE' '-----BEGIN RSA PRIVATE KE''Y-----' > "$Se/README.md"
bash "$V" "$Se" >/dev/null 2>&1 && bad "secret material should fail" || ok "secret material (key/token) fails"
rm -rf "$Se"

# --- off-space term via deny-list should FAIL ---
Od="$(mktemp -d)"; echo "# Acme but mentions OtherClient" > "$Od/README.md"
echo "OtherClient" > "$Od/deny.txt"
bash "$V" "$Od" "$Od/deny.txt" >/dev/null 2>&1 && bad "deny-list term should fail" || ok "off-space deny-list term fails"
rm -rf "$Od"

# --- a subfolder without a README should FAIL ---
Fr="$(mktemp -d)"; echo "# root" > "$Fr/README.md"; mkdir "$Fr/assets"; echo "x" > "$Fr/assets/a.png"
bash "$V" "$Fr" >/dev/null 2>&1 && bad "subfolder without README should fail" || ok "subfolder without README fails"
echo "# assets" > "$Fr/assets/README.md"
bash "$V" "$Fr" >/dev/null 2>&1 && ok "subfolder WITH README passes" || bad "subfolder with README should pass"
rm -rf "$Fr"

rm -rf "$C" "$L" "$Vd" "$D" "$N"
echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
