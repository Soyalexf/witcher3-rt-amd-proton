# The Witcher 3 Remastered (5.0) — Ray Tracing on AMD under Proton

**Status: working** on RX 6800 XT (RDNA 2) and RX 9060 XT (RDNA 4) with RADV — experimental, use at your own risk.

With the 5.0 "Remastered" update (build `5.0.0.1041720`, Steam build `25575366`, 2026‑09‑29), ray tracing is
unavailable on Linux/Proton for two independent reasons:

1. **The game disables RT when it detects Wine.** `witcher3.exe` queries `ntdll!wine_get_version` and sets a cached
   "Wine / Steam hardware" flag that zeroes the ray‑tracing capability, so every RT and path‑tracing option is
   greyed out regardless of the GPU. (Found and documented by
   [gabrielmaialva33's gist](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5).)
2. **Forcing it on crashes RADV** while creating the RT pipelines, because dxil-spirv emits invalid SPIR‑V for the
   `PTRGSFinal` raygen shader. This is fixed by
   [dxil-spirv PR #311](https://github.com/HansKristian-Work/dxil-spirv/pull/311); RTAS sizing also needs
   [vkd3d-proton PR #3332](https://github.com/HansKristian-Work/vkd3d-proton/pull/3332). Both were merged upstream on 2026‑09‑30.

This repo combines both: it builds vkd3d‑proton with those two PRs, installs it into a **separate copy** of
Proton Experimental (the original is untouched), and patches only the two RT‑related bytes of the exe
(none of the NVIDIA/DLSS patches).

The two halves are independent: a Proton release will eventually ship the vkd3d/dxil‑spirv fixes, but the
exe patch will still be needed, because the game disabling RT on seeing Wine is the game's own doing and no
Proton update changes it. See *The two halves have different lifetimes*.

## Requirements

- The Witcher 3 exe **exactly** `5.0.0.1041720` — SHA256
  `c272b2c2e61f84c758e28fab69ab2915944dd1e539dbb435fae9fc67494c7e25` (the installer refuses anything else).
- Proton Experimental installed in Steam (11.0, 2026‑09‑24 or newer). GE‑Proton10‑34 does **not** work with this
  build at all: it lacks the `SteamUtils011` interface and the game hangs at start.
- **Recommended: `GE-Proton11-7`** (or newer). `install.sh` works against any Proton via `PROTON_DIR`, but
  `GE-Proton11-7` is the revision the native FSR frame generation above was verified against, and the FSR4 notes
  below describe that revision's behaviour. Older GE builds may not behave the same way.
- Build tools (Arch/CachyOS): `sudo pacman -S git meson ninja glslang wine mingw-w64-gcc`

## Usage

```bash
git clone https://github.com/daeduol/witcher3-rt-amd-proton.git
cd witcher3-rt-amd-proton
bash build.sh      # clones vkd3d-proton + both PRs and builds the DLLs (a few minutes)
bash install.sh    # copies Proton Experimental to "Proton-Exp-RT-AMD" and patches witcher3.exe (game must be closed)
```

> **Clone the fork, not the original.** These fixes are not upstream yet. The `main` branch of
> the original repository ([Soyalexf/witcher3-rt-amd-proton](https://github.com/Soyalexf/witcher3-rt-amd-proton))
> does not have them, and cloning it gives you the unpatched scripts.

Then restart Steam, select **Proton-Exp-RT-AMD** under *Properties → Compatibility*, and pick the **RT**
preset in *Graphics*.

To undo everything: `bash install.sh --restore` (or *Verify integrity of game files* in Steam for the exe).

`install.sh --dry-run` prints the Proton, the exe and the mode it would use and changes nothing.

### Non-Steam copies of the game, and patching the Proton you already use

`GAME_EXE` and `PROTON_DIR` (formerly `PROTON_EXP_DIR`) override the automatic lookup, so the same two patches
work for a GOG/Lutris copy or for any Proton-GE build. `install.sh` checks the SHA256 of whatever exe you
point it at and refuses anything that is not build 5.0.0.1041720, GOG included — so a GOG copy of that build
is patched identically, and a different build is rejected instead of being patched at the wrong offsets.

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
refresh it up front. Add `COMPAT_APPID=<appid>` to have it patched in the same run; it is optional, because
Proton re‑syncs those DLLs into the prefix on the next launch anyway:

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
  `3e71c269` or newer, this step is no longer needed at all.

### The two halves have different lifetimes

These are unrelated problems, so they do not become obsolete together:

| Problem | Fixed by | Goes away when |
|---|---|---|
| RT crashes on RADV / DX12 check fails | vkd3d‑proton + dxil‑spirv (the DLL patch) | a Proton release ships `3e71c269` or newer |
| RT options greyed out because the game detects Wine | the 2‑byte exe patch | only if the game stops reacting to Wine, which is the game's own code |

So even after every Proton ships the RT fixes, **the exe patch is still needed**: removing it puts the game
back to "RT options unavailable", which is a different symptom from the RT crash. No Proton update can fix
that half, because it is not Proton behaviour — per the linked gist the game queries `ntdll!wine_get_version`
itself and zeroes RT capability when it finds Wine. It would stop being needed if CDPR changed that code in
a game update, which is the same as saying a future build might not need it.

`--restore` remembers the mode and the paths of the last install, so it needs no arguments.

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

With that, the game auto‑detects the *RT* preset on a 6800 XT.


## Important notes: do NOT set `PROTON_FSR4_UPGRADE=1`

The Remastered update ships its own up-to-date FFX, so the Proton FSR4 upgrade is not just unnecessary here —
it makes things **worse**. The game labels its options plainly *AMD FSR upscaler* and *AMD FSR frame
generation* (it never advertises an "FSR 4" preset), but the binaries behind them are current generation:

| | game | Proton injects in `umu/` |
|---|---|---|
| `amd_fidelityfx_framegeneration_dx12.dll` | FFX **4.0.1** | FFX 4.0.0 |
| `amd_fidelityfx_upscaler_dx12.dll` | 3.1.5 + `spa` | 3.1.5 + `spa` (identical) |

So the upscaler is the same either way, and the frame-generation library is where the variable hurts: it
replaces the game's **4.0.1** FG with Proton's older **4.0.0** one.

In practice, FSR Frame Generation then stops working: the FSR/XeSS FG options come back greyed out, or are
selectable but apply nothing. This is the same class of problem as [GE-Proton issue #418](https://github.com/GloriousEggroll/proton-ge-custom/issues/418),
where forcing `PROTON_FSR4_UPGRADE=1` broke natively-FSR4 games. `GE-Proton11-7` does **not** yet ignore the
variable for titles that already support FSR4 — `upscalers.py` substitutes unconditionally whenever the flag is
set — so test per game if you enable it globally.

Also verified in `GE-Proton11-7`:

- `PROTON_FSR4_RDNA3_UPGRADE` is declared in `proton` but consumed nowhere in the Python code: a vestigial flag
  with no effect in this revision.
- `PROTON_USE_OPTISCALER=1` injects OptiScaler's `dxgi.dll`/`d3d12.dll` into `umu/` (not into the game folder,
  so disabling it really is just removing the variable). It works for swapping upscalers, but opening the
  in-game settings menu crashes. Leave it unset and use the game's native FG instead.

### Launch options that work with native FSR FG

```
RADV_PERFTEST=rt WINE_NTSYNC=1 gamemoderun PROTON_LOG=1 %command%
```

In-game: *Graphics → RT* preset, then enable **FSR Frame Generation**. Tick **either** FSR or XeSS FG, never
both — with both enabled the game applies neither.

## What exactly is patched

| Offset      | Original | Patched | Purpose |
|-------------|----------|---------|---------|
| `0x1EE2A53` | `75 0B`  | `90 90` | Clear the Wine flag → RT / path tracing selectable |
| `0x1EE09F7` | `75`     | `EB`    | Keep the Wine buffer‑alignment path |

Offsets are from the gist above (its `--rt` mode). A game update or file verification undoes the patch.

## Tested on

| | |
|---|---|
| GPU | AMD Radeon RX 6800 XT (Navi 21, RDNA 2), 16 GB, and AMD Radeon RX 9060 XT (Navi 44, RDNA 4), 16 GB |
| CPU | Intel Core i5‑13600K (UHD 770 iGPU enabled) |
| OS  | CachyOS, kernel 7.2.2, KDE Plasma (Wayland) |
| Mesa / RADV | 26.2.1 |
| Proton | Experimental 11.0 (2026‑09‑24) + this vkd3d-proton build; native FSR FG additionally verified on **GE‑Proton11‑7** (`install.sh --in-place`) |
| vkd3d-proton | `3e71c269` (PR #3332 on top of `4d06d745`) |
| dxil-spirv | `dcdbadff` (PR #311) |
| Settings | 2560×1440, *RT* preset (RT GI performance, RT reflections, RT shadows performance), FSR |

Results (first session, ~20 min):

- RT options no longer greyed out; the *RT* preset sticks after reopening the menu and restarting the game.
- No crash on RT pipeline creation and no GPU hang/reset (`dmesg` clean) — the RADV crash described in the gist is
  gone with dxil-spirv PR #311.
- GPU fully engaged with RT on: 99 % busy for the whole 2‑minute sample, ~254 W, ~8.7 GB VRAM
  (vs ~6.4 GB and 67–83 % busy at a 72 fps cap without RT).
- In gameplay at 1440p, *RT* preset, FSR Quality: **~45 fps** without frame generation, **~60 fps** with AMD FSR
  frame generation enabled.
- On the RDNA 4 card (GE‑Proton11‑7): RT selectable, preset sticks across restarts, and AMD FSR frame generation
  works natively — but **only** with `PROTON_FSR4_UPGRADE` unset. See the notes above.

## Credits

- [gabrielmaialva33](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5) — reverse‑engineering of the Wine flag and patch offsets.
- Hans‑Kristian Arntzen and the vkd3d‑proton / dxil‑spirv contributors — the actual RT fixes (PR #3332, PR #311).
- @drizzt — first report of RT working on AMD (RX 7900) with a custom vkd3d‑proton build.

Investigation, scripts and documentation were done with the help of [Claude Code](https://claude.com/claude-code).

---

## Resumen en español

Con la actualización 5.0 (Remastered), el RT no funciona en Linux/Proton por dos motivos: el juego lo **bloquea al
detectar Wine**, y al forzarlo **RADV se cuelga** por un fallo de dxil‑spirv que arregla el PR #311 (ya
mergeado el 2026‑09‑30). Este repositorio compila vkd3d‑proton con ese arreglo y el PR #3332, lo instala en una **copia aparte** de
Proton Experimental y parchea solo los 2 bytes del ejecutable relacionados con el RT.

Pasos: `bash build.sh` → `bash install.sh` → reiniciar Steam → elegir *Proton‑Exp‑RT‑AMD* → preset *RT*.

> **Clona el fork, no el original.** Estos arreglos aún no están en el upstream: la rama `main` del
> repositorio original ([Soyalexf/witcher3-rt-amd-proton](https://github.com/Soyalexf/witcher3-rt-amd-proton))
> no los tiene, y si clonas ese te llevarás los scripts sin parchear.
Para deshacer: `bash install.sh --restore`.

Si usas una copia que no es de Steam (GOG, Lutris) o una build de Proton‑GE concreta, `install.sh --in-place` sustituye las
DLL de vkd3d‑proton **dentro** de Proton en vez de crear una copia: sin copia, sin entrada nueva en
*Compatibilidad* y sin tocar los prefix ni las partidas.

```bash
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/Proton-GE Latest" \
GAME_EXE="/mnt/games/The Witcher 3 Wild Hunt/bin/x64_dx12/witcher3.exe" bash install.sh --in-place
```

El `witcher3.exe` de GOG de la build 5.0.0.1041720 se parchea igual: `install.sh` comprueba el SHA256 de la exe
que le apuntes y rechaza cualquier build que no sea esa, en vez de escribir en offsets equivocados.

Ojo: al actualizar Proton (ProtonUp-Qt, Steam…) sus DLLs vuelven a las originales y hay que
re‑ejecutar `--in-place`; en cuanto una release traiga vkd3d‑proton `3e71c269` o superior, ese paso sobra.

Los dos parches caducan por separado: el de las DLL desaparecerá cuando Proton traiga los arreglos de
vkd3d/dxil‑spirv, pero **el del ejecutable hará falta siempre**. No es comportamiento de Proton que se pueda
arreglar en una actualización: según el gist enlazado arriba, el propio juego consulta
`ntdll!wine_get_version` y pone RT a cero cuando detecta Wine. Solo dejaría de hacer falta si CDPR cambiara ese
código en una actualización del juego.

En una copia que no es de Steam no hay prefix localizable por nombre, así que `install.sh` no puede refrescarlo
solo. Añade `COMPAT_APPID=<appid>` para que lo parchee en la misma pasada; es opcional, porque Proton vuelve a
copiar esas DLLs al prefix en el siguiente arranque igualmente.

Si Proton Experimental o el juego están en otra biblioteca de Steam (otro disco), `install.sh` los encuentra solo
leyendo `steamapps/libraryfolders.vdf`. Para usar una copia concreta de Proton:
`PROTON_DIR="/ruta/a/Proton - Experimental" bash install.sh`. `STEAM_DIR` debe apuntar siempre a la carpeta
principal de Steam, no a una biblioteca secundaria.

Si tienes gráfica integrada activa (Intel/AMD iGPU), usa las opciones de lanzamiento `VK_DRIVER_FILES=…radeon_icd.json`
de arriba; si no, el juego detecta la integrada, elige *Bajo* y bloquea el RT.

## License

Scripts: MIT. This repo contains no game files and no binaries.
