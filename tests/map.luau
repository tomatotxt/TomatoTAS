-- Tests reversible clone preparation with mock Instances/signals, not Roblox cloning.
local factory=require("../src/runtime/Map")
local Scope=require("../src/core/Scope")(function() end,{})
local elapsed,yields=0,0
local heartbeat={Wait=function() elapsed+=0.1; yields+=1 end}
local remote
local storage={FindFirstChild=function(_,name) return if name=="Remote" then remote else nil end}
local root={CFrame={}}
local player={Character={HumanoidRootPart=root,FindFirstChild=function(_,name) return if name=="HumanoidRootPart" then root else nil end,
    FindFirstChildOfClass=function(_,name) return if name=="Humanoid" then {Health=100} else nil end}}
local services={RunService={Heartbeat=heartbeat},Players={LocalPlayer=player},ReplicatedStorage=storage,
    HttpService={GenerateGUID=function() return "test-guid" end}}
local environment=setmetatable({game={GetService=function(_,name) return services[name] end},workspace={},
    os={clock=function() return elapsed end},getconnections=function(signal) return {signal} end,
    warn=function() end,
},{__index=getfenv()})
setfenv(factory,environment)
local Map=factory(function(name) assert(name=="core/Scope"); return Scope end,{Timeout=10,BatchSize=2})
local function object(name)
    local state={Name=name,Parent=true,Archivable=false,attributes={},descendants={}}
    local connection={Enabled=true,disables=0,enables=0}
    function connection:Disable() self.Enabled=false; self.disables+=1 end
    function connection:Enable() self.Enabled=true; self.enables+=1 end
    state.connection=connection
    state.GetPropertyChangedSignal=function() return connection end
    state.GetDescendants=function() return state.descendants end
    state.GetAttribute=function(_,key) return state.attributes[key] end
    state.SetAttribute=function(_,key,value) state.attributes[key]=value end
    state.IsA=function() return false end
    state.IsDescendantOf=function(_,ancestor)
        local parent=state.Parent
        while type(parent)=="table" do
            if parent==ancestor then return true end
            parent=parent.Parent
        end
        return false
    end
    state.Destroy=function() state.Parent=nil; state.destroyed=true end
    local instance=setmetatable({},{__index=state,__newindex=function(_,key,value)
        if state.beforeWrite then state.beforeWrite(key,value) end
        if key=="Archivable" and value~=state.Archivable then
            assert(not connection.Enabled,"Archivable trap fired")
        end
        state[key]=value
    end})
    return instance
end
local function prepared()
    elapsed,yields=0,0
    local map=Map.new()
    local live=object("Map")
    for i=1,5 do
        local part=object("Part"..i)
        part.Parent=live
        table.insert(live.descendants,part)
    end
    map.live=live; map.spawn=live.descendants[1]
    map.spawn.CFrame={ToObjectSpace=function() return {} end}
    map.Settle=function() end
    live.Clone=function()
        assert(live.Archivable)
        local clone=object("Clone")
        clone.Parent=nil
        for _,part in ipairs(live.descendants) do
            assert(part.Archivable and not part.connection.Enabled)
            local copy=object(part.Name)
            copy.Parent=clone
            copy.attributes=table.clone(part.attributes)
            copy.CFrame={}
            table.insert(clone.descendants,copy)
        end
        live.lastClone=clone
        return clone
    end
    return map,live
end
local function restored(live)
    local all={live}
    for _,part in ipairs(live.descendants) do table.insert(all,part) end
    for _,part in ipairs(all) do assert(not part.Archivable and part.connection.Enabled) end
