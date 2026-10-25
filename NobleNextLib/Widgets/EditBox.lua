local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Widgets = Lib.Widgets

function Widgets.CreateEditBox(parent, options)
    options = options or {}
    local width = options.width or 80
    local height = options.height or 22
    local globalName = options.name
    local box = CreateFrame("EditBox", globalName, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetAutoFocus(false)
    box:SetAltArrowKeyMode(false)
    box:SetFontObject(Theme.FONT.highlight)
    Theme.Apply(box, "input")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if options.text then
        box:SetText(options.text)
    end
    if options.numeric then
        box:SetNumeric(true)
    end
    return box
end

function Widgets.CreateEditBoxLegacy(parent, name, width, height)
    local globalName = nil
    if name then
        -- Keep legacy global naming for old call sites that rely on it.
        globalName = (parent:GetName() or "NobleNext") .. "_Edit_" .. tostring(name):gsub("[^%w_]", "_")
    end
    return Widgets.CreateEditBox(parent, {
        name = globalName,
        width = width,
        height = height,
    })
end
