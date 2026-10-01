#!/usr/bin/env bash
# The Witcher 3 5.0.0.1041720 (Steam build 25575366) — ray tracing on AMD under Proton (experimental)
#   bash install.sh                     -> copies Proton Experimental to "Proton-Exp-RT-AMD" + patches witcher3.exe
#   bash install.sh --in-place          -> patches the Proton itself, no copy and no extra compatibility tool
#   bash install.sh --restore           -> undoes the last install (Proton DLLs and/or the custom Proton, plus the exe)
#   bash install.sh --dry-run           -> reports what it would do, changes nothing
# Proton and the game are looked up in every Steam library (steamapps/libraryfolders.vdf) unless
# PROTON_DIR / GAME_EXE point somewhere else (any Proton-GE, GOG, Lutris, Heroic, ...).
#
# Non-Steam copies (GOG, Lutris, Heroic) have no prefix that can be located by name under Steam's
# compatdata dir, so COMPAT_APPID may name the prefix to refresh. It is optional: it only makes the
# install take effect immediately instead of on the next launch, which Proton handles on its own.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"
BUILD="$HERE/build/vkd3d-proton-w3rt"
BACKUP_DIR="$HOME/.local/share/witcher3-rt-amd-proton"
STATE="$BACKUP_DIR/install-state"
ORIG="$BACKUP_DIR/witcher3.exe.original-5.0.1041720"
SHA_ORIG="c272b2c2e61f84c758e28fab69ab2915944dd1e539dbb435fae9fc67494c7e25"
DST_DEFAULT="$STEAM/compatibilitytools.d/Proton-Exp-RT-AMD"

usage() { sed -n '2,8s/^# \{0,1\}//p' "$0"; }

MODE=copy
ACTION=install
DRY_RUN=0
MODE_SET=0
for arg in "$@"; do
    case "$arg" in
        --in-place) MODE=in-place; MODE_SET=1 ;;
        --restore)  ACTION=restore ;;
        --dry-run)  DRY_RUN=1 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "Unknown option: $arg"; usage >&2; exit 1 ;;
    esac
done

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

# Value written by the last install, so --restore needs no arguments again
read_state() {
    [[ -f "$STATE" ]] || return 0
    sed -n "s/^$1=//p" "$STATE" | tail -1
}

# A restore normally repeats the mode of the last install so it needs no arguments,
# but an explicit --in-place on the command line always wins over the recorded one.
if [[ "$ACTION" == restore && $MODE_SET -eq 0 ]]; then
    saved_mode="$(read_state mode)"
    if [[ -n "$saved_mode" ]]; then MODE="$saved_mode"; fi
fi

# Does a restore still have work to do? Refuses to overwrite a fresh install.
pending_restore() {
    [[ -f "$STATE" ]] || return 1
    grep -q '^restored=' "$STATE"
}

PROTON="${PROTON_DIR:-${PROTON_EXP_DIR:-$(read_state proton)}}"
[[ -n "$PROTON" ]] || PROTON="$(find_in_libraries "Proton - Experimental" || true)"
PROTON="${PROTON%/}"

EXE="${GAME_EXE:-$(read_state exe)}"
if [[ -z "$EXE" ]]; then
    W3="$(find_in_libraries "The Witcher 3" || true)"
    EXE="${W3:-$STEAM/steamapps/common/The Witcher 3}/bin/x64_dx12/witcher3.exe"
fi

DST="$(read_state dst)"
DST="${DST:-$DST_DEFAULT}"

if pgrep -f '^[A-Z]:.*witcher3\.exe' >/dev/null; then
    echo "Close The Witcher 3 first."; exit 1
fi

# Replaces the vkd3d-proton DLLs of a Proton with the ones from build.sh.
#
# Both locations matter and both must be patched:
#   lib/wine/vkd3d-proton/<arch>  the source proton's script copies these into
#                                 <prefix>/drive_c/windows/{system32,syswow64} on
#                                 every launch and sets dlloverride=n.
#   lib/wine/<arch>               the copies the loader itself opens, and the
#                                 ones already sitting in a used prefix.
# Patching only the first leaves a prefix (and any loader path) on stock
# d3d12core, which reports D3D12_RAYTRACING_TIER_NOT_SUPPORTED and makes the
# game claim it "does not meet minimal requirements".
install_vkd3d() {
    local root="$1/files/lib/wine"
    for pair in "x64:x86_64-windows" "x86:i386-windows"; do
        local arch="${pair%%:*}" pe="${pair##*:}"
        for target in "$root/vkd3d-proton/$pe" "$root/$pe"; do
            [[ -d "$target" ]] || continue
            cp -f "$BUILD/$arch/d3d12.dll" "$BUILD/$arch/d3d12core.dll" "$target/"
            # Proton ships these read-only, keep it that way
            chmod 555 "$target/d3d12.dll" "$target/d3d12core.dll"
        done
    done
    refresh_prefix_vkd3d
}