end
local count=0
local function test(name,fn) fn(); count+=1; print("PASS "..name) end
test("dense batched clone restores flags and listeners",function()
    local map,live=prepared()
    local clone=map:Clone()
    restored(live)
    assert(yields==3 and clone.Parent==environment.workspace and live.Parent==storage)
    assert(map.cloneSpawn==clone.descendants[1])
    for _,part in ipairs(live.descendants) do assert(part.connection.disables==1 and part.connection.enables==1) end
    map:Destroy()
    assert(live.Parent==true and clone.Parent==nil)
end)
test("clone failure restores source and listeners",function()
    local map,live=prepared()
    live.Clone=function() error("simulated clone failure") end
    assert(not pcall(function() map:Clone() end))
    restored(live)
    assert(live.Parent==true and not map.clone)
    assert(next(map.spawn.attributes)==nil)
    map:Destroy()
end)
test("cancelled batch restores changed instances",function()
    local map,live=prepared()
    local originalWait=heartbeat.Wait
    heartbeat.Wait=function() originalWait(); map.generation+=1 end
    local ok=pcall(function() map:Clone() end)
    heartbeat.Wait=originalWait
    assert(not ok)
    restored(live)
    assert(live.Parent==true and not map.clone)
    map:Destroy()
end)
test("unrestorable listener rejected without mutating protected part",function()
    local map,live=prepared()
    live.descendants[2].connection.Enable=nil
    assert(not pcall(function() map:Clone() end))
    restored(live)
    assert(live.descendants[2].connection.disables==0)
    map:Destroy()
end)
local function pose(x,angle)
    local position=setmetatable({x=x},{__sub=function(a,b) return {Magnitude=math.abs(a.x-b.x)} end})
    return {Position=position,angle=angle or 0,ToObjectSpace=function(self,other)
        return {ToAxisAngle=function() return nil,other.angle-self.angle end}
    end}
