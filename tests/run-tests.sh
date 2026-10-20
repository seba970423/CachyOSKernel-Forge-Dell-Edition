#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

for script in "$REPO_ROOT"/builder*.sh "$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/profiles/*.conf "$SCRIPT_DIR"/*.sh; do
    bash -n "$script"
done

"$SCRIPT_DIR/validate-reference.sh"
"$SCRIPT_DIR/test-hardware-detection.sh"
"$SCRIPT_DIR/test-dell-profile.sh"
"$SCRIPT_DIR/test-policy-prompts.sh"
"$SCRIPT_DIR/test-kernel-naming.sh"
"$SCRIPT_DIR/test-validation-paths.sh"
"$SCRIPT_DIR/test-tick-frequency.sh"
"$SCRIPT_DIR/test-optional-tuning.sh"
"$SCRIPT_DIR/test-postinstall-cleanup.sh"
bash "$SCRIPT_DIR/test-debug-compression.sh"

printf 'All KernelForge Dell Edition tests passed.\n'
