local Recipes = require("recipes")
local UI = {}
local folder = "/Game/Mods/PalworldPinItems/"
local check_path = "/Game/Pal/Texture/UI/Main_Menu/T_prt_itemslot_select_check_0.T_prt_itemslot_select_check_0"

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
        image:SetVisibility(valid(texture) and 3 or 2)
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
    image:SetVisibility(available and 3 or 2)
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
            row:SetVisibility(1)
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
        card.widget:SetVisibility(model and 4 or 1)
        if model then
            card.widget.ItemName:SetText(FText(model.title))
            local key = (model.kind or "craft") .. ":" .. (model.icon_path or model.icon_id or "")
            if card.icon_key ~= key then set_icon(card.widget.ItemIcon, model, controller); card.icon_key = key end
            for material, row in ipairs(card.rows) do
                local ingredient = model.materials[material]
                row:SetVisibility((ingredient or (material == 1 and #model.materials == 0)) and 4 or 1)
                if ingredient then
                    row.MaterialName:SetText(FText(ingredient.text))
                    row.Complete:SetVisibility(ingredient.complete and 3 or 2)
                    if row.icon_id ~= ingredient.id then
                        set_icon(row.MaterialIcon, {icon_id = ingredient.id}, controller)
                        row.icon_id = ingredient.id
                    end
                elseif material == 1 and #model.materials == 0 then
                    row.MaterialName:SetText(FText("No materials required"))
                    row.MaterialIcon:SetVisibility(2)
                    row.Complete:SetVisibility(2)
                    row.icon_id = nil
                end
            end
        end
    end
end

function UI.menu(controller)
    local view = {controller = controller, page = 1, open = false}
    view.widget = UI.create(controller, "WBP_PinPage")
    view.widget:SetVisibility(1)
    view.widget:AddToViewport(200)
    view.cards = UI.cards(view.widget.PinnedList, controller)
    return view
end

function UI.update_menu(view, tracker, item_name, owned_count)
    local menu
    for _, candidate in ipairs(FindAllOf("WBP_MainMenu_C") or {}) do
        if valid(candidate) and candidate:IsVisible() then menu = candidate; break end
    end
    if not menu then view.open = false; view.widget:SetVisibility(1); return end
    if not valid(view.tab) or not valid(view.menu) or view.menu:GetAddress() ~= menu:GetAddress() then
        if valid(view.tab) then view.tab:RemoveFromParent() end
        -- shortcut: native tab cycling skips this entry; extend navigation if keyboard/controller access is needed.
        view.tab = UI.create(view.controller, "WBP_PinTab")
        menu.HorizontalBox_Tab:AddChildToHorizontalBox(view.tab)
        view.menu = menu
        print("[PalworldPinItems] Pinned tab added")
    end
    view.widget:SetVisibility(view.open and 4 or 1)
    if view.open then
        local models, page, pages = Recipes.display(tracker, view.page, item_name, owned_count)
        view.page = page
        UI.draw(view.cards, models, view.controller)
        view.widget.PageLabel:SetText(FText(page .. " / " .. pages))
        view.widget.PreviousButton:SetIsEnabled(page > 1)
        view.widget.NextButton:SetIsEnabled(page < pages)
    end
end

return UI
