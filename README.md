# The Witcher 3 Remastered (5.0) — Ray Tracing on AMD under Proton

**Status: working** on RX 6800 XT (RDNA 2) and RX 9060 XT (RDNA 4) with RADV — experimental, use at your own risk.

With the 5.0 "Remastered" update, ray tracing is unavailable on Linux/Proton for two independent reasons:

1. **The game disables RT when it detects Wine.** `witcher3.exe` queries `ntdll!wine_get_version` and sets a cached
   "Wine / Steam hardware" flag that zeroes the ray‑tracing capability, so every RT and path‑tracing option is
   greyed out regardless of the GPU. (Found and documented by
   [gabrielmaialva33's gist](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5).)
2. **Forcing it on crashes RADV** while creating the RT pipelines, because dxil-spirv emits invalid SPIR‑V for the
   `PTRGSFinal` raygen shader. This is fixed by
   [dxil-spirv PR #311](https://github.com/HansKristian-Work/dxil-spirv/pull/311); RTAS sizing also needs
   [vkd3d-proton PR #3332](https://github.com/HansKristian-Work/vkd3d-proton/pull/3332). Both were merged upstream on 2026‑09‑30.

This repo combines both: it builds vkd3d‑proton with those two PRs, installs it into a **separate copy** of
Proton Experimental (the original is untouched), and patches 3 bytes in 2 places of the exe (none of the
NVIDIA/DLSS patches).

The two halves expire at different times: a Proton release will eventually ship the vkd3d/dxil‑spirv fixes, but the
exe patch will still be needed, because the game disabling RT on seeing Wine is the game's own doing and no Proton
update changes it. See *The two halves have different lifetimes*.

## Recommended: Proton Wineland (no exe patch)

The gist above now points to a route that does **not** touch the executable at all, and therefore survives game
updates. It is **Proton Wineland** from [nanomatters' proton-cachyos releases](https://github.com/nanomatters/proton-cachyos/releases)
(`11.0-20260930` or newer): a regular Proton build, not tied to CachyOS, that hides Wine from `witcher3.exe` only,
through a per-game fix (`HideWineExports` for that exe). Because the game files stay untouched, *Verify integrity of
game files* no longer undoes it and a game update does not break it. It also ships the vkd3d-proton fixes ray tracing
needs (the BLAS size fix, tight alignment and the RADV shader fix) and turns NVAPI off on non-NVIDIA GPUs.

Set it up: download `proton-wineland-<version>-x86_64.tar.xz` from the release page and extract it into
`~/.local/share/Steam/compatibilitytools.d/`, restart Steam, then pick it under *Properties → Compatibility* and use
the **unmodified** exe (if you first patched with this repo's script, run `bash install.sh --restore`).

Two caveats:

- The per-game fix runs when **Steam** launches the game. On **Heroic, Lutris or Faugus** it needs a manual step for
  now (the gist's #75/#76/#77) — if you launch outside Steam, expect to do that by hand.
- It is a rolling third-party Proton. Only recent proton-cachyos builds work: older ones lack `SteamUtils011` in
  their `lsteamclient` and crash at start. If it crashes on first run, update Wineland to a newer build.

The gist's end-to-end test of this route was on an **RTX 4090**; the RADV shader fix AMD needs is included. The
*Tested on* table below is where the verified-on-RDNA numbers come from if you stay on the exe-patch route.

> The rest of this README (**Requirements** through **Tested on**) documents that exe-patch route — what `build.sh`
> and `install.sh` do, i.e. the alternative when you'd rather not run a third-party Proton.

## Requirements

The exe must be **one of these two builds**, identified by the SHA256 of the untouched file. `install.sh` refuses
anything else rather than writing at guessed offsets:

| Game build | Steam build | SHA256 of the untouched exe | Size |
|---|---|---|---|
| `5.0.0.1041720` (launch, 2026‑09‑29) | 25575366 | `c272b2c2e61f84c758e28fab69ab2915944dd1e539dbb435fae9fc67494c7e25` | 90832336 |
| `5.0.0.1044392` (5.00c hotfix) | 25646871 | `9406eccc12b68e08920931442ef6a57340e910d3e01f2082e88232487433fe51` | 90674640 |

Also:

- Proton Experimental installed in Steam (11.0, 2026‑09‑24 or newer). GE‑Proton10‑34 does **not** work with this
  game at all: it lacks the `SteamUtils011` interface and the game hangs at start.
- **Recommended: `GE-Proton11-7`** (or newer). `install.sh` works against any Proton via `PROTON_DIR`, but
  `GE-Proton11-7` is the revision the native FSR frame generation was verified against, and the FSR4 notes below
  describe that revision's behaviour. Older GE builds may not behave the same way.
- Build tools (Arch/CachyOS): `sudo pacman -S git meson ninja glslang wine mingw-w64-gcc`

## Usage

```bash
git clone https://github.com/daeduol/witcher3-rt-amd-proton.git
cd witcher3-rt-amd-proton
bash build.sh      # clones vkd3d-proton + both PRs and builds the DLLs (a few minutes)
bash install.sh    # copies Proton Experimental to "Proton-Exp-RT-AMD" and patches witcher3.exe (game must be closed)
```

> **Clone the fork, not the original.** These fixes are not upstream yet. The `main` branch of the original
> repository ([Soyalexf/witcher3-rt-amd-proton](https://github.com/Soyalexf/witcher3-rt-amd-proton)) does not have
> them, and cloning it gives you the unpatched scripts.

Then **restart Steam**, select **Proton-Exp-RT-AMD** under *Properties → Compatibility*, and pick the **RT**
preset in *Graphics*.

> **The Steam restart is not optional.** Steam caches the list of compatibility tools, so if it was already
> running when you installed, the patched Proton may not be picked up and the game can crash on start. Restarting
> Steam first avoids that. Hit in practice on the RDNA 4 machine: install with Steam open → crash on start →
> quit Steam fully and reopen → worked.

To undo everything: `bash install.sh --restore` (or *Verify integrity of game files* in Steam for the exe).

`install.sh --dry-run` prints the Proton, the exe and the mode it would use and changes nothing.

### If it crashes when starting a new game

On the RDNA 4 machine, starting a **new game** on the hotfix crashed while RT and frame generation were still
enabled from the previous save's settings. What worked:

1. Turn **RT** and **frame generation off** in the graphics options.
2. Start the new game on `5.0.0.1044392`.
3. Once in game, re‑enable **RT** and **FSR Frame Generation** from the *RT* preset.

Both then worked normally for the rest of the session. This is an observation from one machine, not a
diagnosed cause, so treat it as a workaround rather than a fix — but it is the thing to try first if a new game
will not start.

### Non-Steam copies of the game, and patching the Proton you already use

`GAME_EXE` and `PROTON_DIR` (formerly `PROTON_EXP_DIR`) override the automatic lookup, so the same two patches
work for a GOG/Lutris copy or for any Proton-GE build. The GOG `witcher3.exe` is checked the same way as the Steam
one, so a GOG copy of either supported build is patched identically.

`--in-place` replaces the vkd3d‑proton DLLs **inside** the Proton you point at instead of creating a copy of it,
which is what you want if that Proton is already your default compatibility tool:

```bash
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest" \
GAME_EXE="/mnt/games/The Witcher 3 Wild Hunt/bin/x64_dx12/witcher3.exe" \
bash install.sh --in-place
```

No copy and no new entry in *Compatibility*: Steam keeps using the same tool, and Proton copies the new
`d3d12.dll` / `d3d12core.dll` into the prefix on every launch, so existing prefixes and saves are untouched.

A non‑Steam copy has no prefix that can be located by name under `steamapps/compatdata`, so `install.sh` cannot
refresh it up front. Add `COMPAT_APPID=<appid>` to have it patched in the same run; it is optional, because Proton
re‑syncs those DLLs into the prefix on the next launch anyway:

```bash
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest" \
GAME_EXE="/mnt/games/The Witcher 3 Wild Hunt/bin/x64_dx12/witcher3.exe" \
COMPAT_APPID=1234567890 bash install.sh --in-place
```

The trade‑offs:

- Every game that uses that Proton also gets the new vkd3d‑proton (it is newer than the one shipped, so this is
  usually an improvement, and `install.sh --restore` puts the original DLLs back).
- `ProtonUp-Qt`, Steam or any other updater **overwrites the Proton directory** on its next update, which takes
  the patched DLLs with it. Re‑run `install.sh --in-place` afterwards; once a Proton release carries vkd3d‑proton
  [`0894a2d5`](https://github.com/HansKristian-Work/vkd3d-proton/commit/0894a2d5) or newer, this step is no longer
  needed at all.

### The two halves have different lifetimes

These are unrelated problems, so they do not become obsolete together:

| Problem | Fixed by | Goes away when |
|---|---|---|
| RT crashes on RADV / DX12 check fails | vkd3d‑proton + dxil‑spirv (the DLL patch) | a Proton release ships [`0894a2d5`](https://github.com/HansKristian-Work/vkd3d-proton/commit/0894a2d5) or newer |
| RT options greyed out because the game detects Wine | the exe patch (3 bytes in 2 places) | only if the game stops reacting to Wine, which is the game's own code |

So even after every Proton ships the RT fixes, **the exe patch is still needed**: removing it puts the game back
to "RT options unavailable", which is a different symptom from the RT crash. No Proton update can fix that half,
because it is not Proton behaviour — per the linked gist the game queries `ntdll!wine_get_version` itself and
zeroes RT capability when it finds Wine. It would stop being needed if CDPR changed that code in a game update.

`--restore` remembers the mode, the paths and which build's backup to use, so it needs no arguments. It also
refuses to overwrite an exe that does not match the backup, in case the game was updated since.

### Steam libraries on other drives

`install.sh` looks for Proton Experimental and The Witcher 3 in every Steam library listed in
`~/.local/share/Steam/steamapps/libraryfolders.vdf`, so they can live on another disk. To use a specific copy of
Proton Experimental, point to it explicitly:

```bash
PROTON_DIR="/mnt/games/SteamLibrary/steamapps/common/Proton - Experimental" bash install.sh
```

If Steam itself is not in `~/.local/share/Steam` (e.g. Flatpak), set `STEAM_DIR` to the main Steam directory
(the one containing `compatibilitytools.d`), not to a secondary library.

### Hybrid graphics (iGPU + dGPU)

If your CPU has an integrated GPU enabled (e.g. Intel UHD 770), Wine exposes **both** GPUs and the game's hardware
detection uses the integrated one: it auto‑selects the *Low* preset, keeps RT locked and "reverts" your graphics
settings. `DXVK_FILTER_DEVICE_NAME` / `VKD3D_FILTER_DEVICE_NAME` / `MESA_VK_DEVICE_SELECT` only change the render
device and are **not enough**. Hide the iGPU's Vulkan driver instead:

```
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json %command%
```

With that, the game auto‑detects the *RT* preset.

## Important notes: do NOT set `PROTON_FSR4_UPGRADE=1`

The Remastered update ships its own up-to-date FFX, so the Proton FSR4 upgrade is not just unnecessary here — it
makes things **worse**. The game labels its options plainly *AMD FSR upscaler* and *AMD FSR frame generation* (it
never advertises an "FSR 4" preset), but the binaries behind them are current generation:

| | game | Proton injects in `umu/` |
|---|---|---|
| `amd_fidelityfx_framegeneration_dx12.dll` | FFX **4.0.1** | FFX 4.0.0 |
| `amd_fidelityfx_upscaler_dx12.dll` | 3.1.5 + `spa` | 3.1.5 + `spa` (identical) |

So the upscaler is the same either way, and the frame-generation library is where the variable hurts: it replaces
the game's **4.0.1** FG with Proton's older **4.0.0** one.

In practice, FSR Frame Generation then stops working: the FSR/XeSS FG options come back greyed out, or are
selectable but apply nothing. This is the same class of problem as
[GE-Proton issue #418](https://github.com/GloriousEggroll/proton-ge-custom/issues/418), where forcing
`PROTON_FSR4_UPGRADE=1` broke natively-FSR4 games. `GE-Proton11-7` does **not** yet ignore the variable for titles
that already support FSR4 — `upscalers.py` substitutes unconditionally whenever the flag is set — so test per game
if you enable it globally.

Also verified in `GE-Proton11-7`:

- `PROTON_FSR4_RDNA3_UPGRADE` is declared in `proton` but consumed nowhere in the Python code: a vestigial flag
  with no effect in this revision.
- `PROTON_USE_OPTISCALER=1` injects OptiScaler's `dxgi.dll`/`d3d12.dll` into `umu/` (not into the game folder, so
  disabling it really is just removing the variable). It works for swapping upscalers, but opening the in-game
  settings menu crashes. Leave it unset and use the game's native FG instead.

### What does NOT work here: DLSS, Multi Frame Generation, DLSS Enabler

Tried on the RDNA 4 machine and **not working**:

- **The game never initialises Streamline in the first place.** This is the same `wine_get_version` check that hides
  RT: when it finds Wine, the game skips `slInit`, so DLSS SR/RR, Reflex, frame generation and DLSS-G are all reported
  as *unsupported* regardless of GPU. Clearing that flag (this repo's patch) restores RT, but this repo **deliberately
  skips** the two extra offsets that would create the Streamline manager under Wine (`0x1B7169B` and `0x1B76620` on the
  hotfix). With no Streamline manager there is nothing for DLSS to attach to. That also explains a loaded-but-idle
  DLSS Enabler: its own log shows it injecting fine (`Loading genuine NGX file …`, then `DLL Loaded`), so the injector
  is not the problem — the manager it needs simply never exists.
- **Applying those DLSS patches on AMD is where it goes wrong.** The linked gist reports that with OptiScaler /
  fakenvapi, applying them made the game exit (one report). That is why this repo keeps them out: in practice they are
  NVIDIA-only. On top of that, OptiScaler's own Streamline interposer collides — a DLSS Enabler log shows
  `Preloader: Streamline Interposer already loaded`. So on an RDNA card there is no supported combination that yields a
  working DLSS option, not a toggle you are missing.
- **x3 Multi Frame Generation cannot work on AMD at all.** DLSS 4 MFG is a hardware frame generator that exists only on
  RTX 50-series (Blackwell) silicon; even plain DLSS-G needs an RTX 40 or newer. An RDNA card has none of that, so this
  is out of reach rather than merely unconfigured.

What *does* exist for AMD is `OptiScaler/dlssg_to_fsr3_amd_is_better.dll`, shipped with OptiScaler, which converts
DLSS Frame Generation output into FSR3 so FG works on RDNA. It is not x3 and it is not DLSS, but it is the closest
thing available. The game itself ships the full NVIDIA stack (`nvngx_dlss*.dll`, `sl.dlss*.dll`, a `streamline/`
directory), so the missing piece is not the files but which ones get loaded and what the menu is allowed to show.

Note that `PROTON_DLSS_UPGRADE=1` does exist, but it is unrelated: it swaps in newer DLSS DLLs for *NVIDIA* GPUs.

### Launch options that work with native FSR FG

```
RADV_PERFTEST=rt WINE_NTSYNC=1 gamemoderun PROTON_LOG=1 %command%
```

In-game: *Graphics → RT* preset, then enable **FSR Frame Generation**. Tick **either** FSR or XeSS FG, never both —
with both enabled the game applies neither.

`PROTON_LOG=1` is optional and only there for debugging: it writes a large log on every launch, so drop it once
things work. None of the four are required for RT either; they are simply what was tested.

On AMD also set `PROTON_DISABLE_NVAPI=1`, which the linked gist recommends for non-NVIDIA GPUs (it is redundant only
if your Proton already disables NVAPI for them). Prepend it to the line above:

```
RADV_PERFTEST=rt WINE_NTSYNC=1 gamemoderun PROTON_DISABLE_NVAPI=1 PROTON_LOG=1 %command%
```

## Known limitations

- **Paths containing spaces are untested.** Everything here was tested on space-free paths
  (`/mnt/games/The Witcher 3 Wild Hunt/...`). The quoting looks correct throughout, but a copy under something like
  `/mnt/My Games/` is unverified.
- Only two GPUs were tried: RDNA 2 and RDNA 4, both on RADV. No Intel/AMD iGPU alongside a dGPU, no Windows, no
  other vendors.
- The exe patch modifies a game binary. It is one game's executable, it only makes the game show its own options,
  and `--restore` puts the original back. Saves and Steam features are untouched.
- **The `5.0.0.1044392` (hotfix) offsets** were reported by gabrielmaialva33 and d1g1talpump; they match that
  build's bytes and are now confirmed in-game with RT and FSR frame generation. The per-GPU numbers below were
  measured on `5.0.0.1041720`.

## What exactly is patched

Build `5.0.0.1041720`:

| Offset      | Original | Patched | Purpose |
|-------------|----------|---------|---------|
| `0x1EE2A53` | `75 0B`  | `90 90` | Clear the Wine flag → RT / path tracing selectable |
| `0x1EE09F7` | `75`     | `EB`    | Keep the Wine buffer‑alignment path |

Build `5.0.0.1044392`:

| Offset      | Original | Patched | Purpose |
|-------------|----------|---------|---------|
| `0x1EDE8F3` | `75 0B`  | `90 90` | Clear the Wine flag → RT / path tracing selectable |
| `0x1EDC897` | `75`     | `EB`    | Keep the Wine buffer‑alignment path |

3 bytes in 2 places, all of them RT/Wine‑related.

The buffer-alignment offset (`0x1EE09F7` / `0x1EDC897`) is only *required* on vkd3d-proton older than
[#3308](https://github.com/HansKristian-Work/vkd3d-proton/pull/3308) (the "tight alignment" change, e.g. stock
`GE-Proton11-7`): there, clearing the Wine flag alone makes the game request tightly-aligned 256-byte buffers, which
get rejected and crash it within seconds. This repo's own build already includes #3308, so on **it** that offset is
harmless rather than load-bearing — but keeping it means the same script still works if you point it at an older
vkd3d-proton.

Offsets are from the gist above (its `--rt` mode). A game update
or Steam's *Verify integrity of game files* undoes the exe patch.

Note that `install.sh` patches four DLL locations per Proton: `files/lib/wine/vkd3d-proton/<arch>` and
`files/lib/wine/<arch>`, for both x86_64 and i386. Only the first one matters in practice — Proton copies from it
into the prefix on every launch — so the second is belt and braces rather than the reason it works.

## Tested on

Two people, two GPUs, same vkd3d‑proton/dxil‑spirv build.

| | Original author | Fork author |
|---|---|---|
| Name | Alejandro Flores Mayorga | Daniel Olano |
| GPU | AMD Radeon RX 6800 XT (Navi 21, RDNA 2), 16 GB | AMD Radeon RX 9060 XT (Navi 44, RDNA 4), 16 GB |
| CPU | Intel Core i5‑13600K (UHD 770 iGPU enabled) | Intel Core i5‑13600K (UHD 770 iGPU enabled) |
| OS | CachyOS, kernel 7.2.2, KDE Plasma (Wayland) | CachyOS, Mesa 26.2.1 |
| Mesa / RADV | 26.2.1 | 26.2.1 |
| Proton | Experimental 11.0 (2026‑09‑24) | GE‑Proton11‑7 via `install.sh --in-place` |
| Game build | `5.0.0.1041720` | `5.0.0.1041720` and `5.0.0.1044392` (both RT + FSR FG) |
| Settings | 2560×1440, *RT* preset, FSR | 2560×1440, *RT* preset, native FSR FG |

Builds used (both are PR branch heads, not commits in the official history — the upstream merges were squashed):

| | |
|---|---|
| vkd3d‑proton | PR #3332 head `3e71c269` (by Felix); merged upstream as `0894a2d5` |
| dxil-spirv | PR #311 head `dcdbadff` |

Results on the original author's RX 6800 XT (first session, ~20 min):

- RT options no longer greyed out; the *RT* preset sticks after reopening the menu and restarting the game.
- No crash on RT pipeline creation and no GPU hang/reset (`dmesg` clean) — the RADV crash described in the gist is
  gone with dxil-spirv PR #311.
- GPU fully engaged with RT on: 99 % busy for the whole 2‑minute sample, ~254 W, ~8.7 GB VRAM (vs ~6.4 GB and
  67–83 % busy at a 72 fps cap without RT).
- In gameplay at 1440p, *RT* preset, FSR Quality: **~45 fps** without frame generation, **~60 fps** with AMD FSR
  frame generation enabled.

On the fork author's RX 9060 XT (GE‑Proton11‑7): RT selectable, preset sticks across restarts, and AMD FSR frame
generation works natively — but **only** with `PROTON_FSR4_UPGRADE` unset. See the notes above.

## Credits

- [gabrielmaialva33](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5) — reverse‑engineering of the Wine flag and patch offsets.
- d1g1talpump — the hotfix (`5.0.0.1044392`) offsets.
- Hans‑Kristian Arntzen and the vkd3d‑proton / dxil‑spirv contributors — the actual RT fixes (PR #3332, PR #311).
- @drizzt — first report of RT working on AMD (RX 7900) with a custom vkd3d‑proton build.

Investigation, scripts and documentation were done with the help of [Claude Code](https://claude.com/claude-code).

---

## Resumen en español

Con la actualización 5.0 (Remastered), el RT no funciona en Linux/Proton por dos motivos: el juego lo **bloquea al
detectar Wine**, y al forzarlo **RADV se cuelga** por un fallo de dxil-spirv que arregla el PR #311 (ya mergeado el
2026‑09‑30). Este repositorio compila vkd3d‑proton con ese arreglo y el PR #3332, lo instala en una **copia aparte** de
Proton Experimental y parchea 3 bytes en 2 sitios del ejecutable (solo los relacionados con el RT).

**Recomendado por el gist (sin tocar la exe): Proton Wineland.** [nanomatters' proton-cachyos releases](https://github.com/nanomatters/proton-cachyos/releases)
trae un Proton que oculta Wine solo para `witcher3.exe` sin tocar los ficheros del juego, sobrevive a las actualizaciones
del juego y ya incluye los fixes de vkd3d-proton que necesita el RT (BLAS size, tight alignment y el fix RADV). Descomprímelo
en `~/.local/share/Steam/compatibilitytools.d/`, reinicia Steam, eligelo en *Compatibilidad* y usa la exe **sin tocar**
(si antes parcheaste con este repo, `bash install.sh --restore`). Matices: en Heroic/Lutris/Faugus el fix por juego necesita
un paso manual (ver #75/#76/#77 del gist), y solo funcionan builds recientes — las antiguas no traen `SteamUtils011` y
crashean. El resto de este resumen describe la ruta de este repo, que sí parchea la exe.

La exe tiene que ser **una de estas dos builds**; `install.sh` rechaza cualquier otra en vez de escribir en offsets
supuestos:

| Build del juego | Build de Steam | SHA256 de la exe sin tocar |
|---|---|---|
| `5.0.0.1041720` (lanzamiento) | 25575366 | `c272b2c2e61f84c7…` |
| `5.0.0.1044392` (hotfix 5.00c) | 25646871 | `9406eccc12b68e08…` |

> **Clona el fork, no el original.** Estos arreglos aún no están en el upstream: la rama `main` del repositorio
> original ([Soyalexf/witcher3-rt-amd-proton](https://github.com/Soyalexf/witcher3-rt-amd-proton)) no los tiene, y si
> clonas ese te llevarás los scripts sin parchear.

Pasos: `bash build.sh` → `bash install.sh` → **reiniciar Steam** → elegir *Proton‑Exp‑RT‑AMD* → preset *RT*.

> **Reiniciar Steam no es opcional.** Steam cachea la lista de herramientas de compatibilidad, así que si
> estaba abierto cuando instalaste, puede no pillar la Proton parcheada y el juego crashea al arrancar. Reiniciando
> Steam se arregla. Pasó en la práctica en la máquina RDNA 4: instalar con Steam abierto → crash al iniciar → cerrar
> Steam del todo y volver a abrir → funcionó.

Para deshacer: `bash install.sh --restore`.

**Si te crashea al empezar una partida nueva**: en la máquina RDNA 4, arrancar partida nueva en el hotfix crasheaba
con RT y frame generation todavía activados de la sesión anterior. Lo que funcionó: desactivar **RT** y **frame
generation**, empezar la partida, y una vez dentro volver a activarlos desde el preset *RT*. Es una observación de una
sola máquina, no una causa diagnosticada, así que trátalo como apaño.

**Lo que NO funciona aquí**: el **DLSS Enabler** y el **Multi Frame Generation x3**.

La causa es la misma que con el RT: al detectar Wine, el juego no llama a `slInit`, así que Streamline ni se crea y DLSS
SR/RR, Reflex, frame generation y DLSS-G aparecen como *no soportados*. Quitar ese flag (el parche de este repo) recupera
el RT, pero **a propósito** no aplicamos los dos offsets extra que crearían el manager de Streamline bajo Wine (`0x1B7169B`
y `0x1B76620` en el hotfix). Sin ese manager no hay dónde engancharse DLSS. Por eso un DLSS Enabler puede cargar bien (su log
muestra que inyecta su DLL) y aun así no servir de nada: el problema no es el inyector, sino que el manager nunca existe.

Además, aplicar esos parches de DLSS **en AMD** es justo donde se rompe: el gist enlazado reporta que con OptiScaler /
fakenvapi hacían salir el juego (un reporte). Por eso este repo los deja fuera; en la práctica son solo de NVIDIA. Y por
encima, OptiScaler mete su propio interposer de Streamline (`Preloader: Streamline Interposer already loaded`). Así que en
una GPU RDNA no hay combinación soportada que dé una opción de DLSS funcional: no es un ajuste que falte.

El **x3 Multi Frame Generation no puede funcionar en AMD**: es un generador de frames por hardware que solo existe en las
RTX 50 (Blackwell), y hasta el DLSS-G normal necesita una RTX 40 o superior. Una GPU RDNA no tiene ese hardware, así que
esto está fuera de alcance, no sin configurar.

Lo que sí existe para AMD es `OptiScaler/dlssg_to_fsr3_amd_is_better.dll`, que viene con OptiScaler y convierte la salida
de DLSS Frame Generation en FSR3 para que el FG funcione en RDNA. No es x3 ni es DLSS, pero es lo más parecido que hay. El
juego trae la pila de NVIDIA completa (`nvngx_dlss*.dll`, `sl.dlss*.dll`, directorio `streamline/`), así que lo que falta
no son los ficheros sino cuáles se cargan y qué puede mostrar el menú.

Si usas una copia que no es de Steam (GOG, Lutris) o una build de Proton‑GE concreta, `install.sh --in-place`
sustituye las DLL de vkd3d‑proton **dentro** de Proton en vez de crear una copia: sin copia, sin entrada nueva en
*Compatibilidad* y sin tocar los prefix ni las partidas.

```bash
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest" \
GAME_EXE="/mnt/games/The Witcher 3 Wild Hunt/bin/x64_dx12/witcher3.exe" bash install.sh --in-place
```

En una copia que no es de Steam no hay prefix localizable por nombre, así que `install.sh` no puede refrescarlo
solo. Añade `COMPAT_APPID=<appid>` para que lo parchee en la misma pasada; es opcional, porque Proton vuelve a
copiar esas DLLs al prefix en el siguiente arranque igualmente.

Ojo: al actualizar Proton (ProtonUp-Qt, Steam…) sus DLLs vuelven a las originales y hay que re‑ejecutar
`--in-place`; en cuanto una release traiga vkd3d‑proton
[`0894a2d5`](https://github.com/HansKristian-Work/vkd3d-proton/commit/0894a2d5) o superior, ese paso sobra.

Los dos parches caducan por separado: el de las DLL desaparecerá cuando Proton traiga los arreglos de
vkd3d/dxil‑spirv, pero **el del ejecutable hará falta siempre**. No es comportamiento de Proton que se pueda
arreglar en una actualización: según el gist enlazado arriba, el propio juego consulta `ntdll!wine_get_version` y
pone RT a cero cuando detecta Wine. Solo dejaría de hacer falta si CDPR cambiara ese código en una actualización.

Si Proton Experimental o el juego están en otra biblioteca de Steam (otro disco), `install.sh` los encuentra solo
leyendo `steamapps/libraryfolders.vdf`. Para usar una copia concreta de Proton:
`PROTON_DIR="/ruta/a/Proton - Experimental" bash install.sh`. `STEAM_DIR` debe apuntar siempre a la carpeta
principal de Steam, no a una biblioteca secundaria.

Si tienes gráfica integrada activa (Intel/AMD iGPU), usa las opciones de lanzamiento `VK_DRIVER_FILES=…radeon_icd.json`
de arriba; si no, el juego detecta la integrada, elige *Bajo* y bloquea el RT.

**Opciones de lanzamiento**: las probadas son `RADV_PERFTEST=rt WINE_NTSYNC=1 gamemoderun %command%` (ver arriba). En
AMD añade también `PROTON_DISABLE_NVAPI=1`, que el gist recomienda para GPUs no NVIDIA. `PROTON_LOG=1` es opcional y solo
para depurar: escribe un log grande en cada arranque, así que quítalo cuando ya funcione.

Lo que **no** está probado: las rutas con espacios (todo se probó en rutas sin espacios). Los offsets del hotfix
`5.0.0.1044392` fueron reportados por gabrielmaialva33 y d1g1talpump, coinciden con los bytes de esa build y ya están
confirmados in-game (RT y FSR frame generation).

## License

Scripts: MIT. This repo contains no game files and no binaries.