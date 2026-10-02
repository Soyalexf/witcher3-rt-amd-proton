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

### What does NOT work here: Streamline, Multi Frame Generation, DLSS Enabler

Tried on the RDNA 4 machine and **not working**, so do not spend time on it:

- **OptiScaler via Streamline for x3 Multi Frame Generation.** `GE-Proton11-7` has no Streamline support at all:
  the `proton` script never references Streamline, and there is no `nvngx.dll` anywhere in the Proton tree.
- **DLSS Enabler.** Same reason — it works by injecting `nvngx`, which is not there.

So the only frame generation available on this setup is the game's own **AMD FSR frame generation**, plus XeSS in
the menu. That is what the numbers below were measured with.

Note that `PROTON_DLSS_UPGRADE=1` does exist, but it is not this: it swaps in newer DLSS DLLs for *NVIDIA* GPUs.
It has no useful effect on an AMD card and is not a substitute for the above.

Do **not** try to enable these alongside the game's FG. More than one frame generator active at once is the one
combination that reliably broke things in testing (see the FSR/XeSS note above).

### Launch options that work with native FSR FG

```
RADV_PERFTEST=rt WINE_NTSYNC=1 gamemoderun PROTON_LOG=1 %command%
```

In-game: *Graphics → RT* preset, then enable **FSR Frame Generation**. Tick **either** FSR or XeSS FG, never both —
with both enabled the game applies neither.

`PROTON_LOG=1` is optional and only there for debugging: it writes a large log on every launch, so drop it once
things work. None of the four are required for RT either; they are simply what was tested.

## Known limitations

- **Paths containing spaces are untested.** Everything here was tested on space-free paths
  (`/mnt/games/The Witcher 3 Wild Hunt/...`). The quoting looks correct throughout, but a copy under something like
  `/mnt/My Games/` is unverified.
- Only two GPUs were tried: RDNA 2 and RDNA 4, both on RADV. No Intel/AMD iGPU alongside a dGPU, no Windows, no
  other vendors.
- The exe patch modifies a game binary. It is one game's executable, it only makes the game show its own options,
  and `--restore` puts the original back. Saves and Steam features are untouched.
- **The hotfix offsets are unverified in-game.** The `5.0.0.1044392` offsets were reported by gabrielmaialva33 and
  d1g1talpump and are confirmed to match that build's bytes, but the game has not been run with them. The
  `5.0.0.1041720` offsets are the ones everything below was measured with.

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

3 bytes in 2 places, all of them RT/Wine‑related. Offsets are from the gist above (its `--rt` mode). A game update
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
| Game build | `5.0.0.1041720` | `5.0.0.1041720`, plus `5.0.0.1044392` patched but not yet run |
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

**Lo que NO funciona aquí**: OptiScaler vía Streamline para el Multi Frame Generation x3, y el DLSS Enabler.
`GE-Proton11-7` no tiene soporte de Streamline: su script `proton` no lo menciona en ningún sitio y no hay ningún
`nvngx.dll` en el árbol de la Proton. Por lo tanto el único frame generation disponible es el **AMD FSR** nativo del
juego (o XeSS desde el menú), que es con lo que están medidos los números de arriba. `PROTON_DLSS_UPGRADE=1` sí
existe, pero cambia DLLs de DLSS para GPUs **NVIDIA**, no sirve en AMD y no es sustituto de lo anterior.

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

Lo que **no** está probado: rutas con espacios (todo se probó en rutas sin espacios), y los offsets del hotfix
`5.0.0.1044392` están confirmados contra los bytes de esa build pero el juego no se ha ejecutado con ellos.

## License

Scripts: MIT. This repo contains no game files and no binaries.