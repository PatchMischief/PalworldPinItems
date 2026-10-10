package.path = "Scripts/?.lua;" .. package.path
local Inventory = require("inventory")
local reads, names = 0, 0
FName = function(id) names = names + 1; return id end
local function inventory(address, count)
    return {IsValid = function() return true end, GetAddress = function() return address end,
        CountItemNum = function() reads = reads + 1; return count end}
end
StaticFindObject = function() return nil end
RegisterHook = function() error("Missing native functions must not be hooked") end
local cache = Inventory.new()
Inventory.subscribe(cache)
assert(cache.interval == 1, "Missing event handlers must use the faster fallback")
local original = inventory(1, 0)
Inventory.bind(cache, original, 0, true)
assert(Inventory.count(cache, "Wood") == 0 and Inventory.count(cache, "Wood") == 0)
assert(reads == 1 and names == 1, "Zero counts must be cached")
Inventory.bind(cache, original, 0.5, true)
Inventory.count(cache, "Wood")
assert(reads == 1)
Inventory.bind(cache, original, 1, true)
Inventory.count(cache, "Wood")
assert(reads == 2 and names == 1, "Fallback recounting must reuse item names")
Inventory.bind(cache, inventory(2, 8), 1.1, true)
assert(Inventory.count(cache, "Wood") == 8, "A different local inventory must invalidate cached counts")
Inventory.bind(cache, nil, 1.2, true)
assert(Inventory.count(cache, "Wood") == nil, "Unavailable inventory must not show old owned counts")
local version = cache.version
Inventory.bind(cache, nil, 20, false)
assert(cache.version == version, "An empty pin list must not trigger periodic recounts")
print("Inventory cache tests passed: zero counts, no-hook fallback, owner replacement, missing inventory, idle.")
