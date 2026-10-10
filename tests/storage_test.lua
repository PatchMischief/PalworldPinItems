package.path = "Scripts/?.lua;" .. package.path
local Storage = require("storage")
local function object(fields)
    fields = fields or {}; fields.IsValid = function() return true end; return fields
end
local function id(value) return {A = value, B = 2, C = 3, D = 4} end
local function name(value) return {ToString = function() return value end} end
local function row(item, count) return {StaticItemId = name(item), Num = count} end
local function camp(value, label)
    return object({GetId = function() return id(value) end, GetBaseCampName = function() return label end})
end
local base_a, base_b = camp(1, "Forest"), camp(2, "Desert")
local active, snapshots, player_lookups = nil, 0, 0
local requests, hooks = {}, {}
local rows = {[base_a] = {row("Wood", 7), row("Wood", 3), row("Stone", 4), row("None", 99), row("Empty", 0)},
    [base_b] = {row("Wood", 50)}}
local network = object({GetAddress = function() return 200 end, RequestReplicateBaseCampItemStackInfo_ToServer = function(self, guid, enabled)
    requests[#requests + 1] = {base = guid.A, enabled = enabled}
    local callback = hooks["/Script/Pal.PalNetworkBaseCampComponent:RequestReplicateBaseCampItemStackInfo_ToServer"]
    if callback then callback({get = function() return self end}, {get = function() return guid end}, {get = function() return enabled end}) end
end})
local player = object({InsideBaseCampCheckComponent = object({IsInsideBaseCamp = function() return active ~= nil end,
    GetInsideBaseCampModel = function() return active end})})
local menu_open = false
local controller = object({GetAddress = function() return 100 end, GetHUD = function()
    return object({IsAnyOverlayUIActive = function() return menu_open end}) end,
    Transmitter = object({GetBaseCamp = function() return network end})})
controller.HasAuthority = function() return false end
local utility = object({GetPlayerCharacter = function() player_lookups = player_lookups + 1; return player end})
local collector = object({CollectLocalPlayerControllableAllItemInfos = function(_, context, output, collect_type)
    assert(context == controller and collect_type == 1, "Collect only the local active base, never personal inventory twice")
    snapshots = snapshots + 1
    for index, value in ipairs(rows[active]) do output[index] = {get = function() return value end} end
end})
function StaticFindObject(path)
    if path == "/Script/Pal.Default__PalUtility" then return utility end
    if path == "/Script/Pal.Default__PalItemUtility" then return collector end
    return object()
end
function RegisterHook(path, _, post) hooks[path] = post end
local function updated(base, method)
    local module = object({OwnerBaseCampId = id(base)})
    hooks["/Script/Pal.PalBaseCampModuleItemStackInfo:" .. (method or "OnRep_ItemStackRepInfoArray")]({get = function() return module end})
end
local cache = Storage.new()
Storage.subscribe(cache)
assert(cache.interval == 10)
-- A local host has storage already and no remote connection for the metadata RPC.
active = base_a
local host = object({GetAddress = function() return 101 end, HasAuthority = function() return true end,
    Transmitter = object({GetBaseCamp = function() error("Host metadata RPC path would crash natively") end})})
local host_cache = Storage.new()
Storage.bind(host_cache, host, 0, true)
assert(host_cache.label == "Backpack + Forest" and #requests == 0)
collector.CollectLocalPlayerControllableAllItemInfos = function(_, context, output, collect_type)
    assert((context == controller or context == host) and collect_type == 1)
    snapshots = snapshots + 1
    for index, value in ipairs(rows[active]) do output[index] = {get = function() return value end} end
end
assert(Storage.count(host_cache, "Wood") == 10)
active = base_b
Storage.bind(host_cache, host, 1, true)
assert(Storage.count(host_cache, "Wood") == 50 and #requests == 0)
active = nil
Storage.bind(host_cache, host, 2, false)
assert(Storage.count(host_cache, "Wood") == 0 and #requests == 0)
snapshots, player_lookups = 0, 0
Storage.bind(cache, controller, 0, false)
assert(Storage.count(cache, "Wood") == 0 and player_lookups == 0 and snapshots == 0)
Storage.bind(cache, controller, 0, true)
assert(cache.label == "Backpack" and Storage.count(cache, "Wood") == 0 and #requests == 0)
active = base_a
Storage.bind(cache, controller, 0, true)
assert(cache.label == "Backpack + Forest")
assert(Storage.count(cache, "Wood") == 10 and Storage.count(cache, "Stone") == 4)
assert(Storage.count(cache, "Missing") == 0 and Storage.count(cache, "None") == 0 and snapshots == 1)
assert(#requests == 1 and requests[1].base == 1 and requests[1].enabled)
for _ = 1, 100 do Storage.bind(cache, controller, 0.5, true); Storage.count(cache, "Wood") end
assert(snapshots == 1, "Unchanged base storage must not be scanned per update or per recipe")
updated(2)
Storage.bind(cache, controller, 0.6, true); Storage.count(cache, "Wood")
assert(snapshots == 1, "Other bases must not invalidate this snapshot")
network:RequestReplicateBaseCampItemStackInfo_ToServer(id(1), false)
local request_count = #requests
Storage.bind(cache, controller, 0.65, true)
assert(#requests == request_count + 1 and requests[#requests].enabled, "Closing native menus must resume updates for existing pins")
Storage.count(cache, "Wood")
assert(snapshots == 2)
rows[base_a][1].Num = 9
for _ = 1, 10 do updated(1) end
Storage.bind(cache, controller, 0.7, true)
assert(Storage.count(cache, "Wood") == 12 and snapshots == 3, "Coalesce base updates into one bulk snapshot")
active = base_b
Storage.bind(cache, controller, 1, true)
assert(Storage.count(cache, "Wood") == 50 and Storage.count(cache, "Stone") == 0)
assert(cache.label == "Backpack + Desert")
assert(requests[#requests - 1].base == 1 and not requests[#requests - 1].enabled and requests[#requests].base == 2 and requests[#requests].enabled)
updated(1)
Storage.bind(cache, controller, 1.1, true); Storage.count(cache, "Wood")
assert(snapshots == 4, "Previous-base events must not mix its totals into the current base")
active = nil
Storage.bind(cache, controller, 1.2, true)
assert(cache.label == "Backpack" and Storage.count(cache, "Wood") == 0 and not requests[#requests].enabled)
active = base_a
Storage.bind(cache, controller, 2, true)
Storage.count(cache, "Wood")
Storage.bind(cache, controller, 13, true)
assert(Storage.count(cache, "Wood") == 12 and snapshots == 6, "Recovery snapshot must handle missed events")
menu_open = true
request_count = #requests
Storage.bind(cache, controller, 14, false)
assert(#requests == request_count, "Clearing pins must not stop replication used by an open native menu")
menu_open = false
Storage.bind(cache, controller, 14.1, false)
assert(#requests == request_count + 1 and not requests[#requests].enabled, "Deferred release must finish once menus close")
local lookups = player_lookups
for _ = 1, 100 do Storage.bind(cache, controller, 20, false) end
assert(player_lookups == lookups and snapshots == 6, "No pins must mean no base lookups or storage scans")
Storage.bind(cache, controller, 21, true)
request_count = #requests
controller.IsValid = function() return false end
Storage.bind(cache, nil, 22, false)
assert(#requests == request_count and Storage.count(cache, "Wood") == 0, "World teardown must drop totals without calling a destroyed owner's RPC")
print("Base storage tests passed: duplicate stacks, hash counts, current-base isolation, event bursts, switching/leaving, idle, reconciliation.")
