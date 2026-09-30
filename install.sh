#!/usr/bin/env bash
# The Witcher 3 5.0.0.1041720 (Steam build 25575366) — ray tracing on AMD under Proton (experimental)
#   bash install.sh            -> creates "Proton Experimental RT-AMD" + patches witcher3.exe
#   bash install.sh --restore  -> removes the custom Proton and restores the original exe
# Proton Experimental and the game are looked up in every Steam library (steamapps/libraryfolders.vdf);
# set PROTON_EXP_DIR="/path/to/Proton - Experimental" to use a specific copy.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"

# Steam library roots: the main Steam dir first, then every "path" in libraryfolders.vdf
steam_libraries() {
    printf '%s\n' "$STEAM"
    local vdf="$STEAM/steamapps/libraryfolders.vdf"
    [[ -f "$vdf" ]] || return 0
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$vdf" | sed 's/\\\\/\\/g'
}

# Prints steamapps/common/<name> from the first library that has it
find_in_libraries() {
    local lib
    while IFS= read -r lib; do
        if [[ -d "$lib/steamapps/common/$1" ]]; then
            printf '%s\n' "$lib/steamapps/common/$1"
            return 0
        fi
    done < <(steam_libraries)
    return 1
}

EXP="${PROTON_EXP_DIR:-$(find_in_libraries "Proton - Experimental" || true)}"
EXP="${EXP%/}"
# Steam only reads compatibility tools from the main Steam dir, never from other libraries
DST="$STEAM/compatibilitytools.d/Proton-Exp-RT-AMD"
BUILD="$HERE/build/vkd3d-proton-w3rt"
W3="$(find_in_libraries "The Witcher 3" || true)"
EXE="${W3:-$STEAM/steamapps/common/The Witcher 3}/bin/x64_dx12/witcher3.exe"
BACKUP_DIR="$HOME/.local/share/witcher3-rt-amd-proton"
ORIG="$BACKUP_DIR/witcher3.exe.original-5.0.1041720"
SHA_ORIG="c272b2c2e61f84c758e28fab69ab2915944dd1e539dbb435fae9fc67494c7e25"

if pgrep -f '^[A-Z]:.*witcher3\.exe' >/dev/null; then
    echo "Close The Witcher 3 first."; exit 1
fi

if [[ "${1:-}" == "--restore" ]]; then
    rm -rf "$DST" && echo "Removed $DST"
    if [[ -f "$ORIG" ]]; then cp -f "$ORIG" "$EXE" && echo "Restored original witcher3.exe"
    else echo "No backup found; use Steam > Verify integrity of game files."; fi
    echo "Switch the game back to 'Proton Experimental' in Steam."
    exit 0
fi

if [[ -z "$EXP" ]]; then
    echo "Proton Experimental not found in any Steam library listed in $STEAM/steamapps/libraryfolders.vdf."
    echo "Install it in Steam, or set PROTON_EXP_DIR=\"/path/to/Proton - Experimental\"."
    exit 1
fi
for f in proton version files/lib/wine/vkd3d-proton/x86_64-windows files/lib/wine/vkd3d-proton/i386-windows; do
    [[ -e "$EXP/$f" ]] || { echo "Not a usable Proton Experimental (missing $f): $EXP"; exit 1; }
done
[[ "$(realpath "$EXP")" != "$(realpath -m "$DST")" ]] || { echo "PROTON_EXP_DIR must not be $DST"; exit 1; }
[[ -f "$BUILD/x64/d3d12core.dll" ]] || { echo "Run build.sh first."; exit 1; }
[[ -f "$EXE" ]]   || { echo "witcher3.exe not found at: $EXE"; exit 1; }

# 1) Separate Proton copy with the patched vkd3d-proton (Proton Experimental itself is untouched)
echo "== Using $EXP"
echo "== Creating $DST"
rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -a "$EXP" "$DST"
rm -f "$DST/dist.lock"
cp -f "$BUILD/x64/d3d12.dll" "$BUILD/x64/d3d12core.dll" "$DST/files/lib/wine/vkd3d-proton/x86_64-windows/"
cp -f "$BUILD/x86/d3d12.dll" "$BUILD/x86/d3d12core.dll" "$DST/files/lib/wine/vkd3d-proton/i386-windows/"
# bump version so Proton re-syncs the DLLs into the prefix
read -r ts name < "$EXP/version"
echo "$((ts + 1)) ${name}-rtamd" > "$DST/version"
cat > "$DST/compatibilitytool.vdf" <<'EOF'
"compatibilitytools"
{
  "compat_tools"
  {
    "Proton-Exp-RT-AMD"
    {
      "install_path" "."
      "display_name" "Proton Experimental RT-AMD (vkd3d #3332 + dxil-spirv #311)"
      "from_oslist"  "windows"
      "to_oslist"    "linux"
    }
  }
}
EOF

# 2) Exe patch: clear the "running under Wine" flag that zeroes RT capability.
#    Only the two RT-related changes; the NVIDIA/Streamline (DLSS) patches are NOT applied.
echo "== Patching witcher3.exe"
mkdir -p "$BACKUP_DIR"
python3 - "$EXE" "$SHA_ORIG" "$ORIG" <<'PY'
import sys, hashlib, os, shutil
exe, sha_orig, orig = sys.argv[1:4]
d = bytearray(open(exe, 'rb').read())
patches = [  # (offset, original, new, description)
    (0x1EE2A53, bytes.fromhex('750b'), bytes.fromhex('9090'), 'clear Wine flag -> RT/PT selectable'),
    (0x1EE09F7, bytes.fromhex('75'),   bytes.fromhex('eb'),   'keep Wine buffer-alignment path'),
]
if all(d[o:o+len(n)] == n for o, _, n, _ in patches):
    print('Already patched.'); sys.exit(0)
if hashlib.sha256(d).hexdigest() != sha_orig:
    sys.exit('witcher3.exe is not build 5.0.0.1041720: refusing to patch.')
if not os.path.exists(orig):
    shutil.copy2(exe, orig); print(f'  backup: {orig}')
for o, old, new, desc in patches:
    assert d[o:o+len(old)] == old, hex(o)
    d[o:o+len(new)] = new
    print(f'  {hex(o)}: {old.hex()} -> {new.hex()}  ({desc})')
open(exe, 'wb').write(d)
print('OK')
PY

cat <<'EOF'

Done. Next:
  1) Restart Steam.
  2) The Witcher 3 > Properties > Compatibility > "Proton Experimental RT-AMD".
  3) On hybrid systems (iGPU + dGPU) add to launch options so the game's hardware
     detection only sees the AMD card:
       VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json %command%
  4) In-game: Graphics > preset "RT".
Note: a game update or "Verify integrity" will undo the exe patch.
EOF
