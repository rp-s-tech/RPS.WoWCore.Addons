local Lib = LibStub("NobleNextLib-1.0")
local SafeString = Lib.Runtime.Util.SafeString

-- Return the native control; selection and actions remain owned by the caller.
-- menu(dropdown, rootDescription) uses the native CreateRadio/CreateButton API.
-- After an external selection change, call dropdown:GenerateMenu().
function Lib.Widgets.CreateDropdown(parent, options)
    options = options or {}
    local dropdown = CreateFrame("DropdownButton", options.name, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(options.width or 190)
    dropdown:SetDefaultText(SafeString(options.defaultText))
    if options.menu then dropdown:SetupMenu(options.menu) end
    return dropdown
end