end
test("spawn settle waits a full quiet second after movement",function()
    elapsed,yields=0,0
    local map=Map.new()
    local spawn={Parent=true,CFrame=pose(0)}
    local originalWait=heartbeat.Wait
    heartbeat.Wait=function()
        originalWait()
        if yields==5 then spawn.CFrame=pose(1) end
    end
    map:Settle(spawn)
    heartbeat.Wait=originalWait
    assert(elapsed>=1.5)
    map:Destroy()
end)
test("subthreshold drift cannot falsely settle",function()
    elapsed,yields=0,0
    local map=Map.new()
    local spawn={Parent=true,CFrame=pose(0)}
    local originalWait=heartbeat.Wait
    heartbeat.Wait=function() originalWait(); spawn.CFrame=pose(yields*0.003) end
    local ok=pcall(function() map:Settle(spawn) end)
    heartbeat.Wait=originalWait
    assert(not ok and elapsed>=10)
    map:Destroy()
end)
test("living character readiness ignores temporary movement locks",function()
    local original=player.Character
    local root={Anchored=true}
    local humanoid={Health=100,WalkSpeed=16}
    local character={
        FindFirstChild=function(_,name) return if name=="HumanoidRootPart" then root else nil end,
        FindFirstChildOfClass=function(_,name) return if name=="Humanoid" then humanoid else nil end,
    }
    player.Character=character
    local map=Map.new()
    assert(map:LivingCharacter()==character)
    map:Destroy()
    player.Character=original
end)
test("wait timeout preserves an actionable reason",function()
    elapsed,yields=0,0
    local map=Map.new()
    local ok,err=pcall(function()
        map:Wait(function() return nil end,map.generation,"Timed out waiting for test readiness")
    end)
    assert(not ok and tostring(err):find("Timed out waiting for test readiness",1,true))
    map:Destroy()
end)
test("equal-size hierarchy replacement is rejected before cloning",function()
    local map,live=prepared()
    local originalWait=heartbeat.Wait
    local old=live.descendants[5]
    heartbeat.Wait=function()
        originalWait()
        if yields==1 then
            local replacement=object("replacement"); replacement.Parent=live
            live.descendants[5]=replacement
        end
    end
    local ok=pcall(function() map:Clone() end)
    heartbeat.Wait=originalWait
    assert(not ok and not live.lastClone and live.Parent==true and not map.clone)
    restored(live)
    assert(not old.Archivable and old.connection.Enabled)
    map:Destroy()
end)
test("failed sandbox parenting restores live map and destroys clone",function()
    local map,live=prepared()
    local cloneMethod=live.Clone
    live.Clone=function()
        local clone=cloneMethod()
        clone.beforeWrite=function(key,value)
            if key=="Parent" and value==environment.workspace then error("sandbox parent blocked") end
        end
        return clone
    end
    assert(not pcall(function() map:Clone() end))
    restored(live)
    assert(live.Parent==true and live.lastClone.destroyed and not map.clone)
    map:Destroy()
end)
test("failed live parenting destroys uncommitted clone",function()
    local map,live=prepared()
    live.beforeWrite=function(key,value)
        if key=="Parent" and value==storage then error("live parent blocked") end
    end
    assert(not pcall(function() map:Clone() end))
    restored(live)
    assert(live.Parent==true and live.lastClone.destroyed and not map.clone)
    map:Destroy()
end)
test("failure after listener disabling re-enables it",function()
    local map,live=prepared()
    local connection=live.descendants[1].connection
    connection.Disable=function(self) self.Enabled=false; error("partial disable failed") end
    assert(not pcall(function() map:Clone() end))
    restored(live)
    assert(connection.enables==1 and not map.clone)
    map:Destroy()
end)
test("already disabled listeners stay disabled",function()
    local map,live=prepared()
    local connection=live.descendants[1].connection
    connection.Enabled=false
    map:Clone()
    assert(not connection.Enabled and connection.disables==0 and connection.enables==0)
    map:Destroy()
end)
test("spawn removal on the final settle heartbeat rejects",function()
    elapsed,yields=0,0
    local map=Map.new()
    local spawn={Parent=true,CFrame=pose(0)}
    local originalWait=heartbeat.Wait
    heartbeat.Wait=function() originalWait(); if elapsed>=1 then spawn.Parent=nil end end
    local ok=pcall(function() map:Settle(spawn) end)
    heartbeat.Wait=originalWait
    assert(not ok)
    map:Destroy()
end)
test("a later round cannot overwrite sandbox rope data",function()
    local listener
    local event={Connect=function(_,fn)
        listener=fn
        return {Destroy=function() listener=nil end,Disconnect=function() listener=nil end}
    end}
    remote={FindFirstChild=function(_,name) return if name=="UpdRopeData" then {OnClientEvent=event} else nil end}
    local map=Map.new()
    remote=nil
    local originalSource,newSource={},{}
    local current=originalSource
    environment.workspace.FindFirstChild=function(_,name)
        if name=="Multiplayer" then return {FindFirstChild=function(_,child) return if child=="Map" then current else nil end} end
        return nil
    end
    map.live=originalSource
    local originalRopes,newRopes={{positions={1}}},{{positions={2}}}
    listener(originalRopes)
    assert(map.ropes==originalRopes)
    map.clone={Destroy=function() end}
    current=newSource
    listener(newRopes)
    assert(map.ropes==originalRopes and map.ropeCache[newSource]==newRopes)
    map:Destroy()
    environment.workspace.FindFirstChild=nil
    assert(not listener)
end)
test("zipline restore waits for a ready environment and avoids duplicate writes",function()
    local map=Map.new()
    local originalCharacter=player.Character
    local scriptObject={}
    local character={FindFirstChild=function(_,name) return if name=="FE2_Character" then scriptObject else nil end}
    player.Character=character
    elapsed,yields=0,0
    local fn=function() end
    local value,writes=nil,0
    map.ropes={{positions={1}}}
    environment.getsenv=function() return if yields>=2 then {startZipline=fn} else {} end
    environment.getupvalue=function() return value end
    environment.setupvalue=function(_,index,nextValue) assert(index==2); value=nextValue; writes+=1 end
    assert(map:RestoreRopes(character) and yields>=2 and value==map.ropes)
    assert(map:RestoreRopes(character,true) and writes==1)
    map:Destroy(); player.Character=originalCharacter
end)

