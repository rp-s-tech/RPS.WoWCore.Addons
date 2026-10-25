-- Only the public shell activates the passive extension services from Lib.
local ns = _G.NobleNextAPI
assert(ns and ns.Extensions and ns.Extensions.AttachShell, "NobleNextLib extension services are missing")
ns.Extensions.AttachShell()
