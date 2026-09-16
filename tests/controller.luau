-- Service doubles exercise the real App controller; this is not an FE2 simulation.
local factory=require("../src/App")
local modules={}
local config={MaxNodes=10000,MaxFileBytes=1000000,File="test"}
local function import(name) return assert(modules[name],name) end
modules["core/Tree"]=require("../src/core/Tree")(import,config)
modules["core/Quaternion"]=require("../src/core/Quaternion")(import,config)
modules["core/Sampling"]=require("../src/core/Sampling")(import,config)
modules["core/Scope"]=require("../src/core/Scope")(import,config)
local function signal()
    local s={callbacks={}}
    function s:Connect(fn)
        self.callbacks[fn]=true
        return {Disconnect=function() self.callbacks[fn]=nil end,Destroy=function() self.callbacks[fn]=nil end}
    end
    function s:Fire(...)
        for fn in pairs(self.callbacks) do fn(...) end
    end
    return s
end
local services={
    RunService={PostSimulation=signal(),PreSimulation=signal(),RenderStepped=signal(),Heartbeat=signal()},
    UserInputService={InputBegan=signal(),GetFocusedTextBox=function() return nil end},
    Players={LocalPlayer={Name="Tester",Character={}},CharacterAdded=signal()},
}
services.Players.LocalPlayer.CharacterAdded=services.Players.CharacterAdded
local keys=setmetatable({FromName=function(_,name)
    if name=="NotAKey" then return nil end
    return name
end},{__index=function(_,name) return name end})
local shared={}
local warnings={}
local environment=setmetatable({
    game={GetService=function(_,name) return services[name] end},
    Enum={KeyCode=keys},getgenv=function() return shared end,
    warn=function(message) table.insert(warnings,message) end,
    print=function() end,
    task={spawn=function(fn) fn() end},
},{__index=getfenv()})
for _,name in ipairs({"getconnections","getsenv","getupvalue","setupvalue","hookmetamethod","newcclosure",
    "readfile","writefile","isfile","isfolder","makefolder","listfiles","delfile"}) do environment[name]=function() end end
setfenv(factory,environment)
local function frame(t)
    return {time=t,root={t,0,0,0,0,0,1},camera={t,1,0,0,0,0,1},velocity={1,0,0},angular={0,0,0},
        geometry={2,2,1,2,2,1,0},humanoid={8,20,50,7.2,1,0,100},flags={0,0,0},tracks={}}
end
modules["runtime/Character"]={new=function(model)
    return {model=model,Valid=function() return true end,Capture=function(_,t) return frame(t) end,
        Release=function(self) self.released=true end,Resume=function(self,f) self.resumed=f end,
        Apply=function(self,f) self.applied=f end,Camera=function() end,
        ReleaseCamera=function(self) self.cameraReleased=true end,Destroy=function() end}
end}
modules["runtime/Map"]={new=function()
    return {origin={},live={Parent=true},name="Test",spawnName="Spawn",generation=0,
        Acquire=function(self) return self,services.Players.LocalPlayer.Character end,
        Destroy=function(self) self.destroyed=true end,RestoreRopes=function() end,
        AutoCandidate=function() return nil end,ReadyReason=function() return nil end,
        SetRecording=function(self,active) self.recording=active end}
end}
modules["runtime/Storage"]={save=function() return "test",100 end,list=function() return {} end}
local App=factory(import,config)
local function fresh()
    local app=App.new()
    app:Prepare()
    return app
end
local count=0
local function test(name,fn)
    table.clear(warnings)
    config.Keybinds=nil
    config.AutoPrepare=nil
    fn(); count+=1; print("PASS "..name)
end
local function record(app,n)
    app:Record()
    for _=1,n do services.RunService.PostSimulation:Fire(0.1) end
    app:Pause()
