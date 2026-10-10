local UEHelpers = require("UEHelpers")
local Recipes = require("recipes")
local UI = require("ui")
local Inventory = require("inventory")
local Storage = require("storage")
local tracker = Recipes.new_tracker()
local inventory_cache = Inventory.new()
Inventory.subscribe(inventory_cache)
local storage_cache = Storage.new()
Storage.subscribe(storage_cache)
local rendered = {}
local widget, owner, hovered
local cards, menu_view
local hooks_ready = false
local menu_hooks_ready = false
local labels = {}
local last_error
local asset = "/Game/Mods/PalworldPinItems/WBP_PinItems.WBP_PinItems_C"
local tooltip_class = "WBP_InventoryEquipment_ItemInfo_C"
local build_class = "WBP_IngameMenu_Construction_Icon_C"
local ui_instances = {[build_class] = {}, [tooltip_class] = {}, WBP_MainMenu_C = {}}
local seeded = false
local gameplay = StaticFindObject("/Script/Engine.Default__GameplayStatics")

local function valid(object)
    local kind = type(object)
    return (kind == "userdata" or kind == "table") and type(object.IsValid) == "function" and object:IsValid()
end

local function remember_widget(object)
    local list = ui_instances[object:GetClass():GetFName():ToString()]
    if not list or object:GetFName():ToString():match("^Default__") then return end
    for _, existing in ipairs(list) do
        if valid(existing) and existing:GetAddress() == object:GetAddress() then return end
    end
    list[#list + 1] = object
end

NotifyOnNewObject("/Script/UMG.UserWidget", remember_widget)

local function widgets(class)
    local list = ui_instances[class]
    for index = #list, 1, -1 do
        if not valid(list[index]) then table.remove(list, index) end
    end
    return list
end

local function get(object, property)
    local ok, value = pcall(function() return object[property] end)
    return ok and value or nil
end

local function name(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    local ok, text = pcall(function() return value:ToString() end)
    return ok and text or nil
end

local function item_name(id)
    if not id or id == "" or id == "None" then return id end
    if labels[id] then return labels[id] end
    local pal = StaticFindObject("/Script/Pal.Default__PalUtility")
    local manager = pal:GetItemIDManager(owner)
    -- Unknown IDs leave GetItemName's FText null; UE4SS ToString aborts natively.
    if not valid(manager) or not valid(manager:GetStaticItemData(FName(id))) then return id end
    local utility = StaticFindObject("/Script/Pal.Default__PalUIUtility")
    local result = {}
    local ok = pcall(function() utility:GetItemName(owner, FName(id), result) end)
    local text = ok and name(result.outName) or nil
    labels[id] = text and text ~= "" and text or id
    return labels[id]
end

local function snapshot(kind, id, row, label)
    local copied = {Product_Count = get(row, "Product_Count"),
        Product_Id = name(get(row, "Product_Id")), MapObjectId = name(get(row, "MapObjectId"))}
    for index = 1, (kind == "build" and 4 or 5) do
        copied["Material" .. index .. "_Id"] = name(get(row, "Material" .. index .. "_Id"))
        copied["Material" .. index .. "_Count"] = get(row, "Material" .. index .. "_Count")
    end
    return Recipes.from_row(kind, id, copied, label)
end

local function craft_recipe(id)
    if not id or id == "None" then return nil end
    local utility = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
    local access = utility:GetItemRecipeDataTableAccess(owner)
    if not valid(access) then return nil end
    local result = {}
    local row = access:BP_FindRow(FName(id), result)
    if not result.bResult then return nil end
    local product = name(get(row, "Product_Id"))
    return snapshot("craft", id, row, item_name(product or id))
end

local function build_recipe(id, row)
    if not id or id == "None" then return nil end
    if not row then
        local utility = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
        local access = utility:GetBuildObjectDataTableAccess(owner)
        if not valid(access) then return nil end
        local result = {}
        row = access:BP_FindRow(FName(id), result)
        if not result.bResult then return nil end
    end
    local label = name(get(row, "BlueprintItemID"))
    if not label or label == "" or label == "None" then label = id end
    return snapshot("build", id, row, item_name(label or id))
end

local function with_override(recipe, info)
    local map = get(info, "RecipeRequiredItemsOverrideMap")
    if recipe and map then
        local materials = {}
        map:ForEach(function(key, value)
            local id, count = name(key:get()), tonumber(value:get())
            if id and id ~= "None" and count and count > 0 then
                materials[#materials + 1] = {id = id, count = count}
            end
        end)
        if #materials > 0 then recipe.materials = materials end
    end
    return recipe
end

local function current_recipe()
    local hud = owner:GetHUD()
    if not hud:IsAnyOverlayUIActive() then return nil end
    -- The build menu stores soft references; read the hovered icon's actual recipe row.
    if hud:IsAnyOverlayUIActive() then
        for _, icon in ipairs(widgets(build_class)) do
            local button = get(icon, "WBP_PalInvisibleButton")
            if valid(icon) and icon:IsVisible() and (icon:IsHovered() or (valid(button) and button:IsHovered())) then
                local row = get(icon, "MyBuildObjectData")
                if row then
                    local recipe = build_recipe(name(get(row, "MapObjectId")), row)
                    local brush = get(get(icon, "Image_Icon"), "Brush")
                    local texture = get(brush, "ResourceObject")
                    if recipe and valid(texture) then recipe.icon_path = texture:GetFullName():match("^[^ ]+ (.+)$") end
                    return recipe
                end
            end
        end
    end
    local tooltip = get(hud, "HoverWidget")
    if not valid(tooltip) or not get(tooltip, "CachedDisplayInfo") then
        tooltip = nil
        for _, candidate in ipairs(widgets(tooltip_class)) do
            if valid(candidate) and candidate:IsVisible() then tooltip = candidate; break end
        end
    end
    if valid(tooltip) and tooltip:IsVisible() and hud:IsAnyOverlayUIActive() then
        local info = get(tooltip, "CachedDisplayInfo")
        if info then
            local recipe = craft_recipe(name(get(info, "RecipeID")))
            if recipe then return with_override(recipe, info) end
            local item_info = get(info, "ItemInfo")
            local item_id = item_info and get(item_info, "ItemId")
            local static_id = item_id and name(get(item_id, "StaticId"))
            recipe = craft_recipe(static_id)
            if recipe then return with_override(recipe, info) end
            if static_id and static_id ~= "None" then
                local utility = StaticFindObject("/Script/Pal.Default__PalMapObjectUtility")
                local id = name(utility:ConvertBlueprintItemIdToBuildObjectId(owner, FName(static_id)))
                return with_override(build_recipe(id), info)
            end
        end
        return nil
    end
    return nil
end

local function refresh()
    local has_pins = #tracker.pins > 0
    local state = owner:GetPalPlayerState()
    local inventory = valid(state) and state:GetInventoryData() or nil
    Inventory.bind(inventory_cache, inventory, os.clock(), has_pins)
    Storage.bind(storage_cache, owner, os.clock(), has_pins)
    local version = tracker.version .. ":" .. inventory_cache.version .. ":" .. storage_cache.version
    local function owned_count(id)
        local owned = Inventory.count(inventory_cache, id)
        return owned and (owned + Storage.count(storage_cache, id)) or nil
    end
    local hover_key = hovered and hovered.key or ""
    if rendered.version ~= version or rendered.hover ~= hover_key then
        UI.visibility(widget, (hovered or has_pins) and 4 or 1) -- SelfHitTestInvisible / Collapsed.
        UI.text(widget.HoverName, hovered and hovered.name or storage_cache.label)
        UI.visibility(widget.HoverName, (hovered or has_pins) and 0 or 1)
        UI.visibility(widget.PinButton, hovered and 0 or 1)
        UI.text(widget.PinLabel, Recipes.is_pinned(tracker, hovered) and "Unpin this item  [F8]" or "Pin this item  [F8]")
        local models = Recipes.display(tracker, 1, item_name, owned_count)
        UI.draw(cards, models, owner)
        UI.text(widget.Heading, "Pinned items" .. (#tracker.pins > 5 and ("  (5/" .. #tracker.pins .. "; see Pinned tab)") or ""))
        UI.visibility(widget.ClearButton, has_pins and 0 or 1)
        rendered.version, rendered.hover = version, hover_key
    end
    UI.update_menu(menu_view, tracker, item_name, owned_count,
        widgets("WBP_MainMenu_C"), version, storage_cache.label)
    if not menu_hooks_ready then
        local native = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/WBP_MainMenu.WBP_MainMenu_C:SelectByMainMenuType"
        if valid(StaticFindObject(native)) then
            RegisterHook(native, function() if menu_view then menu_view.open = false end end)
            menu_hooks_ready = true
        end
    end
end

local function pin()
    if not valid(widget) or not hovered then return end
    local pinned = Recipes.toggle(tracker, hovered)
    print("[PalworldPinItems] " .. (pinned and "Pinned " or "Unpinned ") .. hovered.key)
    refresh()
end

local function clear()
    Recipes.clear(tracker)
    if valid(widget) then refresh() end
end

local function ensure_widget(controller)
    if valid(widget) and valid(owner) and owner:GetAddress() == controller:GetAddress() then return true end
    if valid(widget) then widget:RemoveFromParent() end
    if menu_view and valid(menu_view.widget) then menu_view.widget:RemoveFromParent() end
    if menu_view and valid(menu_view.tab) then menu_view.tab:RemoveFromParent() end
    owner = controller
    rendered = {}
    local class = StaticFindObject(asset)
    if not valid(class) then
        -- Mod paks are mounted without adding their assets to the game's registry.
        local system = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local path = system:MakeSoftClassPath(asset)
        class = system:LoadClassAsset_Blocking(system:Conv_SoftClassPathToSoftClassRef(path))
    end
    if not valid(class) then error("UI asset missing; install PalworldPinItems_P.pak") end
    if not hooks_ready then
        RegisterHook(asset .. ":PinHovered", function() pin() end)
        RegisterHook(asset .. ":ClearPins", function() clear() end)
        UI.class("WBP_PinTab")
        UI.class("WBP_PinPage")
        local page_asset = "/Game/Mods/PalworldPinItems/WBP_PinPage.WBP_PinPage_C:"
        RegisterHook("/Game/Mods/PalworldPinItems/WBP_PinTab.WBP_PinTab_C:OpenPinned", function()
            menu_view.open = not menu_view.open
            print("[PalworldPinItems] Pinned view " .. (menu_view.open and "opened" or "closed"))
            refresh()
        end)
        RegisterHook(page_asset .. "PreviousPage", function() menu_view.page = math.max(1, menu_view.page - 1); refresh() end)
        RegisterHook(page_asset .. "NextPage", function() menu_view.page = menu_view.page + 1; refresh() end)
        RegisterHook(page_asset .. "ClosePinned", function() menu_view.open = false; refresh() end)
        hooks_ready = true
    end
    local library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    widget = library:Create(controller, class, controller)
    if not valid(widget) then error("Could not create pin UI") end
    UI.visibility(widget.RootCanvas, 4)
    UI.visibility(widget, 1)
    widget:AddToViewport(100)
    cards = UI.cards(widget.PinnedList, controller)
    menu_view = UI.menu(controller)
    print("[PalworldPinItems] UI ready")
    return true
end

local function update()
    local viewport = UEHelpers.GetGameViewportClient()
    local controller = valid(viewport) and gameplay:GetPlayerController(viewport, 0) or nil
    if not valid(controller) then
        Storage.bind(storage_cache, nil, os.clock(), false)
        if valid(widget) then widget:RemoveFromParent() end
        if menu_view and valid(menu_view.widget) then menu_view.widget:RemoveFromParent() end
        if menu_view and valid(menu_view.tab) then menu_view.tab:RemoveFromParent() end
        widget, owner, hovered = nil, nil, nil
        cards, menu_view = nil, nil
        rendered = {}
        return
    end
    if not seeded then
        -- One bootstrap scan per class also supports loading the mod after UI already exists.
        for class in pairs(ui_instances) do
            for _, object in ipairs(FindAllOf(class) or {}) do remember_widget(object) end
        end
        seeded = true
    end
    -- Load and validate the collapsed widget before entering a save.
    ensure_widget(controller)
    if not valid(controller:GetHUD()) then
        Storage.bind(storage_cache, nil, os.clock(), false)
        UI.visibility(widget, 1); UI.visibility(menu_view.widget, 1); menu_view.open = false
        hovered = nil; rendered = {}; return
    end
    -- Only show on the local in-game HUD; no visible UI on the title screen.
    local hud_name = controller:GetHUD():GetFullName()
    if not hud_name:find("PalHUD_InGame", 1, true) and not hud_name:find("PalHUDInGame", 1, true) then
        Storage.bind(storage_cache, nil, os.clock(), false)
        UI.visibility(widget, 1)
        UI.visibility(menu_view.widget, 1)
        menu_view.open = false
        hovered = nil
        rendered = {}
        return
    end
    if not widget.Panel:IsHovered() then
        local next_recipe = current_recipe()
        if next_recipe and (not hovered or hovered.key ~= next_recipe.key) then
            print("[PalworldPinItems] Hover " .. next_recipe.key)
        end
        hovered = next_recipe
    end
    refresh()
end

RegisterKeyBind(Key.F8, function() ExecuteInGameThread(pin) end)
RegisterKeyBind(Key.F8, {ModifierKey.SHIFT}, function() ExecuteInGameThread(clear) end)
local update_pending = false
LoopAsync(150, function()
    if update_pending then return end
    update_pending = true
    ExecuteInGameThread(function()
        local ok, message = xpcall(update, debug.traceback)
        update_pending = false
        if not ok and message ~= last_error then
            print("[PalworldPinItems] " .. tostring(message))
            last_error = message
        elseif ok then last_error = nil end
    end)
end)
print("[PalworldPinItems] Loaded; hover a craft/build recipe and use Pin this item or F8.")
