local Recipes = require("recipes")
local UI = {}
local folder = "/Game/Mods/PalworldPinItems/"
local check_path = "/Game/Pal/Texture/UI/Main_Menu/T_prt_itemslot_select_check_0.T_prt_itemslot_select_check_0"
local text_values, visibility_values, enabled_values = {}, {}, {}

function UI.text(widget, value)
    local address = widget:GetAddress()
    if text_values[address] == value then return end
    widget:SetText(FText(value))
    text_values[address] = value
end

function UI.visibility(widget, value)
    local address = widget:GetAddress()
    if visibility_values[address] == value then return end
    widget:SetVisibility(value)
    visibility_values[address] = value
end

local function enabled(widget, value)
    local address = widget:GetAddress()
    if enabled_values[address] == value then return end
    widget:SetIsEnabled(value)
    enabled_values[address] = value
end

local function valid(object) return object and object:IsValid() end
local function system() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end

function UI.class(name)
    local path = folder .. name .. "." .. name .. "_C"
    local class = StaticFindObject(path)
    if not valid(class) then
        local library = system()
        class = library:LoadClassAsset_Blocking(library:Conv_SoftClassPathToSoftClassRef(library:MakeSoftClassPath(path)))
    end
    assert(valid(class), "Missing UI asset: " .. name)
    return class
end

function UI.create(controller, name)
    -- Property reads can return new Lua wrappers; native addresses identify widgets.
    -- Reset on creation so destroyed widgets' reused addresses cannot suppress initial values.
    text_values, visibility_values, enabled_values = {}, {}, {}
    local library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    return library:Create(controller, UI.class(name), controller)
end

local function load_texture(path)
    local library = system()
    return library:LoadAsset_Blocking(library:Conv_SoftObjPathToSoftObjRef(library:MakeSoftObjectPath(path)))
end

local function set_icon(image, model, controller)
    if model.icon_path then
        local texture = load_texture(model.icon_path)
        UI.visibility(image, valid(texture) and 3 or 2)
        if valid(texture) then image:SetBrushFromTexture(texture, false) end
        return
    end
    local soft
    if model.kind == "build" then
        local utility = StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility")
        local access = utility:GetBuildObjectIconDataTableAccess(controller)
        if valid(access) then
            local result = {}
            local row = access:BP_FindRow(FName(model.icon_id), result)
            if result.bResult then soft = row.SoftIcon end
        end
    else
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local manager = utility:GetItemIDManager(controller)
        local data = valid(manager) and manager:GetStaticItemData(FName(model.icon_id)) or nil
        if valid(data) then soft = data.IconTexture end
    end
    local available = soft and system():IsValidSoftObjectReference(soft)
    UI.visibility(image, available and 3 or 2)
    if available then image:SetBrushFromSoftTexture(soft, false) end
end

function UI.cards(container, controller)
    local cards = {}
    local check = load_texture(check_path)
    for index = 1, 5 do
        local card = UI.create(controller, "WBP_PinCard")
        container:AddChildToVerticalBox(card)
        local rows = {}
        for material = 1, 5 do
            local row = UI.create(controller, "WBP_PinMaterial")
            card.Materials:AddChildToVerticalBox(row)
            if valid(check) then row.Complete:SetBrushFromTexture(check, false) end
            UI.visibility(row, 1)
            rows[material] = row
        end
        card:SetVisibility(1)
        cards[index] = {widget = card, rows = rows}
    end
    return cards
end

function UI.draw(cards, models, controller)
    for index, card in ipairs(cards) do
        local model = models[index]
        card.key = model and model.key or nil
        UI.visibility(card.widget, model and 4 or 1)
        if model then
            UI.text(card.widget.ItemName, model.title)
            local key = (model.kind or "craft") .. ":" .. (model.icon_path or model.icon_id or "")
            if card.icon_key ~= key then set_icon(card.widget.ItemIcon, model, controller); card.icon_key = key end
            for material, row in ipairs(card.rows) do
                local ingredient = model.materials[material]
                UI.visibility(row, (ingredient or (material == 1 and #model.materials == 0)) and 4 or 1)
                if ingredient then
                    UI.text(row.MaterialName, ingredient.text)
                    UI.visibility(row.Complete, ingredient.complete and 3 or 2)
                    if row.icon_id ~= ingredient.id then
                        set_icon(row.MaterialIcon, {icon_id = ingredient.id}, controller)
                        row.icon_id = ingredient.id
                    end
                elseif material == 1 and #model.materials == 0 then
                    UI.text(row.MaterialName, "No materials required")
                    UI.visibility(row.MaterialIcon, 2)
                    UI.visibility(row.Complete, 2)
                    row.icon_id = nil
                end
            end
        end
    end
end

function UI.hud_height(controller)
    local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    return math.max(0, layout:GetViewportSize(controller).Y / layout:GetViewportScale(controller) * 0.73 - 48)
end

function UI.fit_hud(widget, cards, count, height)
    -- Keep whole cards at their normal font size; overflow stays in the Pinned page.
    widget:ForceLayoutPrepass()
    while count > 0 and widget.Panel:GetDesiredSize().Y > height do
        UI.visibility(cards[count].widget, 1)
        cards[count].key = nil
        count = count - 1
        widget:ForceLayoutPrepass()
    end
    return count
end

function UI.menu(controller)
    local view = {controller = controller, page = 1, open = false}
    view.widget = UI.create(controller, "WBP_PinPage")
    UI.visibility(view.widget, 1)
    view.widget:AddToViewport(200)
    view.cards = UI.cards(view.widget.PinnedList, controller)
    return view
end

function UI.update_menu(view, tracker, item_name, owned_count, menus, version, scope)
    local menu
    for _, candidate in ipairs(menus) do
        if valid(candidate) and candidate:IsVisible() then menu = candidate; break end
    end
    if not menu then view.open = false; view.version = nil; UI.visibility(view.widget, 1); return end
    if not valid(view.tab) or not valid(view.menu) or view.menu:GetAddress() ~= menu:GetAddress() then
        if valid(view.tab) then view.tab:RemoveFromParent() end
        -- shortcut: native tab cycling skips this entry; extend navigation if keyboard/controller access is needed.
        view.tab = UI.create(view.controller, "WBP_PinTab")
        menu.HorizontalBox_Tab:AddChildToHorizontalBox(view.tab)
        view.menu = menu
        view.version = nil
        print("[PalworldPinItems] Pinned tab added")
    end
    UI.visibility(view.widget, view.open and 4 or 1)
    if not view.open then view.version = nil end
    if view.open and (view.version ~= version or view.rendered_page ~= view.page) then
        local models, page, pages = Recipes.display(tracker, view.page, item_name, owned_count)
        view.page = page
        UI.draw(view.cards, models, view.controller)
        UI.text(view.widget.PageHeading, "Pinned items · " .. scope)
        UI.text(view.widget.PageLabel, page .. " / " .. pages)
        enabled(view.widget.PreviousButton, page > 1)
        enabled(view.widget.NextButton, page < pages)
        view.version, view.rendered_page = version, page
    end
end

return UI