end
test("recording uses completed simulation deltas",function()
    local app=fresh(); record(app,3)
    assert(#app.tree.nodes==4 and math.abs(app.time-0.3)<1e-10)
    assert(app.mode=="paused" and app.character.applied==app.tree.nodes[4].frame)
    app:Destroy()
end)
test("restore and continue creates a branch",function()
    local app=fresh(); record(app,2); app:Mark("quick")
    record(app,2); local oldTip=app.tree.cursor
    app:Restore("quick"); record(app,1)
    assert(#app.tree:Branches()==2 and app.tree.nodes[oldTip])
    assert(app.tree.nodes[app.tree.cursor].parent==3)
    app:Destroy()
end)
test("single frame advance records exactly once",function()
    local app=fresh(); record(app,1)
    app:Step()
    services.RunService.PreSimulation:Fire(0.1)
    services.RunService.PostSimulation:Fire(0.1)
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="paused" and #app.tree.nodes==3)
    app:Destroy()
end)
test("exact playback visits every stored frame then holds",function()
    local app=fresh(); record(app,3)
    app:Play(nil,"frames")
    for i=1,4 do
        services.RunService.PreSimulation:Fire(0.017)
        assert(app.tree.cursor==i and app.character.applied==app.tree.nodes[i].frame)
    end
    assert(app.mode=="paused")
    app:Play()
    services.RunService.PreSimulation:Fire(0.017)
    assert(app.tree.cursor==1,"Playback must restart after reaching end")
    app:Destroy()
end)
test("time playback interpolates and clamps end",function()
    local app=fresh(); record(app,3)
    app:Play(nil,"time")
    services.RunService.PreSimulation:Fire(0.15)
    assert(math.abs(app.current.root[1]-0.15)<1e-10)
    services.RunService.PreSimulation:Fire(10)
    assert(app.mode=="paused" and app.tree.cursor==4)
    app:Destroy()
end)
test("zero delta adds no frame",function()
    local app=fresh(); app:Record()
    services.RunService.PostSimulation:Fire(0)
    assert(#app.tree.nodes==1)
    app:Destroy()
end)
test("new run can replace a previous map run",function()
    local app=fresh(); record(app,2)
    app.map.name="Other"
    app:NewRun()
    assert(app.tree.metadata.map=="Other" and #app.tree.nodes==1)
    app:Destroy()
end)
test("unload disconnects frame callbacks",function()
    local app=fresh(); record(app,1); app:Record(); app:Destroy()
    services.RunService.PostSimulation:Fire(1)
    assert(#app.tree.nodes==2)
    assert(next(services.RunService.PostSimulation.callbacks)==nil)
end)
test("runtime failure releases control and stops",function()
    local app=fresh(); app:Record()
    app.character.Capture=function() error("simulated character loss") end
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="idle" and app.character.released and #warnings==1)
    app:Destroy()
end)
test("stop hotkey cancels a busy operation",function()
    local app=fresh(); app.busy=true
    services.UserInputService.InputBegan:Fire({KeyCode="F9"},false)
    assert(app.map.generation==1 and app.mode=="idle")
    app:Destroy()
end)
test("backslash before recording is harmless",function()
    local app=App.new()
    services.UserInputService.InputBegan:Fire({KeyCode="BackSlash"},false)
    assert(#warnings==0 and app.mode=="idle" and not app.tree and not app.busy)
    app:Destroy()
end)
test("backslash with empty or single branch preserves state",function()
    local app=fresh()
    app.tree=modules["core/Tree"].new({})
    services.UserInputService.InputBegan:Fire({KeyCode="BackSlash"},false)
    assert(#warnings==0 and app.tree.cursor==0 and not app.path)
    app.tree=nil
    app:Record()
    services.RunService.PostSimulation:Fire(0.1)
    local cursor=app.tree.cursor
    services.UserInputService.InputBegan:Fire({KeyCode="BackSlash"},false)
    assert(#warnings==0 and app.mode=="recording" and app.tree.cursor==cursor and not app.path)
    app:Destroy()
end)
test("branch cycling wraps and selected branch can play before first playback",function()
    local app=fresh(); record(app,2)
    local first=app.tree.cursor
    app:Seek(2); record(app,2)
    local second=app.tree.cursor
    for _,expected in ipairs({first,second,first}) do
        services.UserInputService.InputBegan:Fire({KeyCode="BackSlash"},false)
        assert(#warnings==0 and app.tree.cursor==expected and app.mode=="paused")
        assert(app.path[#app.path]==expected)
    end
    services.UserInputService.InputBegan:Fire({KeyCode="F3"},false)
    assert(#warnings==0 and app.mode=="playing" and app.time==0)
    services.RunService.PreSimulation:Fire(1)
    assert(app.tree.cursor==first and app.mode=="paused")
    app:Destroy()
end)
test("unavailable hotkeys do not enter the runtime failure handler",function()
    local app=App.new()
    for _,key in ipairs({"F2","F3","F4","F5","F6","F10","LeftBracket","RightBracket"}) do
        services.UserInputService.InputBegan:Fire({KeyCode=key},false)
        assert(app.mode=="idle" and not app.tree and not app.busy)
    end
    assert(#warnings==0)
    app:Destroy()
end)
test("missing mark hotkey preserves active recording",function()
    local app=fresh(); app:Record()
    services.UserInputService.InputBegan:Fire({KeyCode="F5"},false)
    assert(app.mode=="recording" and #warnings==0)
    services.RunService.PostSimulation:Fire(0.1)
    assert(#app.tree.nodes==2)
    app:Destroy()
end)
test("failed file commands preserve active recording",function()
    local app=fresh(); app:Record()
    local originalSave=modules["runtime/Storage"].save
    modules["runtime/Storage"].save=function() error("disk full") end
    modules["runtime/Storage"].load=function() error("corrupt file") end
    for _,key in ipairs({"F6","F7"}) do
        services.UserInputService.InputBegan:Fire({KeyCode=key},false)
        assert(app.mode=="recording" and not app.busy)
    end
    assert(#warnings==2)
    services.RunService.PostSimulation:Fire(0.1)
    assert(#app.tree.nodes==2)
    modules["runtime/Storage"].save=originalSave
    modules["runtime/Storage"].load=nil
    app:Destroy()
end)
test("seek outside selected branch updates its path",function()
    local app=fresh(); record(app,2)
    local original=app.tree.cursor
    app:Seek(2); record(app,3)
    local second=app.tree.cursor
    app:Seek(second)
    app:Seek(original)
    assert(app.path[#app.path]==original)
    app:Play()
    services.RunService.PreSimulation:Fire(10)
    assert(app.tree.cursor==original and app.mode=="paused")
    app:Destroy()
end)
test("custom and disabled hotkeys are respected",function()
    config.Keybinds={Record="R",Save=false}
    local app=fresh()
    services.UserInputService.InputBegan:Fire({KeyCode="F2"},false)
    assert(app.mode=="idle")
    services.UserInputService.InputBegan:Fire({KeyCode="R"},false)
    assert(app.mode=="recording")
    assert(app.keys.F6==nil and app.keys.R=="Record")
    app:Destroy()
end)
test("duplicate and invalid bindings fail before connections are registered",function()
    for _,overrides in ipairs({{Record="F1"},{Record="NotAKey"},{Unknown="R"},{Record=17}}) do
        config.Keybinds=overrides
        assert(not pcall(App.new))
        assert(next(services.RunService.PreSimulation.callbacks)==nil)
        assert(next(services.UserInputService.InputBegan.callbacks)==nil)
    end
end)
test("camera toggles restore takeover immediately",function()
    local app=fresh(); record(app,2)
    app:SetCamera(false)
    assert(not app.camera and app.character.cameraReleased)
    app.character.cameraReleased=false
    app.camera=false
    services.RunService.RenderStepped:Fire()
    assert(app.character.cameraReleased)
    app:Destroy()
end)
test("removed map stops recording before another frame is captured",function()
    local app=fresh(); app:Record()
    app.map.live.Parent=nil
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="idle" and #app.tree.nodes==1 and #warnings==1)
    app:Destroy()
end)
test("explicit cancellation does not log a fatal command error",function()
    local app=fresh()
    app:Command(function() app:Cancel(); error("operation cancelled") end)
    assert(#warnings==0 and app.mode=="idle" and not app.busy)
    app:Destroy()
end)
test("frame advance waits for a fresh physics boundary",function()
    local app=fresh(); record(app,1)
    app:Step()
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="stepPending" and #app.tree.nodes==2)
    services.RunService.PreSimulation:Fire(0.1)
    assert(app.mode=="stepping")
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="paused" and #app.tree.nodes==3)
    app:Destroy()
end)
test("pending frame advance can be cancelled without adding a frame",function()
    local app=fresh(); record(app,1)
    app:Step(); app:Cancel()
    services.RunService.PreSimulation:Fire(0.1)
    services.RunService.PostSimulation:Fire(0.1)
    assert(app.mode=="idle" and #app.tree.nodes==2)
    app:Destroy()
end)
test("GUI branch selection validates tips and preserves the selected path",function()
    local app=fresh(); record(app,2)
    local first=app.tree.cursor
    app:Seek(2); record(app,2)
    app:SelectBranch(first)
    assert(app.mode=="paused" and app.tree.cursor==first and app.path[#app.path]==first)
    assert(not pcall(function() app:SelectBranch(2) end))
    assert(app.tree.cursor==first)
    app:Destroy()
end)
test("GUI notices and run names use the shared application state",function()
    local app=fresh()
    local original=config.File
    app:SetFile("gui_run")
    assert(config.File=="gui_run")
    assert(not pcall(function() app:SetFile("../bad") end) and config.File=="gui_run")
    app:Notify("Saved successfully","info")
    assert(app.lastNotice.text=="Saved successfully" and app.lastNotice.level=="info")
    config.File=original
    app:Destroy()
end)
test("failed constructor disconnects partially installed engine callbacks",function()
    local connect=services.RunService.RenderStepped.Connect
    local newMap=modules["runtime/Map"].new
    local map
    modules["runtime/Map"].new=function() map=newMap(); return map end
    services.RunService.RenderStepped.Connect=function() error("signal unavailable") end
    local ok=pcall(App.new)
    services.RunService.RenderStepped.Connect=connect
    modules["runtime/Map"].new=newMap
    assert(not ok and map.destroyed)
    assert(next(services.RunService.PreSimulation.callbacks)==nil)
    assert(next(services.RunService.PostSimulation.callbacks)==nil)
end)

test("failed first capture preserves an existing run and allows retry",function()
    local app=fresh(); record(app,2); app:Stop()
    local original,capture=app.tree,app.character.Capture
    app.character.Capture=function() error("character not ready") end
    assert(not pcall(function() app:NewRun() end))
    assert(app.tree==original and #app.tree.nodes==3)
    app.tree=nil
    assert(not pcall(function() app:Record() end) and app.tree==nil)
    app.character.Capture=capture
    app:Record()
    assert(app.mode=="recording" and #app.tree.nodes==1)
    app:Destroy()
end)

test("new run from a held frame keeps original movement and animation state",function()
    local app=fresh(); record(app,2)
    local source=app.current
    source.tracks={{id="example",time=0.2,speed=1,weight=1,priority=2,looped=0}}
    app.character.Capture=function() error("must not capture puppet-modified properties") end
    app:NewRun()
    local first=app.tree.nodes[1].frame
    assert(first~=source and first.time==0 and source.time>0)
    assert(first.humanoid[5]==1 and first.tracks[1].speed==1)
    app:Record()
    assert(app.character.resumed==first)
    app:Destroy()
end)

test("playback and immediate pause agree with the first visible frame",function()
    for _,mode in ipairs({"time","frames"}) do
        local app=fresh(); record(app,2)
        app:Play(nil,mode)
        assert(app.tree.cursor==1 and app.time==0 and app.character.applied==app.tree.nodes[1].frame)
        app:Pause()
        assert(app.tree.cursor==1 and app.current==app.tree.nodes[1].frame and app.time==0)
        app:Destroy()
    end
end)

test("FE2 movement lock prevents recording but our puppet anchor can resume",function()
    local app=fresh()
    app.character.root={Anchored=true}
    assert(not app:Dispatch("Record") and not app.tree and #warnings==0)
    app.character.root.Anchored=false
    record(app,1)
    app.character.root.Anchored=true; app.character.saved={anchored=false}
    assert(app:Dispatch("Record") and app.mode=="recording")
    app:Destroy()
end)

test("failed capture leaves the clock at the last saved frame",function()
    local app=fresh(); app:Record()
    services.RunService.PostSimulation:Fire(0.1)
    app.character.Capture=function() error("lost character") end
    services.RunService.PostSimulation:Fire(0.5)
    assert(app.mode=="idle" and app.time==0.1 and #app.tree.nodes==2)
    assert(not app.current and not app.path and not app.map.recording)
    app:Destroy()
end)

local function automatic()
    local app=App.new()
    app.map.live=nil; app.map.origin=nil
    local candidate={map={Parent=true},character=services.Players.LocalPlayer.Character,ready=false,attempts=0}
    app.map.AutoCandidate=function()
        if candidate.ready then return candidate.map,candidate.character end
        return nil
    end
    app.map.Acquire=function(self)
        candidate.attempts+=1
        self.live=candidate.map; self.origin={}
        return self,candidate.character
    end
    return app,candidate
end

test("automatic preparation waits for entry and starts only after loader handoff",function()
    local app,candidate=automatic()
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==0)
    candidate.ready=true
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==0)
    app:StartAutoPrepare()
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==1 and app.character.model==candidate.character and not app.busy)
    services.RunService.Heartbeat:Fire(1)
    assert(candidate.attempts==1)
    app:Destroy()
    assert(next(services.RunService.Heartbeat.callbacks)==nil)
end)

test("automatic preparation follows another round without deleting the old run",function()
    local app,candidate=automatic(); candidate.ready=true; app:StartAutoPrepare()
    services.RunService.Heartbeat:Fire(0.3)
    record(app,2); app:Stop()
    local tree=app.tree
    candidate.map={Parent=true}
    app.map.name="Next round"
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==2 and app.map.live==candidate.map and app.tree==tree)
    assert(app:ActionReason("Record"),"A different map must not silently replace the run")
    app:Destroy()
end)

test("automatic preparation is idle-only and can be disabled",function()
    local app,candidate=automatic(); candidate.ready=true; app:StartAutoPrepare()
    config.AutoPrepare=false
    services.RunService.Heartbeat:Fire(1)
    assert(candidate.attempts==0)
    config.AutoPrepare=true
    app.busy=true; services.RunService.Heartbeat:Fire(1); app.busy=false
    assert(candidate.attempts==0)
    services.RunService.Heartbeat:Fire(0.3)
    record(app,1)
    candidate.map={Parent=true}
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==1 and app.mode=="paused")
    app:Destroy()
end)

test("stopping queued automatic preparation suppresses restart until a new round",function()
    local app,candidate=automatic(); candidate.ready=true; app:StartAutoPrepare()
    local spawn=environment.task.spawn
    local pending
    environment.task.spawn=function(fn) pending=fn end
    services.RunService.Heartbeat:Fire(0.3)
    assert(app.busy and pending)
    app:Cancel()
    pending()
    environment.task.spawn=spawn
    services.RunService.Heartbeat:Fire(1)
    assert(candidate.attempts==0 and not app.busy and #warnings==0)
    candidate.map={Parent=true}
    services.RunService.Heartbeat:Fire(0.3)
    assert(candidate.attempts==1)
    app:Destroy()
end)

test("automatic preparation retries failures with a delay and no warning spam",function()
    local app,candidate=automatic(); candidate.ready=true; app:StartAutoPrepare()
    local acquire=app.map.Acquire
    local attempts=0
    app.map.Acquire=function(self)
        attempts+=1
        if attempts<3 then error("spawn still moving") end
        return acquire(self)
    end
    services.RunService.Heartbeat:Fire(0.3)
    services.RunService.Heartbeat:Fire(1)
    assert(attempts==1 and #warnings==1)
    services.RunService.Heartbeat:Fire(5)
    assert(attempts==2 and #warnings==1)
    services.RunService.Heartbeat:Fire(5)
    assert(attempts==3 and app.character and not app.busy)
    app:Destroy()
end)

test("sandbox source is committed only after respawn and character attachment",function()
    local app=fresh()
    local events={}
    app.map.Clone=function(self) self.clone={Parent=true}; table.insert(events,"clone") end
    app.map.Respawn=function() table.insert(events,"respawn"); return services.Players.LocalPlayer.Character end
    local attach=app.Attach
    app.Attach=function(self,character) attach(self,character); table.insert(events,"attach") end
    app.map.CommitSandbox=function() table.insert(events,"commit") end
    app:PrepareClone()
    assert(table.concat(events,",")=="clone,respawn,attach,commit")
    assert(not pcall(function() app:PrepareClone() end) and not app.map.destroyed)
    app:Destroy()
end)

test("failed sandbox respawn never commits source deletion",function()
    local app=fresh()
    local previous=app.map
    previous.Clone=function(self) self.clone={Parent=true} end
    previous.Respawn=function() error("respawn failed") end
    previous.CommitSandbox=function() error("source must not be deleted") end
    assert(not pcall(function() app:PrepareClone() end))
    assert(previous.destroyed and app.map~=previous and not app.character)
    app:Destroy()
end)

test("incoming-map removal follows recording pause step playback and stop",function()
    local app=fresh()
    record(app,1)
    assert(not app.map.recording)
    app:Record(); assert(app.map.recording)
    app:Pause(); assert(not app.map.recording)
    app:Step(); assert(not app.map.recording)
    services.RunService.PreSimulation:Fire(0.1)
    assert(app.map.recording)
    services.RunService.PostSimulation:Fire(0.1)
    assert(not app.map.recording)
    app:Record(); app:Play()
    assert(not app.map.recording)
    app:Pause(); app:Record(); app:Stop()
    assert(not app.map.recording)
    app:Destroy()
end)
print("Controller tests passed: "..count)
