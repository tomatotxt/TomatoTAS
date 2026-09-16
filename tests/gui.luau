-- Native widget/service doubles verify GUI wiring and lifetime, not Roblox rendering.
local factory=require("../src/ui/Panel")
local Model=require("../src/ui/Model")(function() end,{})
local Scope=require("../src/core/Scope")(function() end,{})
local function signal()
    local s={callbacks={}}
    function s:Connect(fn)
        self.callbacks[fn]=true
        return {Disconnect=function() self.callbacks[fn]=nil end,Destroy=function() self.callbacks[fn]=nil end}
    end
    function s:Fire(...) for fn in pairs(self.callbacks) do fn(...) end end
    return s
end
local function u(s,o) return {Scale=s,Offset=o} end
local function ud(xs,xo,ys,yo) return {X=u(xs,xo),Y=u(ys,yo)} end
local function vector(x,y) return {X=x,Y=y} end
local function color(r,g,b)
    return {R=r,G=g,B=b,Lerp=function(self,other,t) return color(self.R+(other.R-self.R)*t,self.G+(other.G-self.G)*t,self.B+(other.B-self.B)*t) end}
end
local all={}
local function instance(class)
    local state={ClassName=class,children={},signals={},Size=ud(0,0,0,0),Position=ud(0,0,0,0),Visible=true}
    local object
    local function dimensions()
        if class=="ScreenGui" then return state.viewport or vector(1024,768) end
        local p=state.Parent and state.Parent.AbsoluteSize or vector(1024,768)
        return vector(p.X*state.Size.X.Scale+state.Size.X.Offset,p.Y*state.Size.Y.Scale+state.Size.Y.Offset)
    end
    object=setmetatable({},{__index=function(_,key)
        if state[key]~=nil then return state[key] end
        if key=="AbsoluteSize" then return dimensions() end
        if key=="AbsolutePosition" then return vector(state.Position.X.Offset,state.Position.Y.Offset) end
        if key=="GetChildren" then return function() return table.clone(state.children) end end
        if key=="GetPropertyChangedSignal" then return function(_,property)
            state.signals[property]=state.signals[property] or signal(); return state.signals[property]
        end end
        if key=="Destroy" then return function()
            for _,child in ipairs(table.clone(state.children)) do child:Destroy() end
            object.Parent=nil; state.destroyed=true
        end end
        if key=="Activated" or key=="MouseEnter" or key=="MouseLeave" or key=="InputBegan" then
            state[key]=signal(); return state[key]
        end
        return nil
    end,__newindex=function(_,key,value)
        if key=="Parent" then
            if state.Parent then
                local i=table.find(state.Parent.children,object)
                if i then table.remove(state.Parent.children,i) end
            end
            if value then table.insert(value.children,object) end
        end
        state[key]=value
    end})
    table.insert(all,object)
    return object
end
local enums=setmetatable({},{__index=function(t,key)
    local values=setmetatable({},{__index=function(_,name) return key.."."..name end})
    rawset(t,key,values); return values
end})
local ui={InputChanged=signal(),InputEnded=signal()}
local rs={Heartbeat=signal()}
local playerGui=instance("PlayerGui")
local services={UserInputService=ui,RunService=rs,Players={LocalPlayer={WaitForChild=function() return playerGui end}},
    TweenService={Create=function(_,object,_,props) return {Cancel=function() end,Play=function() for k,v in pairs(props) do object[k]=v end end} end}}
