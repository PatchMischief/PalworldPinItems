local Recipes = {}

-- Copy reflected row values; Unreal's temporary return structs must not be retained.
function Recipes.from_row(kind, id, row, name)
    if not id or id == "" or id == "None" then return nil end
    local materials, counts = {}, {}
    for index = 1, 5 do
        local material = row["Material" .. index .. "_Id"]
        local count = tonumber(row["Material" .. index .. "_Count"]) or 0
        if material and material ~= "None" and material ~= "" and count > 0 then
            if not counts[material] then materials[#materials + 1] = material end
            counts[material] = (counts[material] or 0) + count
        end
    end
    local product = kind == "craft" and row.Product_Id or row.MapObjectId
    if #materials == 0 and (not product or product == "None" or product == "") then return nil end
    local ingredients = {}
    for _, material in ipairs(materials) do
        ingredients[#ingredients + 1] = {id = material, count = counts[material]}
    end
    return {key = kind .. ":" .. id, id = id, kind = kind,
        name = name or id, icon_id = kind == "craft" and (row.Product_Id or id) or id,
        output = math.max(1, tonumber(row.Product_Count) or 1),
        materials = ingredients}
end

function Recipes.new_tracker()
    return {pins = {}}
end

function Recipes.is_pinned(tracker, recipe)
    if not recipe then return false end
    for _, pin in ipairs(tracker.pins) do
        if pin.key == recipe.key then return true end
    end
    return false
end

function Recipes.toggle(tracker, recipe)
    if not recipe then return false end
    for index, pin in ipairs(tracker.pins) do
        if pin.key == recipe.key then table.remove(tracker.pins, index); return false end
    end
    -- Store a detached snapshot, never a live tooltip/recipe UObject.
    local pin = {key = recipe.key, name = recipe.name, kind = recipe.kind, icon_id = recipe.icon_id, icon_path = recipe.icon_path,
        output = recipe.output, materials = {}}
    for _, material in ipairs(recipe.materials) do
        pin.materials[#pin.materials + 1] = {id = material.id, count = material.count}
    end
    tracker.pins[#tracker.pins + 1] = pin
    return true
end

function Recipes.display(tracker, page, item_name, owned_count)
    local pages = math.max(1, math.ceil(#tracker.pins / 5))
    page = math.max(1, math.min(page, pages))
    local cards = {}
    for index = (page - 1) * 5 + 1, math.min(page * 5, #tracker.pins) do
        local pin = tracker.pins[index]
        local card = {title = pin.name .. (pin.output > 1 and (" x" .. pin.output) or ""),
            kind = pin.kind, icon_id = pin.icon_id, icon_path = pin.icon_path, materials = {}}
        for _, material in ipairs(pin.materials) do
            local owned = owned_count and owned_count(material.id)
            card.materials[#card.materials + 1] = {id = material.id,
                text = item_name(material.id) .. ": " .. (owned or "?") .. "/" .. material.count,
                complete = owned ~= nil and owned >= material.count}
        end
        cards[#cards + 1] = card
    end
    return cards, page, pages
end

return Recipes
