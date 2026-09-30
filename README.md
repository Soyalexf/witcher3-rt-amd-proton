# The Witcher 3 Remastered (5.0) — Ray Tracing on AMD under Proton

**Status: working** on an RX 6800 XT (RDNA 2) with RADV — experimental, use at your own risk.

With the 5.0 "Remastered" update (build `5.0.0.1041720`, Steam build `25575366`, 2026‑09‑29), ray tracing is
unavailable on Linux/Proton for two independent reasons:

1. **The game disables RT when it detects Wine.** `witcher3.exe` queries `ntdll!wine_get_version` and sets a cached
   "Wine / Steam hardware" flag that zeroes the ray‑tracing capability, so every RT and path‑tracing option is
   greyed out regardless of the GPU. (Found and documented by
   [gabrielmaialva33's gist](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5).)
2. **Forcing it on crashes RADV** while creating the RT pipelines, because dxil-spirv emits invalid SPIR‑V for the
   `PTRGSFinal` raygen shader. This is fixed by the still‑draft
   [dxil-spirv PR #311](https://github.com/HansKristian-Work/dxil-spirv/pull/311); RTAS sizing also needs
   [vkd3d-proton PR #3332](https://github.com/HansKristian-Work/vkd3d-proton/pull/3332).

This repo combines both: it builds vkd3d‑proton with those two PRs, installs it into a **separate copy** of
Proton Experimental (the original is untouched), and patches only the two RT‑related bytes of the exe
(none of the NVIDIA/DLSS patches).

## Requirements

- The Witcher 3 exe **exactly** `5.0.0.1041720` — SHA256
  `c272b2c2e61f84c758e28fab69ab2915944dd1e539dbb435fae9fc67494c7e25` (the installer refuses anything else).
- Proton Experimental installed in Steam (11.0, 2026‑09‑24 or newer). GE‑Proton10‑34 does **not** work with this
  build at all: it lacks the `SteamUtils011` interface and the game hangs at start.
- Build tools (Arch/CachyOS): `sudo pacman -S git meson ninja glslang wine mingw-w64-gcc`

## Usage

```bash
git clone https://github.com/Soyalexf/witcher3-rt-amd-proton.git
cd witcher3-rt-amd-proton
bash build.sh      # clones vkd3d-proton + both PRs and builds the DLLs (a few minutes)
bash install.sh    # creates "Proton Experimental RT-AMD" and patches witcher3.exe (game must be closed)
```

Then restart Steam, select **Proton Experimental RT-AMD** under *Properties → Compatibility*, and pick the **RT**
preset in *Graphics*.

To undo everything: `bash install.sh --restore` (or *Verify integrity of game files* in Steam for the exe).

### Hybrid graphics (iGPU + dGPU)

If your CPU has an integrated GPU enabled (e.g. Intel UHD 770), Wine exposes **both** GPUs and the game's hardware
detection uses the integrated one: it auto‑selects the *Low* preset, keeps RT locked and "reverts" your graphics
settings. `DXVK_FILTER_DEVICE_NAME` / `VKD3D_FILTER_DEVICE_NAME` / `MESA_VK_DEVICE_SELECT` only change the render
device and are **not enough**. Hide the iGPU's Vulkan driver instead:

```
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json %command%
```

With that, the game auto‑detects the *RT* preset on a 6800 XT.

## What exactly is patched

| Offset      | Original | Patched | Purpose |
|-------------|----------|---------|---------|
| `0x1EE2A53` | `75 0B`  | `90 90` | Clear the Wine flag → RT / path tracing selectable |
| `0x1EE09F7` | `75`     | `EB`    | Keep the Wine buffer‑alignment path |

Offsets are from the gist above (its `--rt` mode). A game update or file verification undoes the patch.

## Tested on

| | |
|---|---|
| GPU | AMD Radeon RX 6800 XT (Navi 21, RDNA 2), 16 GB |
| CPU | Intel Core i5‑13600K (UHD 770 iGPU enabled) |
| OS  | CachyOS, kernel 7.2.2, KDE Plasma (Wayland) |
| Mesa / RADV | 26.2.1 |
| Proton | Experimental 11.0 (2026‑09‑24) + this vkd3d-proton build |
| vkd3d-proton | `3e71c269` (PR #3332 on top of `4d06d745`) |
| dxil-spirv | `dcdbadff` (PR #311) |
| Settings | 2560×1440, *RT* preset (RT GI performance, RT reflections, RT shadows performance), FSR |

Results: RESULTS_PLACEHOLDER

## Credits

- [gabrielmaialva33](https://gist.github.com/gabrielmaialva33/33ebb2542f0513d55100b22aa2149ff5) — reverse‑engineering of the Wine flag and patch offsets.
- Hans‑Kristian Arntzen and the vkd3d‑proton / dxil‑spirv contributors — the actual RT fixes (PR #3332, PR #311).
- @drizzt — first report of RT working on AMD (RX 7900) with a custom vkd3d‑proton build.

Investigation, scripts and documentation were done with the help of [Claude Code](https://claude.com/claude-code).

---

## Resumen en español

Con la actualización 5.0 (Remastered), el RT no funciona en Linux/Proton por dos motivos: el juego lo **bloquea al
detectar Wine**, y al forzarlo **RADV se cuelga** por un fallo de dxil‑spirv que arregla el PR #311 (todavía en
borrador). Este repositorio compila vkd3d‑proton con ese arreglo y el PR #3332, lo instala en una **copia aparte** de
Proton Experimental y parchea solo los 2 bytes del ejecutable relacionados con el RT.

Pasos: `bash build.sh` → `bash install.sh` → reiniciar Steam → elegir *Proton Experimental RT-AMD* → preset *RT*.
Para deshacer: `bash install.sh --restore`.

Si tienes gráfica integrada activa (Intel/AMD iGPU), usa las opciones de lanzamiento `VK_DRIVER_FILES=…radeon_icd.json`
de arriba; si no, el juego detecta la integrada, elige *Bajo* y bloquea el RT.

## License

Scripts: MIT. This repo contains no game files and no binaries.
