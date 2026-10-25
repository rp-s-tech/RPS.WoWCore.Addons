-- NobleNext.lua — точка входа клиентского аддона (/nn)

local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local printFunc = ns.Print or print
        printFunc("Загружен. Открыть меню: /nn или кнопка у миникарты.")
    end
end)