# A prefix that already has stock d3d12*.dll keeps them, so push ours in too.
# Optional: only used when COMPAT_APPID names the game in the given prefix.
refresh_prefix_vkd3d() {
    [[ -n "${COMPAT_APPID:-}" ]] || return 0
    local compat="$STEAM/steamapps/compatdata/$COMPAT_APPID"
    local sys64="$compat/pfx/drive_c/windows/system32"
    local sys32="$compat/pfx/drive_c/windows/syswow64"
    [[ -d "$sys64" ]] || return 0
    if [[ -f "$sys64/d3d12core.dll" ]]; then
        cp -f "$BUILD/x64/d3d12.dll" "$BUILD/x64/d3d12core.dll" "$sys64/"
        echo "== Refreshed vkd3d-proton in the existing prefix (system32)"
    fi
    if [[ -f "$sys32/d3d12core.dll" ]]; then
        cp -f "$BUILD/x86/d3d12.dll" "$BUILD/x86/d3d12core.dll" "$sys32/"
        echo "== Refreshed vkd3d-proton in the existing prefix (syswow64)"
    fi
}

if [[ "$ACTION" == restore ]]; then
    # Every rm -rf below is guarded: an empty $PROTON would otherwise expand to
    # "/files/lib/wine/..." and an empty $DST to "" and the script would try to
    # delete those. A restore must never be able to remove something it did not
    # install, so the paths have to be validated before any deletion.
    if [[ "$MODE" == in-place ]]; then
        if [[ -z "$PROTON" || ! -d "$PROTON/files/lib/wine" ]]; then
            echo "PROTON_DIR is unset or no longer a Proton ($PROTON); nothing to restore in place."
        else
            # Restore into a temp dir and swap, so a failed copy cannot leave the
            # Proton with its vkd3d-proton/ half-deleted.
            if [[ -d "$BACKUP_DIR/vkd3d-proton" ]]; then
                rm -rf "$PROTON/files/lib/wine/vkd3d-proton.new"
                if cp -a "$BACKUP_DIR/vkd3d-proton" "$PROTON/files/lib/wine/vkd3d-proton.new"; then
                    rm -rf "$PROTON/files/lib/wine/vkd3d-proton.old"
                    mv "$PROTON/files/lib/wine/vkd3d-proton" "$PROTON/files/lib/wine/vkd3d-proton.old"
                    mv "$PROTON/files/lib/wine/vkd3d-proton.new" "$PROTON/files/lib/wine/vkd3d-proton"
                    rm -rf "$PROTON/files/lib/wine/vkd3d-proton.old"
                else
                    rm -rf "$PROTON/files/lib/wine/vkd3d-proton.new"
                    echo "Restore of vkd3d-proton/ failed; the Proton was left untouched."
                    exit 1
                fi
            fi

            # Only the two DLLs are ever touched, so restore just those and leave
            # the rest of the Proton tree alone. Copying whole PE dirs back also
            # undoes unrelated updates Proton applied since the backup.
            if [[ -d "$BACKUP_DIR/wine-pe" ]]; then
                for pair in "x64:x86_64-windows" "x86:i386-windows"; do
                    pe="${pair##*:}"
                    bdir="$BACKUP_DIR/wine-pe/$pe" tdir="$PROTON/files/lib/wine/$pe"
                    [[ -d "$bdir" && -d "$tdir" ]] || continue
                    cp -f "$bdir/d3d12.dll" "$bdir/d3d12core.dll" "$tdir/"
                    chmod 555 "$tdir/d3d12.dll" "$tdir/d3d12core.dll"
                done
                echo "== Restored d3d12*.dll in $PROTON/files/lib/wine"
            fi

            if [[ -d "$BACKUP_DIR/vkd3d-proton" || -d "$BACKUP_DIR/wine-pe" ]]; then
                echo "Restored vkd3d-proton in $PROTON"
            else
                echo "No vkd3d-proton backup found in $BACKUP_DIR."
            fi
        fi
    else
        # Same guard as above: never rm -rf an unset or empty $DST.
        if [[ -z "$DST" || "$DST" == "/" || "$DST" == "$STEAM" ]]; then
            echo "Refusing to remove '$DST': the destination path is not a Proton copy."
            exit 1
        fi
        if [[ -d "$DST" ]]; then
            rm -rf "$DST" && echo "Removed $DST"
        fi
    fi
    if [[ -f "$ORIG" ]]; then cp -f "$ORIG" "$EXE" && echo "Restored original witcher3.exe"
    else echo "No backup found; use Steam > Verify integrity of game files."; fi
    # Keep the state file: it only records where the Proton and the exe live, and
    # deleting it makes the next install fall back to "Proton - Experimental" and a
    # Steam-library guess for the exe path. The installed=<n> line is what marks
    # whether a restore is still pending.
    printf 'restored=%s\n' "$(date +%s)" >> "$STATE"
    if [[ "$MODE" == in-place ]]; then
        echo "Nothing else to undo: you were already using that Proton."
    else
        echo "Switch the game back to 'Proton Experimental' in Steam."
    fi
    exit 0
