-- Compatibility adapter for existing panels, provided by the shared library.
local NNL = LibStub("NobleNextLib-1.0")
local ns = NNL.Runtime

ns.VirtualList = NNL.VirtualList

function ns.VirtualList.Create(scrollChild, opts)
    opts = opts or {}
    if NNL and NNL.Scroll and NNL.Scroll.CreateVirtualList then
        -- Attach scrollFrame if parent of scrollChild is a ScrollFrame.
        local parent = scrollChild:GetParent()
        if parent and parent.GetObjectType and parent:GetObjectType() == "ScrollFrame" then
            opts.scrollFrame = opts.scrollFrame or parent
        end
        return NNL.Scroll.CreateVirtualList(scrollChild, opts)
    end

    error("NobleNext VirtualList requires NobleNextLib.Scroll")
end
