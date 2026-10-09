-- A boundary test: a recipe survives tooltip destruction and real button actions reach the tracker.
package.path = "Scripts/?.lua;" .. package.path
local hooks, binds, tick = {}, {}, nil
local unsafe_name_calls = 0
local function object(fields)
    fields = fields or {}
    function fields:IsValid() return true end
    return fields
end
local function field()
    return object({text = "", visibility = 0, SetText = function(self, text) self.text = text:ToString() end,
        SetVisibility = function(self, value) self.visibility = value end})
end
function FName(value) return object({ToString = function() return value end}) end
function FText(value) return object({text = value, ToString = function(self) return self.text end}) end
local ui = object({RootCanvas = field(), Panel = object({IsHovered = function() return false end}), HoverName = field(),
    PinButton = field(), PinLabel = field(), PinnedText = field(), ClearButton = field(),
    SetVisibility = function(self, value) self.visibility = value end,
    AddToViewport = function() end, RemoveFromParent = function(self) self.removed = true end})
local tooltip = object({CachedDisplayInfo = {RecipeID = FName("Arrow")}, IsVisible = function() return true end})
local hud = object({HoverWidget = tooltip, IsAnyOverlayUIActive = function() return true end,
    GetFullName = function() return "BP_PalHUD_InGame_C" end})
local owned = {Wood = 20, Stone = 0}
local inventory = object({CountItemNum = function(_, id) return owned[id:ToString()] or 0 end})
local state = object({GetInventoryData = function() return inventory end})
local pc = object({GetHUD = function() return hud end, GetAddress = function() return 1 end,
    GetPalPlayerState = function() return state end})
local access = object({BP_FindRow = function(_, id, result)
    assert(type(result) == "table", "UE4SS out parameters require a Lua table")
    result.bResult = id:ToString() == "Arrow"
    if not result.bResult then return {Product_Id = FName("None")} end
    return {Product_Id = FName("Arrow"), Product_Count = 3, Material1_Id = FName("Wood"), Material1_Count = 2}
end})
local objects = {
    ["/Script/Pal.Default__PalUtility"] = object({GetItemIDManager = function()
        return object({GetStaticItemData = function(_, id)
            return {IsValid = function() return id:ToString() ~= "None" and id:ToString() ~= "WoodenFoundation" end}
        end})
    end}),
    ["/Script/Engine.Default__KismetSystemLibrary"] = object({MakeSoftClassPath = function(_, path) return path end,
        Conv_SoftClassPathToSoftClassRef = function(_, path) return path end,
        LoadClassAsset_Blocking = function(_, path)
            assert(path == "/Game/Mods/PalworldPinItems/WBP_PinItems.WBP_PinItems_C")
            return object()
        end}),
    ["/Script/Pal.Default__PalMasterDataTablesUtility"] = object({GetItemRecipeDataTableAccess = function() return access end}),
    ["/Script/Pal.Default__PalUIUtility"] = object({GetItemName = function(_, _, id, output)
        assert(type(output) == "table", "UE4SS FText out parameters require a Lua table")
        if id:ToString() == "None" or id:ToString() == "WoodenFoundation" then
            unsafe_name_calls = unsafe_name_calls + 1
            error("Invalid item ID produces a null native FText")
        end
        output.outName = FText(id:ToString())
    end}),
    ["/Script/UMG.Default__WidgetBlueprintLibrary"] = object({Create = function() return ui end})
}
function StaticFindObject(path) return objects[path] or {IsValid = function() return false end} end
local instances = {}
function FindAllOf(class) return instances[class] or {} end
function RegisterHook(path, callback) hooks[path] = callback; return 1, 2 end
function RegisterKeyBind(key, modifiers, callback) binds[#binds + 1] = callback or modifiers end
function LoopAsync(_, callback) tick = callback end
function ExecuteInGameThread(callback) callback() end
Key, ModifierKey = {F8 = 119}, {SHIFT = 16}
package.preload.UEHelpers = function() return {GetPlayerController = function() return pc end} end
dofile("Scripts/main.lua")
tick()
assert(ui.PinButton.visibility == 0 and ui.HoverName.text == "Arrow")
-- A reflected hover value can be a struct, not a UObject; use the typed tooltip fallback.
hud.HoverWidget = {}
instances.WBP_InventoryEquipment_ItemInfo_C = {tooltip}
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
assert(ui.PinnedText.text:find("Arrow x3\n  Wood: 2/20", 1, true))
hud.HoverWidget = nil
tick()
assert(ui.PinButton.visibility == 1 and ui.visibility == 4)
assert(ui.PinnedText.text:find("Wood: 2", 1, true), "Closing the menu lost the pinned recipe")
owned.Wood = 9
tick()
assert(ui.PinnedText.text:find("Wood: 2/9", 1, true), "Inventory changes must update retained pins")
hooks[class .. ":ClearPins"]()
assert(ui.PinnedText.text == "" and ui.visibility == 1)
hud.HoverWidget = tooltip
tooltip.CachedDisplayInfo.RecipeRequiredItemsOverrideMap = {ForEach = function(_, callback)
    callback({get = function() return FName("Wood") end}, {get = function() return 7 end})
end}
tick()
hooks[class .. ":PinHovered"]()
assert(ui.PinnedText.text:find("Wood: 7", 1, true), "Tooltip cost overrides were ignored")
hud.HoverWidget = nil
instances.WBP_IngameMenu_Construction_Icon_C = {object({IsVisible = function() return true end,
    IsHovered = function() return false end, WBP_PalInvisibleButton = object({IsHovered = function() return true end}), MyBuildObjectData = {
        MapObjectId = FName("WoodenFoundation"), BlueprintItemID = FName("FoundationBlueprint"),
        Material1_Id = FName("Wood"), Material1_Count = 2, Material4_Id = FName("Stone"), Material4_Count = 1}})}
-- A stale crafting tooltip must not take priority over the hovered build icon.
hud.HoverWidget = tooltip
tick()
hooks[class .. ":PinHovered"]()
assert(ui.PinnedText.text:find("FoundationBlueprint\n  Wood: 2/9\n  Stone: 1/0", 1, true), "Build hover costs were not pinned")
instances.WBP_IngameMenu_Construction_Icon_C[1].MyBuildObjectData.BlueprintItemID = FName("None")
hooks[class .. ":ClearPins"]()
tick()
hooks[class .. ":PinHovered"]()
assert(ui.PinnedText.text:find("WoodenFoundation\n  Wood: 2/9", 1, true), "Buildings without a blueprint item need a safe ID label")
assert(unsafe_name_calls == 0, "A building ID reached the item-name crash path")
hud.GetFullName = function() return "BP_PalHUD_Title_C" end
tick()
assert(ui.visibility == 1, "The tracker must be hidden outside gameplay")
print("Runtime boundary test passed: crafting/building hover, button, retained/overridden costs, clear, title-screen hiding.")
