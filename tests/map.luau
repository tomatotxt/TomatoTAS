-- Tests reversible clone preparation with mock Instances/signals, not Roblox cloning.
local factory=require("../src/runtime/Map")
local Scope=require("../src/core/Scope")(function() end,{})
local elapsed,yields=0,0
local heartbeat={Wait=function() elapsed+=0.1; yields+=1 end}
local remote
local storage={FindFirstChild=function(_,name) return if name=="Remote" then remote else nil end}
local root={CFrame={}}
local player={Character={HumanoidRootPart=root,FindFirstChild=function(_,name) return if name=="HumanoidRootPart" then root else nil end}}
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
print("Map tests passed: "..count)
