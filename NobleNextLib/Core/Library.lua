-- NobleNextLib core bootstrap (LibStub "NobleNextLib-1.0")
local MAJOR, MINOR = "NobleNextLib-1.0", 11
local Lib = LibStub:NewLibrary(MAJOR, MINOR)
if not Lib then
    return
end

Lib.API_LEVEL = 5
Lib.VERSION = "0.3.182"

-- One library owns shared runtime and presentation. The shell and optional
-- extensions reuse this identity; no privileged module is required to load it.
Lib.Runtime = Lib.Runtime or {}
Lib.Runtime.Util = Lib.Runtime.Util or {}
Lib.Runtime.Events = Lib.Runtime.Events or {}

for _, name in ipairs({ "Theme", "Widgets", "Layout", "Tabs", "Navigation",
        "Scroll", "Window", "Resize", "StateView", "Confirm", "VirtualList" }) do
    Lib[name] = Lib[name] or {}
end

function Lib.HasScrollBox()
    return type(CreateScrollBoxListLinearView) == "function"
        and type(ScrollUtil) == "table"
        and type(CreateDataProvider) == "function"
end

function Lib.HasTabSystem()
    return type(TabSystemOwnerMixin) == "table"
end

function Lib.HasPanelResize()
    return type(PanelResizeButtonMixin) == "table"
end

function Lib.HasPanelDragBar()
    return type(PanelDragBarMixin) == "table"
end

_G.NobleNextLib = Lib