-- Integration fixtures exercise the real Acquire/Clone/Respawn path, including
-- parenting signals and rename events used by recording-only map cleanup.
local function signal()
    local event={listeners={},Enabled=true}
    function event:Disable() self.Enabled=false end
    function event:Enable() self.Enabled=true end
    function event:Connect(fn)
        local connection={Connected=true}
        self.listeners[connection]=fn
        function connection:Disconnect() self.Connected=false; event.listeners[self]=nil end
        connection.Destroy=connection.Disconnect
        return connection
    end
    function event:Fire(...)
        for connection,fn in pairs(table.clone(self.listeners)) do
            if connection.Connected then fn(...) end
        end
    end
    return event
end
local vectorMeta={}
local function vector(x,y,z) return setmetatable({X=x,Y=y,Z=z,Magnitude=math.sqrt(x*x+y*y+z*z)},vectorMeta) end
vectorMeta.__sub=function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local frameMeta={}
local function frame(x,y,z)
    return setmetatable({Position=vector(x,y,z),ToAxisAngle=function() return nil,0 end,
        ToObjectSpace=function(self,other)
            local delta=other.Position-self.Position
            return frame(delta.X,delta.Y,delta.Z)
        end},frameMeta)
end
frameMeta.__mul=function(a,b)
    return frame(a.Position.X+b.Position.X,a.Position.Y+b.Position.Y,a.Position.Z+b.Position.Z)
end
local function instance(name,class)
    local state={Name=name,ClassName=class or "Model",Archivable=false,_children={},_signals={},
        ChildAdded=signal(),ChildRemoved=signal(),attributes={}}
    local node
    state.IsA=function(_,kind)
        return kind==state.ClassName or kind=="BasePart" and state.ClassName=="Part"
            or kind=="BaseScript" and state.ClassName=="LocalScript"
    end
    state.GetPropertyChangedSignal=function(_,key)
        if not state._signals[key] then state._signals[key]=signal() end
        return state._signals[key]
    end
    state.GetChildren=function() return table.clone(state._children) end
    state.GetDescendants=function()
        local result={}
        local function collect(parent)
            for _,child in ipairs(parent:GetChildren()) do
                table.insert(result,child); collect(child)
            end
        end
        collect(node)
        return result
    end
    state.FindFirstChild=function(_,childName,recursive)
        for _,child in ipairs(state._children) do if child.Name==childName then return child end end
        if recursive then
            for _,child in ipairs(state._children) do
                local found=child:FindFirstChild(childName,true)
                if found then return found end
            end
        end
        return nil
    end
    state.FindFirstChildOfClass=function(_,kind)
        for _,child in ipairs(state._children) do if child:IsA(kind) then return child end end
        return nil
    end
    state.IsDescendantOf=function(_,ancestor)
        local parent=state.Parent
        while parent do
            if parent==ancestor then return true end
            parent=parent.Parent
        end
        return false
    end
    state.GetFullName=function()
        return if state.Parent and state.Parent.GetFullName then state.Parent:GetFullName().."."..state.Name else state.Name
    end
    state.GetAttribute=function(_,key) return state.attributes[key] end
    state.SetAttribute=function(_,key,value) state.attributes[key]=value end
    state.Destroy=function()
        if state.failDestroy then error("source removal failed") end
        for _,child in ipairs(node:GetChildren()) do child:Destroy() end
        node.Parent=nil
        state.destroyed=true
    end
    state.Clone=function()
        assert(state.Archivable,"unprepared clone")
        local copy=instance(state.Name,state.ClassName)
        copy.CFrame=state.CFrame
        copy.attributes=table.clone(state.attributes)
        for _,child in ipairs(state._children) do child:Clone().Parent=copy end
        return copy
    end
    node=setmetatable({},{__index=function(_,key)
        if key=="Position" and state.CFrame then return state.CFrame.Position end
        if state[key]~=nil then return state[key] end
        return state.FindFirstChild(nil,key)
    end,__newindex=function(_,key,value)
        local previous=state[key]
        if key=="Parent" and previous~=value then
            if previous and previous._children then
                local index=table.find(previous._children,node)
                if index then table.remove(previous._children,index) end
            end
            state[key]=value
            if previous and previous.ChildRemoved then previous.ChildRemoved:Fire(node) end
            if value and value._children then
                table.insert(value._children,node)
                value.ChildAdded:Fire(node)
            end
        else state[key]=value end
        if previous~=value and state._signals[key] then state._signals[key]:Fire() end
    end})
    return node