local queuedCallbacks
local env=setmetatable({
    game={GetService=function(_,name) return assert(services[name],name) end},Instance={new=instance},Enum=enums,
    Color3={fromRGB=color},UDim={new=u},UDim2={new=ud,fromOffset=function(x,y) return ud(0,x,0,y) end,fromScale=function(x,y) return ud(x,0,y,0) end},
    Vector2={zero=vector(0,0)},TweenInfo={new=function() return {} end},task={spawn=function(fn)
        if queuedCallbacks then table.insert(queuedCallbacks,fn) else fn() end
    end},warn=function() end,
},{__index=getfenv()})
setfenv(factory,env)
local Panel=factory(function(name) return if name=="core/Scope" then Scope else Model end,{File="run"})
local function app()
    local a={map={},mode="idle",time=0,speed=1,camera=true,playbackMode="time",scope={},events={}}
    function a:Notify(text,level) self.lastNotice={text=text,level=level} end
    function a:Dispatch(action) table.insert(self.events,action); return true end
    function a:ActionReason(action) if action=="Record" and not self.ready then return "Prepare first" end; return nil end
    function a:ReadyReason() return if self.ready then nil else "Prepare first" end
    function a:Command(fn) self.busy=true; fn(); self.busy=false end
    function a:SetSpeed(value) self.speed=value end
    function a:SetCamera(value) self.camera=value end
    function a:SetFile(name) assert(name:match("^[%w_%-]+$"),"bad filename"); self.file=name end
    function a:FileCommand(method,name,source) table.insert(self.events,method..":"..name..":"..tostring(source)); return true end
    function a:ListFiles() return {"TomatoTAS/alpha.fe2tomatas","C:\\sandbox\\beta.fe2tomatas","ignore.pending"} end
    function a:Seek(id) self.tree.cursor=id; self.time=self.tree.nodes[id].frame.time; self.mode="paused" end
    function a:SelectBranch(id) self.selected=id end
    function a:NewRun() self.newRuns=(self.newRuns or 0)+1; self.tree=nil end
    return a
end
local function tree()
    return {cursor=3,nodes={{frame={time=0}},{frame={time=0.1}},{frame={time=2}}},marks={},
        Branches=function() return {3} end,Path=function() return {1,2,3} end}
