-- A boundary test: a recipe survives tooltip destruction and real button actions reach the tracker.
package.path = "Scripts/?.lua;" .. package.path
local hooks, binds, tick = {}, {}, nil
local unsafe_name_calls = 0
local scans, ui_writes = 0, 0
local count_reads = 0
local test_time = 0
local viewport_height, prepasses = 2160, 0
os.clock = function() return test_time end
local object_address = 1000
local function object(fields)
    fields = fields or {}
    object_address = object_address + 1
    local address = object_address
    fields.GetAddress = fields.GetAddress or function() return address end
    function fields:IsValid() return true end
    return fields
end
local function field()
    return object({text = "", visibility = 0, SetText = function(self, text) ui_writes = ui_writes + 1; self.text = text:ToString() end,
        SetIsEnabled = function(self, value) ui_writes = ui_writes + 1; self.enabled = value end,
        SetBrushFromTexture = function(self, texture) self.texture = texture end,
        SetBrushFromSoftTexture = function(self, texture) self.texture = texture end,
        SetVisibility = function(self, value) ui_writes = ui_writes + 1; self.visibility = value end})
end
local function panel()
    return object({children = {}, AddChildToVerticalBox = function(self, child) self.children[#self.children + 1] = child end,
        AddChildToHorizontalBox = function(self, child) self.children[#self.children + 1] = child end})
end
local function widget(fields)
    fields = object(fields)
    fields.SetVisibility = function(self, value) ui_writes = ui_writes + 1; self.visibility = value end
    fields.AddToViewport = function() end
    fields.RemoveFromParent = function(self) self.removed = true end
    return fields
end
function FName(value) return object({ToString = function() return value end}) end
function FText(value) return object({text = value, ToString = function(self) return self.text end}) end
local ui = widget({RootCanvas = field(), Panel = object({IsHovered = function() return false end}), HoverName = field(),
    PinButton = field(), PinLabel = field(), PinnedList = panel(), Heading = field(), ClearButton = field()})
ui.ForceLayoutPrepass = function() prepasses = prepasses + 1 end
ui.Panel.GetDesiredSize = function()
    local height = 70
    for _, card in ipairs(ui.PinnedList.children) do
        if card.visibility ~= 1 then
            height = height + 24
            for _, row in ipairs(card.Materials.children) do if row.visibility ~= 1 then height = height + 20 end end
        end
    end
    return {Y = height}
end
local page_view
local function pinned_text()
    local lines = {}
    for _, card in ipairs(ui.PinnedList.children) do
        if card.visibility ~= 1 then
            lines[#lines + 1] = card.ItemName.text
            for _, row in ipairs(card.Materials.children) do
                if row.visibility ~= 1 then lines[#lines + 1] = "  " .. row.MaterialName.text end
            end
        end
    end
    return table.concat(lines, "\n")
end
local tooltip = object({CachedDisplayInfo = {RecipeID = FName("Arrow")}, IsVisible = function() return true end})
local hud = object({HoverWidget = tooltip, IsAnyOverlayUIActive = function() return true end,
    GetFullName = function() return "BP_PalHUD_InGame_C" end})
local owned = {Wood = 20, Stone = 0}
local inventory = object({CountItemNum = function(_, id) count_reads = count_reads + 1; return owned[id:ToString()] or 0 end})
inventory.InventoryMultiHelper = object()
local state = object({GetInventoryData = function() return inventory end})
local pc = object({GetHUD = function() return hud end, GetAddress = function() return 1 end,
    GetPalPlayerState = function() return state end, HasAuthority = function() return true end})
local active_base, storage_reads = nil, 0
local base_wood = 7
local function base_id(value) return {A = value, B = 0, C = 0, D = 0} end
local base_a = object({GetId = function() return base_id(1) end, GetBaseCampName = function() return "Forest" end})
local base_b = object({GetId = function() return base_id(2) end, GetBaseCampName = function() return "Desert" end})
local player = object({InsideBaseCampCheckComponent = object({IsInsideBaseCamp = function() return active_base ~= nil end,
    GetInsideBaseCampModel = function() return active_base end})})
pc.Transmitter = object({GetBaseCamp = function() error("Standalone player must not enter metadata RPC path") end})
local viewport = object()
local access = object({BP_FindRow = function(_, id, result)
    assert(type(result) == "table", "UE4SS out parameters require a Lua table")
    result.bResult = id:ToString() == "Arrow"
    if not result.bResult then return {Product_Id = FName("None")} end
    return {Product_Id = FName("Arrow"), Product_Count = 3, Material1_Id = FName("Wood"), Material1_Count = 2}
end})
local objects = {
    ["/Script/UMG.Default__WidgetLayoutLibrary"] = object({GetViewportSize = function() return {Y = viewport_height} end,
        GetViewportScale = function() return 1 end}),
    ["/Script/Engine.Default__GameplayStatics"] = object({GetPlayerController = function(_, context, index)
        assert(context == viewport and index == 0, "Controller lookup must use the local viewport")
        return pc
    end}),
    ["/Script/Pal.Default__PalUtility"] = object({GetItemIDManager = function()
        return object({GetStaticItemData = function(_, id)
            return {IconTexture = "icon:" .. id:ToString(), IsValid = function() return id:ToString() ~= "None" and id:ToString() ~= "WoodenFoundation" end}
        end})
    end, GetPlayerCharacter = function() return player end}),
    ["/Script/Pal.Default__PalItemUtility"] = object({CollectLocalPlayerControllableAllItemInfos = function(_, context, output, collect_type)
        assert(context == pc and collect_type == 1)
        storage_reads = storage_reads + 1
        output[1] = {StaticItemId = FName("Wood"), Num = active_base == base_a and base_wood or 50}
    end}),
    ["/Script/Engine.Default__KismetSystemLibrary"] = object({MakeSoftClassPath = function(_, path) return path end,
        Conv_SoftClassPathToSoftClassRef = function(_, path) return path end,
        LoadClassAsset_Blocking = function(_, path)
            return object({path = path})
        end, MakeSoftObjectPath = function(_, path) return path end, Conv_SoftObjPathToSoftObjRef = function(_, path) return path end,
        LoadAsset_Blocking = function(_, path) return object({path = path}) end,
        IsValidSoftObjectReference = function(_, path) return path ~= nil end}),
    ["/Script/Pal.Default__PalMasterDataTablesUtility"] = object({GetItemRecipeDataTableAccess = function() return access end,
        GetBuildObjectIconDataTableAccess = function() return object({BP_FindRow = function(_, id, result)
            result.bResult = true; return {SoftIcon = "build:" .. id:ToString()} end}) end}),
    ["/Script/Pal.Default__PalUIUtility"] = object({GetItemName = function(_, _, id, output)
        assert(type(output) == "table", "UE4SS FText out parameters require a Lua table")
        if id:ToString() == "None" or id:ToString() == "WoodenFoundation" then
            unsafe_name_calls = unsafe_name_calls + 1
            error("Invalid item ID produces a null native FText")
        end
        output.outName = FText(id:ToString())
    end}),
    ["/Script/UMG.Default__WidgetBlueprintLibrary"] = object({Create = function(_, _, class)
        if class.path:find("WBP_PinItems.", 1, true) then return ui end
        if class.path:find("WBP_PinCard.", 1, true) then return widget({ItemName = field(), ItemIcon = field(), Materials = panel()}) end
        if class.path:find("WBP_PinMaterial.", 1, true) then return widget({MaterialName = field(), MaterialIcon = field(), Complete = field()}) end
        if class.path:find("WBP_PinPage.", 1, true) then
            page_view = widget({PinnedList = panel(), PageHeading = field(), PageLabel = field(), PreviousButton = field(), NextButton = field()}); return page_view
        end
        if class.path:find("WBP_PinTab.", 1, true) then return widget({OpenButton = field()}) end
        error("Unknown class: " .. class.path)
    end})
}
for _, method in ipairs({"OnUpdateInventoryContainer", "OnUpdateEssentialContainer", "OnUpdateLoadoutSlot",
    "OnUpdateEquipmentSlot", "OnRep_InventoryInfo"}) do
    objects["/Script/Pal.PalPlayerInventoryData:" .. method] = object()
end
for _, method in ipairs({"OnUpdateContainerContent", "OnRep_Containers"}) do
    objects["/Script/Pal.PalItemContainerMultiHelper:" .. method] = object()
end
for _, method in ipairs({"OnUpdateItemContainer", "OnRep_ItemStackRepInfoArray", "OnAvailableConcreteModel",
    "OnNotAvailableConcreteModel", "OnUpdatePrivateLockPlayerUId_ServerInternal", "OnUpdatePasswordLock_ServerInternal",
    "OnUpdateGuildSecurity_ServerInternal"}) do
    objects["/Script/Pal.PalBaseCampModuleItemStackInfo:" .. method] = object()
end
function StaticFindObject(path) return objects[path] or {IsValid = function() return false end} end
local instances = {}
local new_widget
function NotifyOnNewObject(class, callback)
    assert(class == "/Script/UMG.UserWidget" and not new_widget, "Register one widget construction listener")
    new_widget = callback
end
local function created(class, instance)
    local address = instance:GetAddress()
    instance.GetClass = function() return object({GetFName = function() return FName(class) end}) end
    instance.GetFName = function() return FName(class .. "_" .. address) end
    instances[class] = instances[class] or {}
    table.insert(instances[class], instance)
    if new_widget then new_widget(instance) end
    return instance
end
function FindAllOf(class) scans = scans + 1; return instances[class] or {} end
function RegisterHook(path, callback, post) hooks[path] = post or callback; return 1, 2 end
local function inventory_event(target, method, helper)
    hooks["/Script/Pal." .. (helper and "PalItemContainerMultiHelper" or "PalPlayerInventoryData") .. ":" .. method]({get = function() return target end})
end
function RegisterKeyBind(key, modifiers, callback) binds[#binds + 1] = callback or modifiers end
function LoopAsync() error("Periodic refresh must not run on UE4SS's shared async Lua state") end
local loop_registrations = 0
function LoopInGameThreadWithDelay(delay, callback)
    assert(delay == 150)
    loop_registrations = loop_registrations + 1
    tick = callback
end
function ExecuteInGameThread(callback) callback() end
Key, ModifierKey = {F8 = 119}, {SHIFT = 16}
package.preload.UEHelpers = function() return {GetPlayerController = function() FindAllOf("PlayerController"); return pc end,
    GetGameViewportClient = function() return viewport end} end
created("WBP_InventoryEquipment_ItemInfo_C", tooltip) -- Existing UI must be found by the one-time bootstrap.
dofile("Scripts/main.lua")
tick()
assert(ui.PinButton.visibility == 0 and ui.HoverName.text == "Arrow")
-- A reflected hover value can be a struct, not a UObject; use the typed tooltip fallback.
hud.HoverWidget = {}
created("WBP_InventoryEquipment_ItemInfo_C", tooltip)
tick()
assert(ui.PinButton.visibility == 0 and ui.HoverName.text == "Arrow")
hud.HoverWidget = tooltip
instances.WBP_InventoryEquipment_ItemInfo_C = nil
tooltip.CachedDisplayInfo.RecipeID = FName("NotCraftable")
tick()
assert(ui.PinButton.visibility == 1, "A failed recipe lookup must not read its default row or item name")
assert(unsafe_name_calls == 0, "Failed lookups reached the native FText crash path")
tooltip.CachedDisplayInfo.RecipeID = FName("Arrow")
tick()
local class = "/Game/Mods/PalworldPinItems/WBP_PinItems.WBP_PinItems_C"
hooks[class .. ":PinHovered"]()
assert(pinned_text():find("Arrow x3\n  Wood: 20/2", 1, true))
assert(ui.PinnedList.children[1].ItemIcon.texture == "icon:Arrow", "Crafted item icon missing")
assert(ui.PinnedList.children[1].Materials.children[1].MaterialIcon.texture == "icon:Wood", "Material icon missing")
assert(ui.PinnedList.children[1].Materials.children[1].Complete.visibility == 3, "Sufficient ingredients need the game checkmark")
hud.HoverWidget = nil
tooltip.IsVisible = function() return false end
tick()
assert(ui.PinButton.visibility == 1 and ui.visibility == 4)
assert(pinned_text():find("Wood: 20/2", 1, true), "Closing the menu lost the pinned recipe")
owned.Wood = 9
inventory_event(inventory, "OnUpdateInventoryContainer")
tick()
assert(pinned_text():find("Wood: 9/2", 1, true), "Inventory changes must update retained pins")
hooks[class .. ":ClearPins"]()
assert(pinned_text() == "" and ui.visibility == 1)
hud.HoverWidget = tooltip
tooltip.IsVisible = function() return true end
tooltip.CachedDisplayInfo.RecipeRequiredItemsOverrideMap = {ForEach = function(_, callback)
    callback({get = function() return FName("Wood") end}, {get = function() return 7 end})
end}
tick()
hooks[class .. ":PinHovered"]()
assert(pinned_text():find("Wood: 9/7", 1, true), "Tooltip cost overrides were ignored")
hud.HoverWidget = nil
created("WBP_IngameMenu_Construction_Icon_C", object({IsVisible = function() return true end,
    IsHovered = function() return false end, WBP_PalInvisibleButton = object({IsHovered = function() return true end}), MyBuildObjectData = {
        MapObjectId = FName("WoodenFoundation"), BlueprintItemID = FName("FoundationBlueprint"),
        Material1_Id = FName("Wood"), Material1_Count = 2, Material4_Id = FName("Stone"), Material4_Count = 1}}))
-- A stale crafting tooltip must not take priority over the hovered build icon.
hud.HoverWidget = tooltip
tick()
hooks[class .. ":PinHovered"]()
assert(pinned_text():find("FoundationBlueprint\n  Wood: 9/2\n  Stone: 0/1", 1, true), "Build hover costs were not pinned")
instances.WBP_IngameMenu_Construction_Icon_C[1].MyBuildObjectData.BlueprintItemID = FName("None")
hooks[class .. ":ClearPins"]()
tick()
hooks[class .. ":PinHovered"]()
assert(pinned_text():find("WoodenFoundation\n  Wood: 9/2", 1, true), "Buildings without a blueprint item need a safe ID label")
assert(unsafe_name_calls == 0, "A building ID reached the item-name crash path")
local ingredient_rows = ui.PinnedList.children[1].Materials.children
assert(ingredient_rows[1].Complete.visibility == 3 and ingredient_rows[2].Complete.visibility == 2)
owned.Wood = 1
inventory_event(inventory.InventoryMultiHelper, "OnUpdateContainerContent", true)
tick()
assert(ingredient_rows[1].Complete.visibility == 2, "Checkmark must disappear when materials fall below the cost")
for index = 1, 6 do
    instances.WBP_IngameMenu_Construction_Icon_C[1].MyBuildObjectData.MapObjectId = FName("Build" .. index)
    if index == 6 then instances.WBP_IngameMenu_Construction_Icon_C[1].MyBuildObjectData.Material1_Id = FName("Fiber") end
    tick(); hooks[class .. ":PinHovered"]()
end
local function visible_cards(container)
    local count = 0
    for _, card in ipairs(container.children) do if card.visibility ~= 1 then count = count + 1 end end
    return count
end
assert(visible_cards(ui.PinnedList) == 5, "HUD must never display more than five pins")
local menu = object({IsVisible = function() return true end, GetAddress = function() return 2 end, HorizontalBox_Tab = panel()})
created("WBP_MainMenu_C", menu)
tick(); tick()
assert(#menu.HorizontalBox_Tab.children == 1, "Pinned tab must be injected once, not once per refresh")
local page_class = "/Game/Mods/PalworldPinItems/WBP_PinPage.WBP_PinPage_C:"
hooks["/Game/Mods/PalworldPinItems/WBP_PinTab.WBP_PinTab_C:OpenPinned"]()
assert(page_view.visibility == 4 and visible_cards(page_view.PinnedList) == 5)
assert(page_view.PageLabel.text == "1 / 2" and page_view.NextButton.enabled)
count_reads = 0
hooks[page_class .. "NextPage"]()
assert(count_reads == 1, "Paging must query only the newly visible uncached ingredient")
assert(visible_cards(page_view.PinnedList) == 2 and page_view.PageLabel.text == "2 / 2")
assert(not page_view.NextButton.enabled and page_view.PreviousButton.enabled)
hooks[page_class .. "PreviousPage"]()
assert(page_view.PageLabel.text == "1 / 2")
hooks[page_class .. "ClosePinned"]()
assert(page_view.visibility == 1)
scans, ui_writes = 0, 0
count_reads = 0
local UI = require("ui")
local native_draw, draw_calls = UI.draw, 0
UI.draw = function(...) draw_calls = draw_calls + 1; return native_draw(...) end
for _ = 1, 100 do tick() end
print("Seven-pin steady check: " .. count_reads .. " inventory count queries and " .. draw_calls .. " card redraws across 100 updates")
assert(count_reads == 0, "Unchanged inventory must not be recounted every update")
assert(draw_calls == 0, "Unchanged pinned cards must not be rebuilt every update")
assert(scans == 0 and ui_writes == 0, "Steady pinned/menu UI must not scan globally or rewrite unchanged widgets")
UI.draw = native_draw
viewport_height = 1080
tick()
assert(visible_cards(ui.PinnedList) < 5 and visible_cards(ui.PinnedList) > 0, "Small HUD gaps must keep whole cards, with overflow on the Pinned page")
assert(ui.Panel:GetDesiredSize().Y <= UI.hud_height(pc))
local prepass_count = prepasses
for _ = 1, 100 do tick() end
assert(prepasses == prepass_count, "Steady HUD layout must not measure cards repeatedly")
viewport_height = 2160
tick()
assert(visible_cards(ui.PinnedList) == 5, "A larger viewport must restore cards that fit")
count_reads = 0
inventory_event(object(), "OnUpdateInventoryContainer")
tick()
assert(count_reads == 0, "Other players' inventory events must not invalidate local counts")
for _ = 1, 10 do inventory_event(inventory, "OnUpdateInventoryContainer") end
tick()
assert(count_reads == 2, "A burst of local updates must query each visible ingredient just once")
count_reads = 0
test_time = 11
tick()
assert(count_reads == 2, "Slow reconciliation must recover changes if an inventory event is missed")
count_reads = 0
tick()
assert(count_reads == 0, "Reconciliation must not resume per-update polling")
hud.IsAnyOverlayUIActive = function() return false end
active_base = base_a
tick()
assert(pinned_text():find("Wood: 8/2", 1, true) and ui.HoverName.text == "Backpack + Forest")
assert(storage_reads == 1, "Every visible card must share one base snapshot")
for _ = 1, 100 do tick() end
assert(storage_reads == 1, "Pinned recipes must not repeatedly scan base storage")
local function base_event(value)
    hooks["/Script/Pal.PalBaseCampModuleItemStackInfo:OnRep_ItemStackRepInfoArray"]({get = function()
        return object({OwnerBaseCampId = base_id(value)}) end})
end
base_event(2); tick()
assert(storage_reads == 1)
base_wood = 9
base_event(1); tick()
assert(pinned_text():find("Wood: 10/2", 1, true) and storage_reads == 2)
hooks["/Game/Mods/PalworldPinItems/WBP_PinTab.WBP_PinTab_C:OpenPinned"]()
assert(page_view.PageHeading.text == "Pinned items · Backpack + Forest")
active_base = base_b
tick()
assert(pinned_text():find("Wood: 51/2", 1, true) and ui.HoverName.text == "Backpack + Desert")
active_base = nil
tick()
assert(pinned_text():find("Wood: 1/2", 1, true) and ui.HoverName.text == "Backpack")
assert(ui.PinnedList.children[1].Materials.children[1].Complete.visibility == 2, "Leaving a base must remove its completion check")
hooks["/Game/Mods/PalworldPinItems/WBP_PinTab.WBP_PinTab_C:OpenPinned"]()
menu.IsVisible = function() return false end
tick()
assert(page_view.visibility == 1, "Closing the player menu must also close the pinned view")
menu.IsVisible = function() return true end
tick()
local remove_class = "/Game/Mods/PalworldPinItems/WBP_PinCard.WBP_PinCard_C:RemovePin"
local first_card = ui.PinnedList.children[1]
local first_name = first_card.ItemName.text
local writes_before, prepasses_before = ui_writes, prepasses
hooks[remove_class]({get = function() return first_card end})
assert(ui_writes == writes_before and prepasses == prepasses_before, "X must not redraw or prepass its widget inside the click dispatch")
tick()
assert(ui.PinnedList.children[1].ItemName.text ~= first_name, "HUD X must remove its bound pin, independently of hover")
hooks["/Game/Mods/PalworldPinItems/WBP_PinTab.WBP_PinTab_C:OpenPinned"]()
hooks[page_class .. "NextPage"]()
assert(page_view.PageLabel.text == "2 / 2" and visible_cards(page_view.PinnedList) == 1)
hooks[remove_class]({get = function() return page_view.PinnedList.children[1] end})
tick()
assert(page_view.PageLabel.text == "1 / 1" and visible_cards(page_view.PinnedList) == 5, "Removing the final second-page pin must clamp the page and retain the other pins")
hooks[remove_class]({get = function() return object() end})
assert(visible_cards(page_view.PinnedList) == 5, "Unknown widget clicks must leave pins intact")
hooks[class .. ":ClearPins"]()
hud.HoverWidget = nil
hud.IsAnyOverlayUIActive = function() return false end
tick() -- Settle the transition before measuring idle updates.
scans, ui_writes = 0, 0
for _ = 1, 100 do tick() end
print("Idle performance check: " .. scans .. " global scans and " .. ui_writes .. " UI writes across 100 updates")
assert(scans == 0, "Idle updates must not sweep the entire game object array")
assert(ui_writes == 0, "Unchanged hidden UI must not be rewritten every update")
local UI = require("ui")
local wrapper_writes = 0
local function wrapper()
    return object({GetAddress = function() return 777777 end,
        SetText = function() wrapper_writes = wrapper_writes + 1 end})
end
UI.text(wrapper(), "Same native widget")
UI.text(wrapper(), "Same native widget")
assert(wrapper_writes == 1, "Fresh Lua wrappers for one native widget must share the write cache")
assert(loop_registrations == 1, "Register one persistent game-thread timer")
local original_hud = pc.GetHUD
pc.GetHUD = function() error("Injected transient HUD failure") end
tick()
pc.GetHUD = original_hud
tick()
assert(loop_registrations == 1, "An update error must not stall or duplicate the timer")
menu.IsValid = function() return false end
hud.IsAnyOverlayUIActive = function() return true end
local replacement = created("WBP_MainMenu_C", object({IsVisible = function() return true end, HorizontalBox_Tab = panel()}))
tick()
assert(#replacement.HorizontalBox_Tab.children == 1, "A recreated menu must receive its Pinned tab without rescanning")
replacement.IsVisible = function() return false end
instances.WBP_IngameMenu_Construction_Icon_C[1].IsValid = function() return false end
tooltip.IsVisible = function() return false end
hud.HoverWidget = nil
tick()
assert(ui.PinButton.visibility == 1, "Destroyed cached construction widgets must be pruned")
hud.GetFullName = function() return "BP_PalHUD_Title_C" end
tick()
assert(ui.visibility == 1, "The tracker must be hidden outside gameplay")
print("Runtime boundary test passed: crafting/building hover, button, retained/overridden costs, clear, title-screen hiding.")
