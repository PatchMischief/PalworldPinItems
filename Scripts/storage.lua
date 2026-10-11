local Storage = {}
local function valid(object) return object and object:IsValid() end
local function guid_key(id) return id.A .. ":" .. id.B .. ":" .. id.C .. ":" .. id.D end

function Storage.new()
    return {counts = {}, pending = {}, dirty = false, version = 0, deadline = 0, interval = 10, label = "Backpack"}
end

local function overlay(controller)
    local hud = valid(controller) and controller:GetHUD() or nil
    return valid(hud) and hud:IsAnyOverlayUIActive()
end

local function request(cache, enabled)
    if valid(cache.network) and valid(cache.controller) and not cache.controller:HasAuthority() then
        -- Native menus share this subscription; release after their overlay closes.
        if not enabled and overlay(cache.controller) then
            cache.pending[cache.key] = {network = cache.network, controller = cache.controller, id = cache.id}
            return
        end
        cache.network:RequestReplicateBaseCampItemStackInfo_ToServer(cache.id, enabled)
    end
end

function Storage.bind(cache, controller, now, has_pins)
    local base
    if has_pins and valid(controller) then
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local player = utility:GetPlayerCharacter(controller)
        local check = valid(player) and player.InsideBaseCampCheckComponent or nil
        if valid(check) and check:IsInsideBaseCamp() then base = check:GetInsideBaseCampModel() end
    end
    local key = valid(base) and guid_key(base:GetId()) or nil
    local address = valid(controller) and controller:GetAddress() or nil
    for pending_key, pending in pairs(cache.pending) do
        if pending_key == key and valid(pending.controller) and pending.controller:GetAddress() == address then
            cache.pending[pending_key] = nil
        elseif not overlay(pending.controller) then
            if valid(pending.controller) and not pending.controller:HasAuthority() and valid(pending.network) then
                pending.network:RequestReplicateBaseCampItemStackInfo_ToServer(pending.id, false)
            end
            cache.pending[pending_key] = nil
        end
    end
    if cache.key ~= key or cache.address ~= address then
        request(cache, false)
        cache.key, cache.address, cache.controller = key, address, controller
        cache.counts, cache.network, cache.id, cache.label = {}, nil, nil, "Backpack"
        cache.resubscribe = false
        cache.dirty = true
        if key then
            local id = base:GetId()
            cache.id = {A = id.A, B = id.B, C = id.C, D = id.D}
            -- Hosts already own storage; this RPC assumes a remote connection and crashes without one.
            if not controller:HasAuthority() then
                local transmitter = controller.Transmitter
                cache.network = valid(transmitter) and transmitter:GetBaseCamp() or nil
            end
            local name = base:GetBaseCampName()
            if type(name) ~= "string" then name = name:ToString() end
            local number = name:match("[0-9]+")
            cache.label = "Backpack + " .. (number and ("Base " .. number) or "current base")
            cache.deadline = now + cache.interval
            request(cache, true)
        end
    end
    if key and (cache.resubscribe or now >= cache.deadline) then
        request(cache, true)
        cache.resubscribe, cache.dirty = false, true
    end
    if cache.dirty then
        cache.counts, cache.ready, cache.dirty = {}, false, false
        cache.version = cache.version + 1
        cache.deadline = now + cache.interval
    end
end

function Storage.count(cache, id)
    if not cache.key then return 0 end
    if not cache.ready then
        -- One bulk snapshot for this base; copy values before reflected entries expire.
        local infos = {}
        local utility = StaticFindObject("/Script/Pal.Default__PalItemUtility")
        utility:CollectLocalPlayerControllableAllItemInfos(cache.controller, infos, 1) -- BaseCampOnly.
        local counts = {}
        for _, entry in ipairs(infos) do
            local info = entry.get and entry:get() or entry
            local item = info.StaticItemId:ToString()
            if item ~= "None" and item ~= "" and info.Num > 0 then
                counts[item] = (counts[item] or 0) + info.Num
            end
        end
        cache.counts, cache.ready = counts, true
    end
    return cache.counts[id] or 0
end

function Storage.subscribe(cache)
    local hooked = 0
    for _, method in ipairs({"OnUpdateItemContainer", "OnRep_ItemStackRepInfoArray",
        "OnAvailableConcreteModel", "OnNotAvailableConcreteModel", "OnUpdatePrivateLockPlayerUId_ServerInternal",
        "OnUpdatePasswordLock_ServerInternal", "OnUpdateGuildSecurity_ServerInternal"}) do
        local path = "/Script/Pal.PalBaseCampModuleItemStackInfo:" .. method
        if valid(StaticFindObject(path)) then
            RegisterHook(path, function() end, function(context)
                if not cache.key then return end
                local module = context:get()
                if valid(module) and guid_key(module.OwnerBaseCampId) == cache.key then cache.dirty = true end
            end)
            hooked = hooked + 1
        end
    end
    local request_path = "/Script/Pal.PalNetworkBaseCampComponent:RequestReplicateBaseCampItemStackInfo_ToServer"
    if valid(StaticFindObject(request_path)) then
        RegisterHook(request_path, function() end, function(context, id, enabled)
            local source = context:get()
            if cache.key and valid(cache.network) and valid(source)
                and source:GetAddress() == cache.network:GetAddress() and guid_key(id:get()) == cache.key
                and not enabled:get() then cache.resubscribe = true end
        end)
    end
    -- shortcut: native update handlers may change; recover missed notifications without per-frame chest scans.
    cache.interval = hooked > 0 and 10 or 1
    print("[PalworldPinItems] Base storage subscriptions: " .. hooked)
end

return Storage
