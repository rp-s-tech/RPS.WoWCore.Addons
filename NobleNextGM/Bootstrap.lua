-- The addon name is not its saved-settings global. Keep a private extension table.
local addonName, ns = ...
local api = _G.NobleNextAPI
assert(api and type(api.InitializeExtension) == "function", "NobleNext must load before " .. addonName)
api.InitializeExtension(ns, addonName, 2)
