# PalworldPinItems

Client-side Palworld mod: hover a craftable item or building, choose **Pin this item**, and keep its material requirements in the top-right corner after closing the menu. Multiple recipes can be pinned. Hover a pinned recipe again to unpin it; the panel also has a Clear pins button.

Each pin shows the recipe's icon and name, then material icons and **owned/needed** counts, for example `Wood: 15/2`. A green game checkmark marks each material you have enough of. Owned counts come from your personal inventory and update while the pin remains on screen; base storage is not included. Recipes producing a batch show their output count. Pins last for the current game session. Recipe data, item names, and owned counts come from the running game; no costs are hardcoded.

The compact amber and navy panel shows at most five pins without scrolling. Additional pins remain available through the **Pinned** entry in the player menu, with five items per page and Previous/Next buttons. Click this additional entry directly; the game's native tab-cycling keys still cycle its original tabs.

Implementation: UE4SS Lua plus five small UMG Widget Blueprints cooked with Unreal Engine 5.1.1. The widget source stays in `Content/Mods/PalworldPinItems`; PMK only mounts that directory while authoring. This mod does not change crafting, item tables, server state, or save files.

## Development status

The first live test confirmed workbench pinning, and exposed a failure in the B build menu. The corrected build reads hovered construction icons and displays live personal-inventory counts as needed/owned. The next live run crashed before those features could be checked; matching UE4SS symbols identify the abort in native `FText:ToString()`. Failed recipe lookups and building IDs without an item name could reach that conversion. The crash fix checks recipe lookup success and verifies static item data before requesting a localized label; buildings without a blueprint item use their building ID as a fallback. Regression tests reproduce the unsafe lookup before the fix and pass after it, alongside B-menu and changing-inventory checks. On 2026-10-10, the user confirmed the installed crash fix works without crashing: both the B menu and workbench pinning work, and needed/owned counts update correctly. Runtime logs also record building and crafting pin actions. Installed and packaged Lua match the tested source. This is a development build.

## Controls and installation

On 2026-10-10, the user confirmed the redesigned UI works in-game: the HUD shows only five pins, and the Pinned entry exposes additional pins. The Lua regression suite passes, and all five Widget Blueprints compile and cook cleanly. Live logs confirm crafting pins and the Pinned view opening without mod errors.

Hover a crafting recipe or building in its menu. Click **Pin this item** in the top-right panel, or press **F8**. Hover it again to unpin. **Clear pins** or **Shift+F8** removes every pin.

This mod requires the [Palworld-compatible UE4SS loader](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld). With Palworld closed, run `./Install.ps1` to install this mod into the local Steam game. The script preserves other mods and backs up this mod's previous installation before replacing it. The distributable ZIP mirrors the game's directory structure; extract its `Pal` folder into the Palworld installation after installing UE4SS.

## Development

Run commands from this mod folder in PowerShell:

```powershell
& ./.venv/Scripts/python.exe tests/run.py
& ./Build.ps1
& ./Install.ps1
```

The test environment uses `requirements-dev.txt` (Lupa); it is not needed by players. `Build.ps1` requires Unreal Engine 5.1.1 and produces `build/PalworldPinItems_P.pak` and the staged `build/package` directory. It explicitly cooks the mod's asset packages without recooking engine content supplied by the game. ZIP creation is opt-in through `./Build.ps1 -CreateZip` and must only be run when the user requests a ZIP.

## Project isolation

Use the shared skills in `../.agents/skills`. Run Graphify from this directory with scan root `.`. `graphify-out/` contains only this mod's graph; never include PMK, UnrealMCP, game files, or other mods. Build output and temporary dependencies are excluded from the graph. Unreal binary `.uasset` files are not parsed by Graphify; the UI's editable layout specification and integration documentation record their relationships.
