-- Core/Scheduler.lua — отложенная обработка очередей
local ns = LibStub("NobleNextLib-1.0").Runtime

ns.Scheduler = ns.Scheduler or {}

function ns.Scheduler.RunBatched(items, perTick, fn, onDone)
    perTick = perTick or 50
    local index = 1

    local function step()
        local last = math.min(index + perTick - 1, #items)
        for i = index, last do
            fn(items[i], i)
        end
        index = last + 1
        if index <= #items then
            C_Timer.After(0, step)
        elseif onDone then
            onDone()
        end
    end

    if #items == 0 then
        if onDone then onDone() end
        return
    end
    step()
end
