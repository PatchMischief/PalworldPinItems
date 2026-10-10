"""Execute the mod's standalone Lua tests with the development-only Lupa runtime."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

assert Path('Scripts/recipes.lua').exists(), 'Run this check from PalworldPinItems.'
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tests/recipes_test.lua').read_text(encoding='utf-8'))
lua.execute("assert(loadfile('Scripts/main.lua'))")
lua.execute("assert(loadfile('Scripts/ui.lua'))")
lua.execute("assert(loadfile('Scripts/inventory.lua'))")
lua.execute("assert(loadfile('Scripts/storage.lua'))")
LuaRuntime(unpack_returned_tuples=True).execute(Path('tests/inventory_test.lua').read_text(encoding='utf-8'))
LuaRuntime(unpack_returned_tuples=True).execute(Path('tests/storage_test.lua').read_text(encoding='utf-8'))
print('Runtime Lua syntax passed.')
LuaRuntime(unpack_returned_tuples=True).execute(Path('tests/runtime_test.lua').read_text(encoding='utf-8'))
