-- NobleNextDM is separate from the historical NobleNextDB saved-settings global.
local addonName, ns = ...
local api = _G.NobleNextAPI
assert(api and type(api.InitializeExtension) == "function", "NobleNext must load before " .. addonName)
api.InitializeExtension(ns, addonName, 1)