end
local function integration(fn)
    local oldWorkspace,oldCharacter,oldWait,oldWarn=environment.workspace,player.Character,heartbeat.Wait,environment.warn
    elapsed,yields=0,0
    local world=instance("Workspace","Workspace")
    world.Raycast=function() return nil end
    local multiplayer=instance("Multiplayer","Folder"); multiplayer.Parent=world
    local live=instance("Map"); live.Parent=multiplayer
    local spawn=instance("Spawn","Part"); spawn.CFrame=frame(500,20,0); spawn.Parent=live
    local settings=instance("Settings","Folder"); settings:SetAttribute("MapName","Test Map"); settings.Parent=live
    local function character(x)
        local c=instance("Player")
        local r=instance("HumanoidRootPart","Part"); r.CFrame=frame(x,23,0); r.Anchored=true; r.Parent=c
        local h=instance("Humanoid","Humanoid"); h.Health=100; h.WalkSpeed=16; h.Parent=c
        return c
    end
    local original=character(500)
    environment.workspace,player.Character=world,original
    environment.Vector3={new=vector,zero=vector(0,0,0)}
    environment.RaycastParams={new=function() return {} end}
    environment.Enum={RaycastFilterType={Include="Include"}}
    local map=Map.new()
    local fixture={world=world,multiplayer=multiplayer,live=live,spawn=spawn,map=map,character=character}
    function fixture:prepare()
        local acquired,c=map:Acquire()
        assert(acquired==map and c==player.Character)
        assert(map.name=="Test Map" and map.spawn==spawn and map.offset.Position.Y==3)
    end
    function fixture:sandbox()
        self:prepare()
        local ropes={{positions={1,2,3}}}
        map.ropes=ropes
        local clone=map:Clone()
        local nextCharacter=character(0)
        local respawnYields=0
        heartbeat.Wait=function()
            oldWait()
            if original.Humanoid.Health==0 then
                respawnYields+=1
                player.Character=nextCharacter
                if respawnYields>=3 then nextCharacter.HumanoidRootPart.Anchored=false end
            end
        end
        -- FE2 environment restoration is tested separately above.
        local restoreRopes=map.RestoreRopes
        map.RestoreRopes=function(_,c) assert(c==nextCharacter); return true end
        assert(map:Respawn()==nextCharacter)
        assert(respawnYields>=13 and not nextCharacter.HumanoidRootPart.Anchored)
        map.RestoreRopes=restoreRopes
        heartbeat.Wait=oldWait
        assert(nextCharacter.HumanoidRootPart.CFrame.Position.X==500)
        assert(nextCharacter.HumanoidRootPart.CFrame.Position.Y==23)
        assert(live.Parent==storage and not live.destroyed)
        return clone,ropes
    end
    local ok,err=xpcall(function() fn(fixture) end,debug.traceback)
    map:Destroy()
    environment.workspace,player.Character,heartbeat.Wait,environment.warn=oldWorkspace,oldCharacter,oldWait,oldWarn
    assert(ok,err)
