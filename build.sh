#!/usr/bin/env bash
# Builds vkd3d-proton with the two in-flight fixes needed for The Witcher 3 5.0 ray tracing on RADV:
#   - vkd3d-proton PR #3332  (conservative BLAS sizes for RTAS_ALLOW_BLAS_REBUILD_SIZES)
#   - dxil-spirv   PR #311   (demote frozen loops sharing a merge block -> fixes invalid SPIR-V in PTRGSFinal)
# Requirements (Arch/CachyOS): git meson ninja glslang wine (for widl) mingw-w64-gcc
set -euo pipefail

VKD3D_BASE=4d06d745      # vkd3d-proton master the fixes were tested on
VKD3D_PR=3332
VKD3D_PR_SHA=3e71c269
DXIL_PR=311
DXIL_PR_SHA=dcdbadff

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/work"
OUT="$HERE/build"

for t in git meson ninja glslangValidator widl x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
    command -v "$t" >/dev/null || { echo "Missing: $t"; exit 1; }
done

mkdir -p "$WORK"
if [[ ! -d "$WORK/vkd3d-proton" ]]; then
    git clone --recursive https://github.com/HansKristian-Work/vkd3d-proton.git "$WORK/vkd3d-proton"
fi
cd "$WORK/vkd3d-proton"
git fetch origin "pull/$VKD3D_PR/head"
git merge-base --is-ancestor "$VKD3D_BASE" "$VKD3D_PR_SHA" || echo "WARNING: PR #$VKD3D_PR no longer based on $VKD3D_BASE"
git checkout -q "$VKD3D_PR_SHA"
git submodule update --init --recursive

cd subprojects/dxil-spirv
git fetch origin "pull/$DXIL_PR/head"
git checkout -q "$DXIL_PR_SHA"
git submodule update --init --recursive
cd ../..

echo "vkd3d-proton: $(git log -1 --format='%h %s')"
echo "dxil-spirv:   $(git -C subprojects/dxil-spirv log -1 --format='%h %s')"

rm -rf "$OUT"
./package-release.sh w3rt "$OUT" --no-package
echo
echo "Built DLLs:"
find "$OUT" -name 'd3d12*.dll' -printf '  %p\n'
