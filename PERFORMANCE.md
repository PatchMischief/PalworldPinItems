# Performance investigation — 2026-10-10

The user initially reported fewer than 30 FPS even with no nearby Pals and no pinned recipes, including a new save. After the first patch, they confirmed good performance with no pins but an FPS drop with about seven pins. On 2026-10-10, they confirmed the combined performance patch works well, reported no bugs so far, and authorized committing/pushing it. This is qualitative gameplay confirmation, not a measured FPS benchmark. No ZIP was created.

## Cause found in the mod

The previous 150 ms loop called the installed `UEHelpers.GetPlayerController`, which uses `FindAllOf("PlayerController")` on every invocation. With no recipe tooltip, `current_recipe` also searched for crafting tooltip instances even when no overlay was active. `UI.update_menu` searched for the main menu on every refresh, regardless of whether it was open. That makes three complete global object scans per idle update, approximately twenty scans per second. UI text and visibility were also rewritten repeatedly while the panel was collapsed.

UE4SS's [FindAllOf documentation](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/docs/lua-api/global-functions/findallof.md) identifies an entire pass over the global object array and warns that the function is very slow. The installed helper implementation was inspected directly; the repeated controller scan is not an assumption about an external helper.

## Change

- Get the current local controller through `/Script/Engine.Default__GameplayStatics.GetPlayerController(viewport, 0)`. The viewport comes from the installed helper's cached engine lookup, and the current world determines the controller after map transitions.
- Register one [NotifyOnNewObject](https://docs.ue4ss.com/lua-api/global-functions/notifyonnewobject.html) listener for the already-existing `/Script/UMG.UserWidget` class. Keep only construction icons, recipe tooltips, and main menus; exclude class defaults. Bootstrap existing instances once per class, deduplicate notifications, and prune destroyed cached objects. There is no repeated global widget discovery loop.
- Return from recipe hover detection when no overlay is active. Preserve existing build-menu priority and safe recipe/item-name lookup guards.
- Cache native text, visibility, and enabled values by widget address. A new Lua wrapper for the same native widget shares the cache. Reset caches when creating UI so a reused native address receives its initial values.
- Use one persistent `LoopInGameThreadWithDelay(150, ...)` timer. This supersedes the original one-pending-callback guard: recurring async Lua can race the shared hook state in UE4SS. F8 actions remain independent, and X redraw happens on the next timer update after click dispatch ends. See `UI.md` for the failed live test and patch evidence.

## Evidence

The new failing regression check reproduced **300 global scans and 1,300 native UI writes across 100 idle updates** before the patch. The helper mock deliberately includes the real installed helper's controller scan. After the patch, the same check records **zero scans and zero UI writes** after the initial transition settles.

The suite also checks unchanged pinned/menu UI over 100 updates, initial existing-widget discovery, notifications for newly created widgets, duplicate prevention, destroyed-widget cleanup, recreated main-menu tab injection, fresh wrappers sharing a native address, one persistent game-thread timer, and recovery after a caught update error. Existing crafting/building pins, overrides, inventory count changes, icons, checkmarks, five-card HUD limit, paging, and title-screen hiding still pass.

An unattended native title-screen smoke test registered the UMG notification listener, created the UI, and loaded every button hook without a mod error. Temporary instrumentation compared twenty calls to the old three-search path with twenty viewport-controller lookups in the same process. The old path averaged **30.25 ms per sample** using Lua `os.clock`; the new controller lookup was below that timer's resolution. The subsequent steady-state check recorded **zero global scans**. The local log is `build/diagnostics/native-smoke.log`.

This is a lookup-cost measurement on the title screen, not an in-world FPS benchmark. The test did not enter a save or measure actual gameplay frame times. It establishes substantial avoidable game-thread work, but other contributors to the reported FPS cannot be excluded yet. The temporary profiler was removed after testing; at that stage all three installed Lua modules hash-matched the clean source. The SDK editor was not running during the smoke test. UE4SS loader settings were left unchanged.

## Follow-up: populated pin list

The previous refresh rebuilt visible card models and reset its count cache every 150 ms, approximately 6.7 times per second. It called the game's native `CountItemNum(FName(material_id))` once per distinct material among the five HUD pins and, if open, the current five-item Pinned page. Shared materials were deduplicated within that one refresh; hidden pins were not queried. The Lua mod did not scan inventory slots itself. PMK's `PalPlayerInventoryData.cpp` contains a stub count implementation, so whether the real game's count function scans slots internally is unknown.

The seven-pin regression fixture reproduced **200 native count queries and 100 card redraws across 100 unchanged updates** before this follow-up. The fixture has two distinct HUD materials; real recipes can have more. This demonstrates repeated work, not a measured causal attribution of the user's entire FPS drop.

`Scripts/inventory.lua` now persists counts and FNames by material ID. It subscribes through native UFUNCTION post-hooks, using the third callback argument documented by [UE4SS RegisterHook](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html):

- `PalPlayerInventoryData`: `OnUpdateInventoryContainer`, `OnUpdateEssentialContainer`, `OnUpdateLoadoutSlot`, `OnUpdateEquipmentSlot`, `OnRep_InventoryInfo`.
- `PalItemContainerMultiHelper`: `OnUpdateContainerContent`, `OnRep_Containers`.

This is a publish/subscribe flow using game notifications: local inventory update -> dirty count cache -> next scheduled game-thread refresh -> changed card values. The callback only marks dirty after checking the publisher's native address against the active inventory or its `InventoryMultiHelper`. Other players' inventories and unrelated containers do not invalidate counts. A burst of notifications coalesces into one refresh, querying each visible material once. Changing local inventory owner clears the cache too. A recovery refresh every ten seconds covers missed handlers; if no handlers can be registered, it uses one second. Empty pins cause no periodic recount.

HUD/page versions skip model generation and `UI.draw` when their data is unchanged. Page navigation queries only newly visible uncached materials. Hover controls can change independently; UI property caches still avoid unchanged native writes. Icon bindings remain cached.

Lua's associative [tables have an array part and a hash part](https://www.lua.org/source/5.4/ltable.c.html). Cached counts and pin membership now use string-keyed tables, with average O(1) lookup. The ordered pin array supports direct page indexing, and drawing visits only five recipes per view. Unpinning remains O(P) to find and shift an ordered array entry, where P is the number of pins; that occurs only on a user action, not every refresh. A linked list would not improve the inventory query or redraw cost, and searching one would be O(P), not O(log P).

After this follow-up, the same seven-pin fixture records **zero count queries and zero card redraws across 100 unchanged updates**. A ten-event local inventory burst makes exactly two count queries in the fixture; an unrelated inventory makes zero. Tests also check new-page-only counts, zero-owned count caching, missing-hook fallback, reconciliation after a missed event, new inventory owner, unavailable inventory, pin hash removal/clear, and the existing runtime boundaries.

The unattended native startup check registered all seven inventory hooks successfully and created the collapsed UI without a mod error. The log is `build/diagnostics/inventory-native-smoke.log`. All four installed Lua modules match source; the five unchanged Widget Blueprints cooked with zero errors or warnings. The user subsequently confirmed the version works well in-game with no bugs found so far. Individual native event paths and exact frame times were not separately instrumented in a loaded world.

## Gameplay verification

The requested return check covered populated pins, paging, performance in the same scene, and responsive material counts/checkmarks. The user's response was: "this version of the mod works fine did not find any bugs so far so you can push it github." Their next request is to include chest items per base; personal-inventory-only counting in this verified version is a feature limitation, not a regression.
