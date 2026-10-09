package.path = "Scripts/?.lua;" .. package.path
local Recipes = require("recipes")
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local tracker = Recipes.new_tracker()
local row = {Product_Count = 3, Material1_Id = "Wood", Material1_Count = 10,
    Material2_Id = "Stone", Material2_Count = 5, Material3_Id = "Wood", Material3_Count = 2,
    Material4_Id = "None", Material4_Count = 100, Material5_Id = "Fiber", Material5_Count = 0}
local recipe = Recipes.from_row("craft", "Arrow", row, "Arrow")
equal(recipe.output, 3)
equal(#recipe.materials, 2)
equal(recipe.materials[1].count, 12)
equal(Recipes.from_row("craft", "None", row), nil)
equal(Recipes.from_row("build", "FreeObject", {}), nil)
local free = Recipes.from_row("craft", "FreeRecipe", {Product_Id = "FreeItem"})
assert(free and #free.materials == 0, "A valid zero-cost recipe must remain pinnable")
equal(Recipes.toggle(tracker, recipe), true)
equal(Recipes.is_pinned(tracker, recipe), true)
recipe.materials[1].count = 999
equal(tracker.pins[1].materials[1].count, 12)
local building = Recipes.from_row("build", "Arrow", {Material1_Id = "Wood", Material1_Count = 20}, "Building")
equal(Recipes.toggle(tracker, building), true)
equal(#tracker.pins, 2)
local owned = {Wood = 30, Stone = 0}
local function render() return Recipes.render(tracker, function(id) return id end, function(id) return owned[id] end) end
equal(render(), "Arrow x3\n  Wood: 12/30\n  Stone: 5/0\n\nBuilding\n  Wood: 20/30\n")
owned.Wood = 8
assert(render():find("Wood: 12/8", 1, true), "Owned material counts must refresh for existing pins")
assert(Recipes.render(tracker, function(id) return id end):find("Wood: 12/?", 1, true), "Unavailable inventory must not be reported as zero")
equal(Recipes.toggle(tracker, recipe), false)
equal(#tracker.pins, 1)
equal(Recipes.toggle(tracker, nil), false)
print("Recipe tests passed: costs, batch yield, duplicate ingredients, detached pins, craft/build IDs, unpin.")