end
local count=0
local function test(name,fn) fn(); count+=1; print("PASS "..name) end
test("clock formats milliseconds and carries minute boundaries",function()
    assert(Model.clock(59.9996)=="01:00.000" and Model.clock(-1)=="00:00.000")
    assert(Model.clock(0/0)=="00:00.000" and Model.clock(3600)=="60:00.000")
end)
test("file names normalize Windows paths without admitting traversal",function()
    assert(Model.fileName("C:\\runs\\practice.fe2tomatas")=="practice")
    assert(Model.fileName("a/../escape.fe2tomatas")=="escape") -- only a safe basename is used by Storage
    assert(not Model.fileName("bad.name.fe2tomatas") and not Model.fileName("run.fe2tomatas.bak"))
end)
test("timeline seeking respects recorded time rather than array spacing",function()
    local t=tree()
    assert(Model.frameAt(t,{1,2,3},0.5)==2)
    assert(Model.frameAt(t,{1,2,3},1)==3 and Model.frameAt(t,{1,2,3},-1)==1)
    assert(not Model.frameAt(t,{},0.5))
end)
test("GUI mounts a separate responsive screen and cleans up",function()
    local a=app(); local panel=Panel.new(a)
    assert(panel.screen.Parent==playerGui and panel.screen.ResetOnSpawn==false)
    assert(panel.pages.Studio.Visible and not panel.pages.Files.Visible)
    assert(panel.window.Size.X.Offset==680 and panel.window.Size.Y.Offset==620)
    assert(panel.mapLabel.Text=="Waiting for map…" and panel.notice.Text:find("automatically",1,true))
    panel.screen.viewport=vector(360,480); panel:Fit()
    assert(panel.scale.Scale<1 and panel.x>=8 and panel.y>=8)
    panel:Destroy()
    assert(panel.screen.destroyed and next(rs.Heartbeat.callbacks)==nil)
    assert(next(ui.InputChanged.callbacks)==nil and next(ui.InputEnded.callbacks)==nil)
end)
test("disabled actions do not dispatch and become enabled when ready",function()
    local a=app(); local panel=Panel.new(a)
    panel.actionButtons.Record.object.Activated:Fire()
    assert(#a.events==0)
    a.ready=true; panel:Update()
    panel.actionButtons.Record.object.Activated:Fire()
    assert(a.events[1]=="Record")
    a.busy=true; panel:Update()
    assert(not panel.actionButtons.Record.enabled and panel.actionButtons.Stop.enabled)
    panel:Destroy()
end)
test("minimize retains controls and restores through launcher",function()
    local panel=Panel.new(app())
    panel:Toggle(false)
    assert(not panel.window.Visible and panel.launcher.object.Visible)
    panel.launcher.object.Activated:Fire()
    assert(panel.window.Visible and not panel.launcher.object.Visible)
    panel:Destroy()
end)
test("file tab routes selected names through the file API",function()
    local a=app(); local panel=Panel.new(a); panel:Tab("Files")
    local first=panel.fileList:GetChildren()[1]
    first.Activated:Fire()
    assert(panel.fileBox.Text=="alpha")
    panel:File("Load","backup")
    assert(a.file=="alpha" and a.events[1]=="Load:alpha:backup")
    panel.fileBox.Text="../bad"; panel:File("Save")
    assert(#a.events==1 and a.lastNotice.level=="error")
    panel:Destroy()
end)
test("timeline cannot seek an active recording",function()
    local a=app(); a.ready=true; a.tree=tree(); a.mode="recording"
    local panel=Panel.new(a)
    panel:Scrub(300)
    assert(a.tree.cursor==3 and a.mode=="recording" and a.lastNotice)
    a.mode="paused"; panel:Scrub(24+632*0.5)
    assert(a.tree.cursor==2)
    panel:Destroy()
end)
test("timeline cannot interrupt a pending physics step",function()
    local a=app(); a.ready=true; a.tree=tree(); a.mode="stepPending"
    local panel=Panel.new(a)
    panel:Scrub(24+632*0.5)
    assert(a.tree.cursor==3 and a.mode=="stepPending" and a.lastNotice)
    panel:Destroy()
end)

test("new run confirmation belongs to the run being replaced",function()
    local a=app(); a.ready=true; a.tree=tree()
    local panel=Panel.new(a)
    panel:NewRun()
    assert(not a.newRuns and a.lastNotice.level=="warning")
    a.tree=tree() -- a file load can replace the tree before the second click
    panel:NewRun()
    assert(not a.newRuns and a.lastNotice.level=="warning")
    panel:NewRun()
    assert(a.newRuns==1)
    panel:Destroy()
end)

test("new run cannot be confirmed while another operation is running",function()
    local a=app(); a.ready=true; a.tree=tree(); a.busy=true
    local panel=Panel.new(a)
    panel:NewRun()
    a.busy=false; panel:NewRun()
    assert(not a.newRuns and a.lastNotice.level=="warning")
    panel:NewRun()
    assert(a.newRuns==1)
    panel:Destroy()
end)

test("queued row clicks are discarded after refreshing their list",function()
    local a=app(); local panel=Panel.new(a); panel:Tab("Files")
    queuedCallbacks={}
    panel.fileList:GetChildren()[1].Activated:Fire()
    assert(#queuedCallbacks==1)
    panel:Files()
    local callback=queuedCallbacks[1]; queuedCallbacks=nil
    callback()
    assert(panel.fileBox.Text=="run")
    panel:Destroy()
end)

test("queued actions do not run after becoming disabled",function()
    local a=app(); a.ready=true
    local panel=Panel.new(a)
    queuedCallbacks={}
    panel.actionButtons.Record.object.Activated:Fire()
    assert(#queuedCallbacks==1)
    a.ready=false; panel:Update()
    local callback=queuedCallbacks[1]; queuedCallbacks=nil
    callback()
    assert(#a.events==0)
    panel:Destroy()
end)
test("branch rows route selection to the engine",function()
    local a=app(); a.ready=true; a.tree=tree()
    local panel=Panel.new(a); panel:Tab("Branches")
    panel.branchList:GetChildren()[1].Activated:Fire()
    assert(a.selected==3)
    panel:Destroy()
end)
test("presentation failure destroys GUI without dispatching engine stop",function()
    local a=app(); local panel=Panel.new(a)
    a.ActionReason=function() error("presentation test failure") end
    rs.Heartbeat:Fire(0.2)
    assert(panel.scope.dead and #a.events==0 and not a.scope.dead)
end)
print("GUI tests passed: "..count)
