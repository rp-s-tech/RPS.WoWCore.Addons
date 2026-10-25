local Lib = LibStub("NobleNextLib-1.0")
local Confirm = Lib.Confirm

local DIALOG_NAME = "NOBLENEXTLIB_CONFIRM"
local queue = {}
local active = nil
local showing = false

local function SafeCall(fn)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn)
    if not ok then
        print("|cffff0000[NobleNextLib Confirm]|r " .. tostring(err))
    end
end

local function ShowNext()
    if showing then
        return
    end
    local nextOpts = table.remove(queue, 1)
    if not nextOpts then
        active = nil
        return
    end

    showing = true
    active = nextOpts
    local dialog = StaticPopupDialogs[DIALOG_NAME]
    dialog.button1 = nextOpts.acceptLabel or ACCEPT
    dialog.button2 = nextOpts.cancelLabel or CANCEL
    StaticPopup_Show(DIALOG_NAME, nextOpts.text or "Подтвердить действие?")
end

local function Finish(accepted)
    local opts = active
    active = nil
    showing = false
    if opts then
        if accepted then
            SafeCall(opts.onAccept)
        else
            SafeCall(opts.onCancel)
        end
    end
    -- Defer next dialog so StaticPopup can fully hide first.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ShowNext)
    else
        ShowNext()
    end
end

local function EnsureDialog()
    if StaticPopupDialogs[DIALOG_NAME] then
        return
    end
    StaticPopupDialogs[DIALOG_NAME] = {
        text = "%s",
        button1 = ACCEPT,
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            Finish(true)
        end,
        OnCancel = function()
            Finish(false)
        end,
    }
end

--- Show a destructive/general confirmation dialog.
--- Concurrent Show() calls are serialized (queue); never overwrite an active dialog.
--- options: { text, acceptLabel?, cancelLabel?, onAccept, onCancel }
function Confirm.Show(options)
    options = options or {}
    EnsureDialog()
    queue[#queue + 1] = options
    ShowNext()
end

Lib.Widgets.Confirm = Confirm