end
test("automatic candidate waits for an actual map and a character at spawn",function()
    integration(function(f)
        player.Character.HumanoidRootPart.CFrame=frame(0,23,0)
        assert(not f.map:AutoCandidate())
        local before=elapsed
        player.Character.HumanoidRootPart.CFrame=frame(500,23,0)
        local live,c=f.map:AutoCandidate()
        assert(live==f.live and c==player.Character and elapsed==before)
        f.live.Name="NewMap"
        assert(not f.map:AutoCandidate())
        f.live.Name="Map"
        player.Character.Humanoid.Health=0
        assert(not f.map:AutoCandidate())
    end)
end)
test("acquire waits for the character to arrive after map replication",function()
    integration(function(f)
        player.Character.HumanoidRootPart.CFrame=frame(0,23,0)
        local normalWait=heartbeat.Wait
        heartbeat.Wait=function()
            normalWait()
            if yields==3 then player.Character.HumanoidRootPart.CFrame=frame(500,23,0) end
        end
        f:prepare()
        assert(elapsed>=1.3)
    end)
end)
test("acquire follows a replaced Multiplayer container while awaiting spawn",function()
    integration(function(f)
        player.Character.HumanoidRootPart.CFrame=frame(0,23,0)
        local replacement=instance("Multiplayer","Folder")
        local newMap=instance("Map"); newMap.Parent=replacement
        local newSpawn=instance("Spawn","Part"); newSpawn.CFrame=frame(700,20,0); newSpawn.Parent=newMap
        local normalWait=heartbeat.Wait
        heartbeat.Wait=function()
            normalWait()
            if yields==1 then f.multiplayer.Parent=nil; replacement.Parent=f.world end
            if yields==3 then player.Character.HumanoidRootPart.CFrame=frame(700,23,0) end
        end
        local map,c=f.map:Acquire()
        assert(map.live==newMap and map.spawn==newSpawn and c==player.Character)
    end)
end)
test("acquire rejects a character that leaves during spawn settling",function()
    integration(function(f)
        local normalWait=heartbeat.Wait
        heartbeat.Wait=function()
            normalWait()
            if yields==3 then player.Character.HumanoidRootPart.CFrame=frame(0,23,0) end
        end
        local ok,err=pcall(function() f.map:Acquire() end)
        assert(not ok and tostring(err):find("Character left the spawn",1,true) and not f.map.live)
    end)
end)
test("source deletion commits only after sandbox respawn and retains ropes",function()
    integration(function(f)
        local clone,ropes=f:sandbox()
        assert(not f.map.sandboxCommitted and not f.map:AutoCandidate())
        assert(f.map:CommitSandbox()==clone)
        assert(f.live.destroyed and f.live.Parent==nil and not f.map.live and not f.map.liveParent)
        assert(f.map.sandboxCommitted and f.map.ropes==ropes and not f.map:ReadyReason())
        assert(f.map:CommitSandbox()==clone)
        f.map:Destroy()
        assert(f.live.Parent==nil and clone.destroyed)
    end)
end)
test("commit refuses source removal before a successful respawn",function()
    integration(function(f)
        f:prepare(); f.map:Clone()
        assert(not pcall(function() f.map:CommitSandbox() end))
        assert(not f.live.destroyed and f.live.Parent==storage and not f.map.sandboxCommitted)
        f.map:Destroy()
        assert(f.live.Parent==f.multiplayer)
    end)
end)
test("uncommitted sandbox stays recoverable on failure",function()
    integration(function(f)
        local clone=f:sandbox()
        f.live.failDestroy=true
        assert(not pcall(function() f.map:CommitSandbox() end))
        assert(not f.map.sandboxCommitted and f.map.live==f.live)
        f.map:Destroy()
        assert(f.live.Parent==f.multiplayer and not f.live.destroyed and clone.destroyed)
    end)
end)
test("respawn timeout leaves the source recoverable and cannot be committed",function()
    integration(function(f)
        f:prepare(); f.map:Clone()
        local nextCharacter=f.character(0)
        local normalWait=heartbeat.Wait
        heartbeat.Wait=function() normalWait(); player.Character=nextCharacter end
        local ok,err=pcall(function() f.map:Respawn() end)
        assert(not ok and tostring(err):find("release the respawned character",1,true))
        assert(not pcall(function() f.map:CommitSandbox() end))
        assert(not f.live.destroyed)
        f.map:Destroy()
        assert(f.live.Parent==f.multiplayer)
    end)
end)
test("commit validates the cloned spawn before deleting the source",function()
    integration(function(f)
        f:sandbox()
        f.map.cloneSpawn.Parent=nil
        assert(not pcall(function() f.map:CommitSandbox() end))
        assert(not f.live.destroyed and f.live.Parent==storage)
        f.map:Destroy()
        assert(f.live.Parent==f.multiplayer)
    end)
end)
test("recording deletes only direct map models and stops deleting on pause",function()
    integration(function(f)
        local clone=f:sandbox()
        assert(not pcall(function() f.map:SetRecording(true) end))
        f.map:CommitSandbox()
        local existing=instance("Map"); existing.Parent=f.multiplayer
        local unrelated=instance("Water"); unrelated.Parent=f.multiplayer
        local nested=instance("Map"); nested.Parent=unrelated
        local sameNamePart=instance("Map","Part"); sameNamePart.Parent=f.multiplayer
        f.map:SetRecording(true)
        assert(existing.destroyed and not unrelated.destroyed and not nested.destroyed and not sameNamePart.destroyed)
        local incoming=instance("NewMap"); incoming.Parent=f.multiplayer
        assert(incoming.destroyed and not clone.destroyed)
        local renamed=instance("Incoming"); renamed.Parent=f.multiplayer; renamed.Name="Map"
        assert(renamed.destroyed)
        f.map:SetRecording(false)
        local paused=instance("NewMap"); paused.Parent=f.multiplayer
        unrelated.Name="Map"
        assert(not paused.destroyed and not unrelated.destroyed)
        f.map:SetRecording(true)
        assert(paused.destroyed and unrelated.destroyed and not clone.destroyed)
        f.map:Destroy()
        local after=instance("Map"); after.Parent=f.multiplayer
        assert(not after.destroyed)
    end)
end)
test("live recording leaves maps intact and installs no cleanup watcher",function()
    integration(function(f)
        f:prepare()
        f.map:SetRecording(true)
        assert(not f.map.recording and not f.map.recordingScope and not f.live.destroyed)
        local newRound=instance("NewMap"); newRound.Parent=f.multiplayer
        assert(not newRound.destroyed and next(f.world.ChildAdded.listeners)==nil)
        assert(next(f.multiplayer.ChildAdded.listeners)==nil)
    end)
end)
test("asynchronous removal failure disconnects the watcher and warns once",function()
    integration(function(f)
        f:sandbox(); f.map:CommitSandbox(); f.map:SetRecording(true)
        local warnings=0
        environment.warn=function(message)
            assert(message:find("Incoming map cleanup stopped",1,true)); warnings+=1
        end
        local blocked=instance("NewMap"); blocked.failDestroy=true
        blocked.Parent=f.multiplayer
        assert(warnings==1 and not f.map.recording and not f.map.recordingScope)
        blocked.Name="Map"
        local nextRound=instance("NewMap"); nextRound.Parent=f.multiplayer
        assert(warnings==1 and not nextRound.destroyed)
    end)
end)
test("recording follows replacement Multiplayer containers without touching old ones",function()
    integration(function(f)
        f:sandbox(); f.map:CommitSandbox(); f.map:SetRecording(true)
        f.multiplayer.Parent=nil
        local detached=instance("Map"); detached.Parent=f.multiplayer
        assert(not detached.destroyed)
        local replacement=instance("Multiplayer","Folder")
        local newRound=instance("NewMap"); newRound.Parent=replacement
        replacement.Parent=f.world
        assert(newRound.destroyed)
        local nextRound=instance("Map"); nextRound.Parent=replacement
        assert(nextRound.destroyed)
        f.map.clone:Destroy()
        local withoutSandbox=instance("Map"); withoutSandbox.Parent=replacement
        assert(not withoutSandbox.destroyed)
    end)
end)
print("Map tests passed: "..count)
