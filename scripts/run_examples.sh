#!/usr/bin/env bash
# Run every example against the precompiled packages.
set -euo pipefail
cd "$(dirname "$0")/.."
for e in examples/*.mojo; do
    echo "=== $e ==="
    mojo run -I build "$e"
done
