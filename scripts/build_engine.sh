#!/usr/bin/env bash
# Precompile every ludens-engine package into build/*.mojoc, in dependency order.
# This nightly only resolves cross-file imports through precompiled .mojoc on the
# -I path (source dirs are not searched), so packages must be built before tests.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

mojo precompile ludens-engine/harness   -o build/harness.mojoc
mojo precompile ludens-engine/geometry  -o build/geometry.mojoc
mojo precompile ludens-engine/spatial   -I build -o build/spatial.mojoc
mojo precompile ludens-engine/ecs       -o build/ecs.mojoc
mojo precompile ludens-engine/collision -I build -o build/collision.mojoc
mojo precompile ludens-engine/physics   -I build -o build/physics.mojoc

echo "build: all packages precompiled into build/"
