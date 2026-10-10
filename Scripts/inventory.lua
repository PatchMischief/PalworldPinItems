local Inventory = {}

local function valid(object) return object and object:IsValid() end

function Inventory.new()
    return {counts = {}, names = {}, dirty = true, version = 0, deadline = 0, interval = 1}
end

function Inventory.bind(cache, inventory, now, has_pins)
    local address = valid(inventory) and inventory:GetAddress() or nil
    if cache.address ~= address then
        cache.inventory, cache.address, cache.dirty = inventory, address, true
    end
    if cache.dirty or (has_pins and now >= cache.deadline) then
        cache.counts, cache.dirty = {}, false
        cache.version = cache.version + 1
        cache.deadline = now + cache.interval
    end
end

function Inventory.count(cache, id)
    if not valid(cache.inventory) then return nil end
    if cache.counts[id] == nil then
        cache.names[id] = cache.names[id] or FName(id)
        cache.counts[id] = cache.inventory:CountItemNum(cache.names[id])
    end
    return cache.counts[id]
end

function Inventory.subscribe(cache)
    local hooked = 0
    local function subscribe(class, method, helper)
        local path = "/Script/Pal." .. class .. ":" .. method
        if not valid(StaticFindObject(path)) then return end
        RegisterHook(path, function() end, function(context)
            local inventory = cache.inventory
            if not valid(inventory) then return end
            local target = helper and inventory.InventoryMultiHelper or inventory
            local source = context:get()
            if valid(target) and valid(source) and source:GetAddress() == target:GetAddress() then
                cache.dirty = true -- Coalesce a burst; count only on the next game-thread refresh.
            end
        end)
        hooked = hooked + 1
    end
    for _, method in ipairs({"OnUpdateInventoryContainer", "OnUpdateEssentialContainer",
        "OnUpdateLoadoutSlot", "OnUpdateEquipmentSlot", "OnRep_InventoryInfo"}) do
        subscribe("PalPlayerInventoryData", method, false)
    end
    for _, method in ipairs({"OnUpdateContainerContent", "OnRep_Containers"}) do
        subscribe("PalItemContainerMultiHelper", method, true)
    end
    -- shortcut: handlers can be bypassed by future game versions; reconcile every 10s (1s without hooks).
    cache.interval = hooked > 0 and 10 or 1
    print("[PalworldPinItems] Inventory update subscriptions: " .. hooked)
end

return Inventory
