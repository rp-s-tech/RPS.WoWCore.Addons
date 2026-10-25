-- Public, presentation-only recipient of the existing AIO storyline callback.
-- Sending controls remain in the access-gated NobleNextDM Master module.
local _, ns = ...
_G.NobleNextMaster = _G.NobleNextMaster or {}
function _G.NobleNextMaster.OnTalkingHead(line, unitName, creator)
    if not line then return end
    local ok = pcall(function()
        if TalkingHeadFrame and TalkingHeadFrame_PlayCurrent then
            TalkingHeadFrame_PlayCurrent(unitName or "NPC", line, nil, creator or "", 0, false)
        else
            print(ns.Color("gold", "[TalkingHead] ") .. (unitName or "NPC") .. ": " .. line)
        end
    end)
    if not ok then
        print(ns.Color("gold", "[TalkingHead] ") .. (unitName or "NPC") .. ": " .. line)
    end
end
