local cases = {}
local function Setup()
    local boxes, buttons, dropdowns, requests, events = {}, {}, {}, {}, {}
    local function Frame()
        local f = {shown=true,text="",scripts={}}
        function f:SetAllPoints() end
        function f:SetPoint() end
        function f:SetAutoFocus() end
        function f:SetEnabled(value) self.enabled=value end
        function f:EnableMouse(value) self.mouse=value end
        function f:EnableKeyboard(value) self.keyboard=value end
        function f:ClearFocus() end
        function f:SetText(text) self.text=text end
        function f:GetText() return self.text end
        function f:SetShown(shown) self.shown=shown end
        function f:Hide() self.shown=false end
        function f:IsShown() return self.shown end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        -- Layout-only widget methods (sections, textures, anchors) return a fresh stub.
        setmetatable(f,{__index=function(_,k) if type(k)=="string" and k:match("^%u") then return function() return Frame() end end end})
        return f
    end
    CreateFrame=function() return Frame() end
    GetServerTime=function() return 100 end
    GetTime=function() return 10 end
    UnitGUID=function() return "Player-1-1" end
    unpack=unpack or table.unpack
    local R={handlers={}, Bind=function() return true end}
    R.Send=function(...) requests[#requests+1]={...} end
    local ns={RPSClient=R,NNL={Widgets={}},PrintError=function(text) events.error=text end}
    ns.CreateNGLabel=function(_,text) local f=Frame(); f.text=text; return f end
    ns.CreateNGEditBox=function() local f=Frame(); boxes[#boxes+1]=f; return f end
    ns.CreateNGButton=function(_,text) local f=Frame(); buttons[text]=f; return f end
    ns.NNL.Widgets.CreateDropdown=function(_,options)
        local f=Frame(); f.options=options
        function f:GenerateMenu()
            self.radios={}
            options.menu(self,{CreateRadio=function(_,text,selected,callback,value)
                self.radios[#self.radios+1]={text=text,callback=callback,value=value,selected=selected}
            end})
        end
        function f:Choose(index) self:GenerateMenu(); local radio=self.radios[index]; radio.callback(radio.value) end
        dropdowns[#dropdowns+1]=f; return f
    end
    ns.Subscribe=function(_,key,fn) events[key]=fn end
    ns.RegisterModule=function(_,build) events.build=build end
    assert(loadfile(ROOT.."/Addons/NobleNextDM/GM/Items/Init.lua"))("NobleNextDM",ns)
    local panel=events.build(Frame()); panel.scripts.OnShow()
    local t={R=R,boxes=boxes,buttons=buttons,dropdowns=dropdowns,requests=requests,events=events}
    function t:State(target,stats,requestId)
        R.handlers.ItemEnchantState(nil,{stats=stats or {{key="accuracy",label="Меткость",limit=20},{key="maxHealth",label="ОЗ",limit=1000}},
            requestId=requestId,catalog={{id=18017,kind="enchant",name="Test ability",effects={{trigger="use",spell_id=16591}}}},
            state={target=target or "Player-1-1",name="Tester",slots={{slot=0,guid="Item-1-1",entry=1,grade=3,gemSlots=2,enchant=18017,
                metadata={revision=4,properties={accuracy=2,maxHealth=-3}}}}}})
    end
    return t
end
function cases.save_retry()
    local t=Setup(); t:State(); t.dropdowns[1]:Choose(1)
    assert(t.boxes[2]:GetText()=="2" and t.boxes[3]:GetText()=="-3")
    t.boxes[1]:SetText("test reason"); t.boxes[2]:SetText("-4"); t.boxes[3]:SetText("7")
    t.buttons["Сохранить"].scripts.OnClick()
    local request=t.requests[#t.requests]
    assert(request[1]=="DmItemProperties" and request[5]==4 and request[8].accuracy==-4 and request[8].maxHealth==7)
    t.R.handlers.ItemMetadataResult(nil,{requestId=request[10],ok=false,code="save_failed"})
    assert(t.boxes[2]:GetText()=="-4" and t.boxes[3]:GetText()=="7", "failure preserves draft")
    t.buttons["Сохранить"].scripts.OnClick()
    local retry=t.requests[#t.requests]
    assert(retry[10]==request[10] and retry[8]==request[8], "retry uses exact intent")
    t.R.handlers.ItemMetadataResult(nil,{requestId=request[10],ok=true})
    assert(t.requests[#t.requests][1]=="RequestItemEnchantState")
end
function cases.target_and_catalog()
    local t=Setup(); t:State(); t.dropdowns[1]:Choose(1)
    t.R.target={isPlayer=true,guid="Player-1-2"}; t.events.rps_dm_items()
    assert(t.boxes[2]:GetText()=="" and t.boxes[3]:GetText()=="", "clear old item on target switch")
    t:State("Player-1-1"); t.dropdowns[1]:GenerateMenu()
    assert(#t.dropdowns[1].radios==0,"late old target snapshot ignored")
    t:State("Player-1-2",{{key="accuracy",label="Меткость",limit=20}})
    assert(not t.boxes[3]:IsShown(),"removed catalog field stays hidden")
    t.dropdowns[1]:Choose(1)
    t.boxes[1]:SetText("test reason"); t.boxes[2]:SetText("1.5")
    local count=#t.requests; t.buttons["Сохранить"].scripts.OnClick(); assert(#t.requests==count)
    t.boxes[2]:SetText("0"); t.buttons["Сохранить"].scripts.OnClick()
    assert(next(t.requests[#t.requests][8])==nil,"zero removes the modifier")
end
function cases.snapshot_and_selection()
    local t=Setup(); t:State(); t.dropdowns[1]:Choose(1)
    t.dropdowns[3]:GenerateMenu(); t.dropdowns[4]:GenerateMenu()
    assert(t.dropdowns[3].radios[4].selected(3), "quality follows the selected item")
    assert(t.dropdowns[4].radios[2].selected(18017), "ability follows the selected item")
    t.dropdowns[2]:GenerateMenu()
    assert(#t.dropdowns[2].radios==5, "only two available runes, quality and ability")
    t.boxes[2]:SetText("9"); t.boxes[2].scripts.OnTextChanged(t.boxes[2],true)
    local count=#t.requests; t.events.rps_dm_items(); t:State()
    assert(#t.requests==count and t.boxes[2]:GetText()=="9", "same target updates preserve the draft without requests")
    t.buttons["Обновить"].scripts.OnClick()
    local latest=t.requests[#t.requests][3]
    t:State(nil,nil,latest-1); assert(t.boxes[2]:GetText()=="9", "obsolete refresh ignored")
    t:State(nil,nil,latest); assert(t.boxes[2]:GetText()=="2")
end
function cases.rejected_operation()
    local t=Setup(); t:State(); t.dropdowns[1]:Choose(1); t.dropdowns[2]:Choose(2)
    t.boxes[1]:SetText("test reason"); t.boxes[2]:SetText("5")
    t.buttons["Сохранить"].scripts.OnClick(); local old=t.requests[#t.requests]
    assert(not t.dropdowns[2].enabled and not t.boxes[2].keyboard)
    t.buttons["Обновить"].scripts.OnClick(); assert(t.requests[#t.requests]==old, "cannot discard an in-flight write")
    t.R.handlers.ItemMetadataResult(nil,{requestId=old[10],ok=false,code="no_gem_slot"})
    assert(t.dropdowns[2].enabled and t.boxes[2].keyboard)
    t.dropdowns[2]:Choose(1); t.boxes[2]:SetText("7"); t.buttons["Сохранить"].scripts.OnClick()
    local new=t.requests[#t.requests]
    assert(new[6]=="enchant" and new[10]~=old[10], "terminal refusal must not replay the old rune request")
    local count=#t.requests
    t.R.handlers.ItemMetadataResult(nil,{requestId=new[10],ok=true,state={target="Player-1-1",name="Tester",slots={
        {slot=0,guid="Item-1-1",entry=1,metadata={revision=5,properties={accuracy=7}}}}}})
    assert(#t.requests==count and t.boxes[2]:GetText()=="7", "confirmed result updates without an extra round trip")
end
function cases.switch_while_pending()
    local t=Setup(); t:State(); t.dropdowns[1]:Choose(1); t.boxes[1]:SetText("test reason")
    t.buttons["Сохранить"].scripts.OnClick(); local old=t.requests[#t.requests]
    t.R.target={isPlayer=true,guid="Player-1-2"}; t.events.rps_dm_items(); t:State("Player-1-2")
    local count=#t.requests
    t.R.handlers.ItemMetadataResult(nil,{requestId=old[10],ok=true,state={target="Player-1-1",slots={}}})
    assert(#t.requests==count and t.dropdowns[1].enabled, "old save cannot refresh the new target")
    t.dropdowns[1]:Choose(1); t.buttons["Сохранить"].scripts.OnClick()
    assert(t.requests[#t.requests][2]=="Player-1-2" and t.requests[#t.requests][10]~=old[10])
end
return cases
