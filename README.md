# PalworldPinItems

Keep crafting and building materials on screen while you play Palworld. Hover a recipe, pin it, and track what you own against what you need in a compact panel at the top left.

- Recipe and material icons, with **owned/needed** counts such as `Wood: 15/2`.
- Green checkmarks when you have enough of a material.
- Backpack counts plus accessible chest stock in your **current base**. Different bases' stock stays separate; outside a base, only your backpack counts.
- Up to five whole recipe cards on the HUD, without scrolling. The **Pinned** player-menu entry shows the full list in pages of five.
- A red **X** on each recipe removes that pin.

Tested on Windows Steam Palworld `1.0.5.102999`. The author confirmed this UI-and-shortcut version works after the later performance experiment was reverted. This is a client-side mod; remote multiplayer, locked/private chest access, and other platforms have not been verified. Pins last for the current game session and reset when the game restarts.

## How to use

1. Open a workbench's crafting menu, or press **B** to open the build menu.
2. Hover the recipe you want to track. Press **G**, or click **Pin this item** on the panel.
3. Close the menu. The recipe and its material counts stay on screen.
4. Open the player menu and click **Pinned** to see additional recipes. Use **Previous** and **Next** to change pages, then **Close** or select a native tab to return.

| Action | Control |
| --- | --- |
| Pin or unpin the hovered recipe | **G**, or **Pin this item / Unpin this item** |
| Remove one pinned recipe | Its red **X** |
| Clear every pin | **Shift+G**, or **Clear pins** |
| Browse the full list | Player menu → **Pinned** → **Previous / Next** |

Mouse buttons need a game menu open so the cursor is available. The mod does not take over the cursor during gameplay. Click the Pinned menu entry directly; native keyboard/controller tab cycling still visits the game's original tabs.

The HUD fits whole cards above the bottom-left Pal icons, so a small viewport or recipes with many ingredients can show fewer than five cards. Extra pins remain on the Pinned page. Recipes that craft a batch show their output quantity.

Within a base, moving materials between its chests and your backpack should leave the combined count unchanged. Collecting, spending, or dropping materials changes it. The scope label shows `Backpack + Base 5`, for example, using the number in the game's underlying base name. If that name has no number, it shows `Backpack + current base`. This changes only the mod's label, not the base's actual name or save data.

## Installation: Windows Steam

You need Palworld, a compatible UE4SS loader, and a **built copy of this mod**. The GitHub repository contains source; the cooked `.pak` is a local build output and is not included in a source checkout. Players do not need Unreal Engine, PMK, Wwise, Python, or an MCP server.

1. **Close Palworld.** In Steam, right-click Palworld → **Properties** → **Installed Files** → **Browse**. This opens the game folder containing `Pal`, `Engine`, and `Palworld.exe`.
2. Install the [Palworld-compatible UE4SS loader used for testing](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld). Choose the player archive, `UE4SS-Palworld.zip`, and follow its [client installation guide](https://pwmodding.wiki/docs/users/ue4ss/installation). Place the archive's `ue4ss` folder and `dwmapi.dll` in `Pal/Binaries/Win64`, preserving the loader's configuration files. The loader maintainer warns that running manual and Workshop copies together causes crashes; use one loader installation.
3. Copy the supplied mod package's **`Pal` folder** into the game folder and merge it with the existing `Pal` folder. Keep other mods' folders and files.
4. Confirm the files below are present. The empty `enabled.txt` enables the Lua mod. If your UE4SS setup uses `ue4ss/Mods/mods.txt`, enable the entry `PalworldPinItems : 1` there while preserving its other entries.
5. Launch Palworld, enter a world, and hover a crafting or building recipe to pin it.

The mod's installed layout is:

```text
Palworld/
└── Pal/
    ├── Binaries/Win64/ue4ss/Mods/PalworldPinItems/
    │   ├── enabled.txt
    │   └── Scripts/
    │       ├── main.lua
    │       ├── recipes.lua
    │       ├── ui.lua
    │       ├── inventory.lua
    │       └── storage.lua
    └── Content/Paks/PalworldPinItems_P.pak
```

Both the Lua files and `.pak` are required. Do not copy the repository's uncooked `.uasset` files into the game.

### Update or uninstall

Close Palworld before replacing files. To update, replace this mod's five scripts and `.pak` together. To uninstall, remove `Pal/Binaries/Win64/ue4ss/Mods/PalworldPinItems` and `Pal/Content/Paks/PalworldPinItems_P.pak`, then remove its entry from `mods.txt` if you added one. Leave the shared UE4SS loader installed if other mods use it.

If the panel does not appear, first hover a valid recipe: it stays hidden when nothing is hovered or pinned. Check both installation paths and `enabled.txt`. The loader log at `Pal/Binaries/Win64/ue4ss/UE4SS.log` should contain `[PalworldPinItems] Loaded`. Palworld updates may change the UI classes or APIs this mod uses.

## Sharing with friends

After building, send the **contents of `build/package`**: its `README.md` and complete `Pal` folder. The package includes only this mod's `.pak`, five Lua modules, and `enabled.txt`; it does not bundle UE4SS. Each friend installs a compatible loader separately, then copies `Pal` into their own game folder as described above.

Do not send the SDK, Unreal project, `Saved`, `Intermediate`, `.venv`, `graphify-out`, logs, diagnostic scripts, or previous-install backups. A ZIP is optional; this project's normal build creates a folder and `.pak` without creating an archive.

## Building and local installation

The standalone cooking project uses **Unreal Engine 5.1.1**. Run these commands from the repository folder in PowerShell:

```powershell
# Build the cooked UI pak and ready-to-copy package folder.
./Build.ps1 -EngineRoot 'C:\Program Files\Epic Games\UE_5.1'

# Install into a local Steam game with UE4SS already installed.
./Install.ps1 -GameRoot 'C:\Program Files (x86)\Steam\steamapps\common\Palworld'
```

The build outputs are `build/PalworldPinItems_P.pak` and `build/package`. Change the paths if your engine or game is elsewhere. `Install.ps1` checks that Palworld is closed and preserves the previous mod installation under `build/previous-install`. ZIP creation is opt-in with `Build.ps1 -CreateZip`; do not use it unless an archive is wanted.

Lua regression tests use the development-only Lupa dependency:

```powershell
py -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements-dev.txt
./.venv/Scripts/python.exe tests/run.py
```

The runtime consists of UE4SS Lua and five UMG Widget Blueprints. Game textures and recipe data are read at runtime; game textures are not redistributed. Implementation and validation details are in [UI.md](UI.md), [BASE_STORAGE.md](BASE_STORAGE.md), and [PERFORMANCE.md](PERFORMANCE.md).

This repository contains only PalworldPinItems. Unreal generated files, local build output, ZIPs, and `graphify-out/` are ignored. In the parent mod workspace, shared skills stay at its root; run Graphify from this mod folder with scan root `.`. Binary Unreal assets are represented by the UI documentation because Graphify does not parse `.uasset` files.