fi

if [[ -z "$PROTON" ]]; then
    echo "Proton not found in any Steam library listed in $STEAM/steamapps/libraryfolders.vdf."
    echo "Point at one explicitly, e.g. PROTON_DIR=\"$STEAM/compatibilitytools.d/Proton-GE Latest\" bash install.sh"
    exit 1
fi
for f in proton version files/lib/wine/vkd3d-proton/x86_64-windows files/lib/wine/vkd3d-proton/i386-windows; do
    [[ -e "$PROTON/$f" ]] || { echo "Not a usable Proton (missing $f): $PROTON"; exit 1; }
done
[[ "$(realpath "$PROTON")" != "$(realpath -m "$DST")" ]] || { echo "PROTON_DIR must not be $DST"; exit 1; }
[[ -f "$BUILD/x64/d3d12core.dll" ]] || { echo "Run build.sh first."; exit 1; }
[[ -f "$EXE" ]] || { echo "witcher3.exe not found at: $EXE"; exit 1; }

if (( DRY_RUN )); then
    echo "Mode:     $MODE"
    echo "Proton:   $PROTON"
    echo "Copy to:  $([[ "$MODE" == copy ]] && echo "$DST" || echo '(none, in place)')"
    echo "Exe:      $EXE"
    echo "Backups:  $BACKUP_DIR"
    echo "Dry run: nothing was changed."
    exit 0
fi

if pending_restore; then
    echo "A previous run was restored, so the Proton is back to stock."
    echo "Re-installing now is fine and expected; the original DLLs are still in $BACKUP_DIR."
fi

mkdir -p "$BACKUP_DIR"
printf 'mode=%s\nproton=%s\ndst=%s\nexe=%s\n' "$MODE" "$PROTON" "$DST" "$EXE" > "$STATE"

if [[ "$MODE" == in-place ]]; then
    # Steam keeps using the same compatibility tool, so every game in the library gets the new vkd3d
    echo "== Using $PROTON (in place, no copy: all its games will use the new vkd3d-proton)"
    # The two locations are tracked separately on purpose. An earlier revision
    # guarded both behind a single check on vkd3d-proton/, so anyone who had
    # already run it never got a wine-pe backup and --restore had nothing to
    # put back for lib/wine/<arch>.
    if [[ ! -d "$BACKUP_DIR/vkd3d-proton" ]]; then
        cp -a "$PROTON/files/lib/wine/vkd3d-proton" "$BACKUP_DIR/"
        echo "== Backed up the original vkd3d-proton/"
    fi
    mkdir -p "$BACKUP_DIR/wine-pe"
    for pe in x86_64-windows i386-windows; do
        src="$PROTON/files/lib/wine/$pe" dst="$BACKUP_DIR/wine-pe/$pe"
        [[ -d "$src" ]] || continue
        if [[ -f "$dst/d3d12core.dll" ]]; then continue; fi
        mkdir -p "$dst"
        cp -a "$src/d3d12.dll" "$src/d3d12core.dll" "$dst/"
        echo "== Backed up the original d3d12*.dll in lib/wine/$pe"
    done
    install_vkd3d "$PROTON"
else
    # Separate Proton copy with the patched vkd3d-proton (the Proton itself is untouched)
    echo "== Using $PROTON"
    # Same guard as in the restore path: an unset $DST would expand to "" and an
    # unvalidated one could point at a real directory. Never rm -rf a path we have
    # not confirmed to be the Proton copy this script creates.
    if [[ -z "$DST" || "$DST" == "/" || "$DST" == "$STEAM" || "$DST" == "$PROTON" ]]; then
        echo "Refusing to use '$DST' as the destination: it is not a usable Proton copy path."
        exit 1
    fi
    echo "== Creating $DST"
    rm -rf "$DST"
    mkdir -p "$(dirname "$DST")"
    cp -a "$PROTON" "$DST"
    rm -f "$DST/dist.lock"
    install_vkd3d "$DST"
    # bump version so Proton re-syncs the DLLs into the prefix
    read -r ts name < "$PROTON/version"
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
fi

# Exe patch: clear the "running under Wine" flag that zeroes RT capability.
#    Only the two RT-related changes; the NVIDIA/Streamline (DLSS) patches are NOT applied.
echo "== Patching witcher3.exe"
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
  1) Launch the game. Proton copies the new vkd3d-proton into the prefix on every start, so
     no prefix deletion is needed.
  2) In-game: Graphics > preset "RT".
  On hybrid systems (iGPU + dGPU) add to launch options so the game's hardware
  detection only sees the AMD card:
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json %command%
Note: a game update replaces the exe and undoes its patch; an update of the Proton
(via ProtonUp-Qt or Steam) replaces the vkd3d-proton DLLs — re-run install.sh --in-place then.
EOF
