#!/usr/bin/env bash
# Run every test file against the precompiled packages. Each test's Suite.finish()
# exits non-zero on failure, so `set -e` stops the run at the first failing file.
set -euo pipefail
cd "$(dirname "$0")/.."
for t in tests/test_*.mojo; do
    echo "--- $t ---"
    mojo run -I build "$t"
done
echo "all tests passed"
