#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
# Emulate digest query in a way the local helper can consume.
printf 'sha256:deadbeef\n'
EOF

cat > "$TMP_DIR/bin/cosign" <<'EOF'
#!/usr/bin/env bash
# Record the command form used for the current cosign invocation.
printf 'cosign %s\n' "$*"
EOF

chmod +x "$TMP_DIR/bin/skopeo" "$TMP_DIR/bin/cosign"

PATH="$TMP_DIR/bin:$PATH" \
COSIGN_KEY="$TMP_DIR/private.key" \
COSIGN_PUB="$TMP_DIR/public.pub" \
IMAGE="quay.io/example:demo" \
"$ROOT_DIR/scripts/local-sign-keyless.sh" > "$TMP_DIR/out.txt" 2>&1 || {
  echo "local key mode test failed because the helper did not accept COSIGN_KEY/COSIGN_PUB" >&2
  exit 1
}

grep -q 'local key/public-key or X.509 certificate mode selected' "$TMP_DIR/out.txt"

grep -q 'cosign sign --key' "$TMP_DIR/out.txt"

grep -q 'cosign verify --key' "$TMP_DIR/out.txt"

grep -q 'sign_image_with_cosign' "$ROOT_DIR/scripts/prepare-demo-m5.sh"

echo "local key mode test passed"
