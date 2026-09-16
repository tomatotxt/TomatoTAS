-- Focused Roblox service doubles: these tests verify ownership and cleanup, not engine physics.
local factory=require("../src/runtime/Character")
local Q=require("../src/core/Quaternion")(function() end,{})
local Scope=require("../src/core/Scope")(function() end,{})
local vectorMT={}
local function vector(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMT) end
vectorMT.__index=function(v,key)
    local magnitude=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)
    if key=="Magnitude" then return magnitude end
    if key=="Unit" then return vector(v.X/magnitude,v.Y/magnitude,v.Z/magnitude) end
end
vectorMT.__sub=function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local cfMT={}
local function cf(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},cfMT) end
cfMT.__mul=function(a,b) return cf(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
cfMT.__index={
    GetComponents=function(c) return c.X,c.Y,c.Z,1,0,0,0,1,0,0,0,1 end,
    ToObjectSpace=function(a,b) return cf(b.X-a.X,b.Y-a.Y,b.Z-a.Z) end,
    VectorToObjectSpace=function(_,v) return v end,
    VectorToWorldSpace=function(_,v) return v end,
}
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        self.listeners[fn]=true
        return {Disconnect=function() self.listeners[fn]=nil end,Destroy=function() self.listeners[fn]=nil end}
    end
    function s:Fire(...) for fn in pairs(self.listeners) do fn(...) end end
    return s
end
local function instance(class,name)
    local state={ClassName=class,Name=name,children={}}
    local result
    state.IsA=function(_,kind) return kind==class or (kind=="BasePart" and class=="Part") end
    state.FindFirstChild=function(_,child) return state.children[child] end
    state.FindFirstChildOfClass=function(_,kind)
        for _,child in pairs(state.children) do if child:IsA(kind) then return child end end
        return nil
    end
    state.Destroy=function()
        if state.destroyError then error("destroy failed") end
        state.destroyed=true; state.Parent=nil
    end
    result=setmetatable({},{__index=state,__newindex=function(_,key,value)
        if key==state.failProperty then error("property no longer writable: "..key) end
        state[key]=value
    end})
    return result
end
local function add(parent,child) parent.children[child.Name]=child; child.Parent=parent; return child end
local states={}
for i=0,18 do states[i]={Value=i} end
local stateEnum={Dead=states[15],FromValue=function(_,value) return states[value] end}
local warnings,shared,hook={}, {},nil
local players={LocalPlayer={}}
local world={}
local assetsMade=0
local environment=setmetatable({
    game={GetService=function(_,name) assert(name=="Players"); return players end},workspace=world,
    Vector3={new=vector,zero=vector(0,0,0)},CFrame={new=cf},
    Enum={HumanoidStateType=stateEnum,CameraType={Scriptable="Scriptable"},AnimationPriority=stateEnum},
    Instance={new=function(class) assetsMade+=1; return instance(class,class) end},
    getgenv=function() return shared end,newcclosure=function(fn) return fn end,
    hookmetamethod=function(_,_,fn) hook=fn; return function(object,key) return object[key] end end,
    warn=function(message) table.insert(warnings,message) end,
},{__index=getfenv()})
setfenv(factory,environment)
local Character=factory(function(name) return if name=="core/Quaternion" then Q else Scope end)
local function track(id)
    local t={Animation={AnimationId=id},TimePosition=0.25,Speed=1,WeightCurrent=0.7,Priority=states[2],Looped=true,IsPlaying=true}
    function t:Play() self.IsPlaying=true end
    function t:Stop() if self.stopError then error("track vanished") end; self.IsPlaying=false end
    function t:Destroy() self.destroyed=true; self.IsPlaying=false end
    function t:AdjustSpeed(value) self.Speed=value end
    function t:AdjustWeight(value) self.WeightCurrent=value end
    return t
end
local function setup(withHitbox)
    local model=instance("Model","Character"); model.Parent=true
    local root=add(model,instance("Part","HumanoidRootPart"))
    root.CFrame=cf(10,2,0); root.Size=vector(2,2,1); root.Anchored=false
    root.AssemblyLinearVelocity=vector(2,0,0); root.AssemblyAngularVelocity=vector(0,0,0)
    local hum=add(model,instance("Humanoid","Humanoid"))
    hum.Health=100; hum.HipHeight=0; hum.WalkSpeed=20; hum.JumpPower=50; hum.JumpHeight=7.2
    hum.AutoRotate=true; hum.PlatformStand=false; hum.state=states[8]
    hum.GetState=function() return hum.state end
    hum.ChangeState=function(_,value) hum.state=value end
    local animator=add(hum,instance("Animator","Animator"))
    animator.playing={}; animator.loads=0
    animator.GetPlayingAnimationTracks=function()
        local result={}
        for _,t in ipairs(animator.playing) do if t.IsPlaying then table.insert(result,t) end end
        return result
    end
    animator.LoadAnimation=function(_,animation)
        animator.loads+=1
        if animation.AnimationId=="bad" then error("asset unavailable") end
        local t=track(animation.AnimationId); t.IsPlaying=false
        table.insert(animator.playing,t)
        return t
    end
    local animate
    for _,name in ipairs({"CL_AntiSideClip","CL_AirMomentum","FE2_Character","Animate"}) do
        local s=add(model,instance("LocalScript",name)); s.Disabled=false
        if name=="Animate" then animate=s end
    end
    for _,name in ipairs({"Sliding","Swinging","Walljump"}) do
        local event=add(animate,instance("BindableEvent",name)); event.Event=signal()
        event.Fire=function(_,active) event.Event:Fire(active) end
    end
    if withHitbox~=false then local hit=add(model,instance("Part","FE2_Hitbox")); hit.Size=vector(2,2,1) end
    local particles=add(root,instance("ParticleEmitter","SlideParticles")); particles.Enabled=false
    players.LocalPlayer.Character=model
    local camera=instance("Camera","Camera"); camera.CameraType="Custom"; camera.CameraSubject=hum; camera.CFrame=cf(1,2,3)
    world.CurrentCamera=camera
    return Character.new(model),model,root,hum,animator,camera
end
local count=0
local function test(name,fn)
    warnings,shared,hook={}, {},nil; assetsMade=0
    fn(); count+=1; print("PASS "..name)
end
local function sample(c)
    local f=c:Capture(0,cf())
    f.geometry={2,1,1,2,1,1,-1.5}; f.flags={1,0,0}; f.velocity={3,9,4}
    return f
end
test("capture sorts animations independently of engine enumeration",function()
    local c,_,_,_,animator=setup()
    local a,b=track("a"),track("b")
    animator.playing={b,a}
    local first=c:Capture(0,cf())
    animator.playing={a,b}
    local second=c:Capture(1,cf())
    assert(first.tracks[1].id=="a" and second.tracks[1].id=="a")
    assert(first.root[1]==10 and first.root[7]==1)
    c:Destroy()
end)

test("constructor failure disconnects events connected before initialization failed",function()
    local original,model=setup()
    original:Destroy()
    local events=model.children.Animate.children
    events.Swinging.Event.Connect=function() error("second event connection failed") end
    local ok,err=pcall(function() Character.new(model) end)
    assert(not ok and tostring(err):find("second event connection failed",1,true))
    assert(next(events.Sliding.Event.listeners)==nil,"Failed constructor retained its first event subscription")
    assert(next(events.Walljump.Event.listeners)==nil)
end)
test("puppet release restores geometry scripts particles and camera",function()
    local c,model,root,hum,_,camera=setup()
    local f=sample(c)
    c:Apply(f,cf(),true)
    assert(root.Anchored and root.Size.Y==1 and hum.HipHeight==-1.5 and model.children.Animate.Disabled)
    assert(root.children.SlideParticles.Enabled and camera.CameraType=="Scriptable")
    local direction=hook(hum,"MoveDirection")
    assert(math.abs(direction.X-0.6)<1e-10 and direction.Y==0 and math.abs(direction.Z-0.8)<1e-10)
    c:Release()
    assert(not root.Anchored and root.Size.Y==2 and hum.HipHeight==0 and not model.children.Animate.Disabled)
    assert(not root.children.SlideParticles.Enabled and camera.CameraType=="Custom")
    assert(shared.__TomatoTASMoveHook.humanoid==nil)
    c:Destroy()
end)
test("camera replacement restores both prior and current cameras",function()
    local c,_,_,_,_,original=setup()
    local f=sample(c); c:Camera(f,cf())
    local nextCamera=instance("Camera","Next"); nextCamera.CameraType="Follow"; nextCamera.CFrame=cf()
    world.CurrentCamera=nextCamera
    c:Camera(f,cf())
    assert(original.CameraType=="Custom" and nextCamera.CameraType=="Scriptable")
    c:ReleaseCamera()
    assert(nextCamera.CameraType=="Follow" and not c.cameraSaved)
    c:Destroy()
end)
test("stale root property and broken track do not prevent other cleanup",function()
    local c,model,root,hum,_,camera=setup()
    c:Apply(sample(c),cf(),true)
    local broken=track("x"); broken.stopError=true; c.tracks.x=broken
    root.failProperty="Size"
    c:Release()
    assert(not root.Anchored and hum.HipHeight==0 and not model.children.Animate.Disabled)
    assert(camera.CameraType=="Custom" and broken.destroyed and #warnings==2)
    c:Destroy()
end)
test("animation enumeration reorder reuses existing playback tracks",function()
    local c,_,_,_,animator=setup()
    local a={id="a",time=0,speed=1,weight=1,priority=2,looped=1}
    local b=table.clone(a); b.id="b"
    c:Animations({a,b}); local firstA=c.tracks["a:1"]
    c:Animations({b,a})
    assert(animator.loads==2 and c.tracks["a:1"]==firstA)
    c:Destroy()
end)
test("unavailable animation fails once without blocking valid tracks",function()
    local c,_,_,_,animator=setup()
    local bad={id="bad",time=0,speed=1,weight=1,priority=2,looped=1}
    local good=table.clone(bad); good.id="good"
    c:Animations({bad,good}); c:Animations({bad,good})
    assert(animator.loads==2 and #warnings==1 and c.tracks["good:1"])
    c:Destroy()
end)

test("animation weights above one survive capture and puppet playback",function()
    local c,_,_,_,animator=setup()
    local original=track("weighted"); original.WeightCurrent=5
    animator.playing={original}
    local f=c:Capture(0,cf())
    assert(f.tracks[1].weight==5)
    c:Apply(f,cf(),false)
    assert(c.tracks["weighted:1"].WeightCurrent==5)
    c:Destroy()
end)

test("failed animation occurrences do not retain unusable sibling tracks",function()
    local c,_,_,_,animator=setup()
    local load=animator.LoadAnimation
    animator.LoadAnimation=function(self,animation)
        if self.loads==1 then error("animator track limit") end
        return load(self,animation)
    end
    local a={id="same",time=0,speed=1,weight=1,priority=2,looped=1}
    c:Animations({a,a})
    local previous=c.tracks["same:1"]
    assert(previous and c.failedAnimations.same)
    c:Animations({a,a})
    assert(previous.destroyed and next(c.tracks)==nil)
    c:Destroy()
end)

test("resume restores slide particles with recorded geometry and state",function()
    local c,model,root,hum=setup()
    local f=sample(c)
    f.humanoid[1]=5
    c:Apply(f,cf(),false)
    c:Resume(f,cf())
    assert(not root.Anchored and not model.children.Animate.Disabled)
    assert(root.Size.Y==1 and hum.HipHeight==-1.5 and hum.state==states[5])
    assert(root.children.SlideParticles.Enabled and c.flags[1]==1)
    f.flags[1]=0
    c:Resume(f,cf())
    assert(not root.children.SlideParticles.Enabled)
    c:Destroy()
end)
test("late hitbox and events are tracked and restored",function()
    local c,model=setup(false)
    local f=sample(c); c:Apply(f,cf(),false)
    local hit=add(model,instance("Part","FE2_Hitbox")); hit.Size=vector(3,3,3)
    c:Apply(f,cf(),false)
    assert(hit.Size.Y==1)
    c:Release(); assert(hit.Size.Y==3)
    local old=model.children.Animate.children.Sliding
    local replacement=add(model.children.Animate,instance("BindableEvent","Sliding"))
    replacement.Event=signal(); replacement.Fire=function(_,active) replacement.Event:Fire(active) end
    c:Refresh(); replacement:Fire(true)
    assert(c.flags[1]==1 and next(old.Event.listeners)==nil)
    c:Destroy(); assert(next(replacement.Event.listeners)==nil)
end)
test("takeover ownership cannot release another controller",function()
    local c,model,root=setup()
    c:Apply(sample(c),cf(),false)
    local second=Character.new(model)
    assert(not pcall(function() second:Acquire() end))
    assert(shared.__TomatoTASMoveHook.owner==c and root.Anchored)
    second:Destroy(); c:Destroy()
end)

test("rejected takeover never restores properties owned by another controller",function()
    local c,model,root,hum=setup()
    c:Apply(sample(c),cf(),false)
    local second=Character.new(model)
    local changes=0
    local changeState=hum.ChangeState
    hum.ChangeState=function(self,state) changes+=1; changeState(self,state) end
    root.failProperty="Anchored"
    local ok,err=pcall(function() second:Acquire() end)
    assert(not ok and tostring(err):find("controlled by another TomatoTAS instance",1,true))
    assert(#warnings==0 and changes==0,"Rejected takeover wrote the active controller's properties")
    assert(shared.__TomatoTASMoveHook.owner==c and root.Anchored and not second.saved)
    root.failProperty=nil
    second:Destroy(); c:Destroy()
end)
test("refresh recovers slide flag from actual standing geometry",function()
    local c=setup()
    c.flags[1]=1
    assert(c:Capture(0,cf()).flags[1]==0)
    c:Destroy()
end)
test("replacement mechanic event receives unchanged puppet state",function()
    local c,model=setup()
    local f=sample(c); c:Apply(f,cf(),false)
    local replacement=add(model.children.Animate,instance("BindableEvent","Sliding"))
    replacement.Event=signal()
    local fired=0
    replacement.Fire=function(_,active) assert(active); fired+=1; replacement.Event:Fire(active) end
    c:Apply(f,cf(),false)
    assert(fired==1)
    c:Apply(f,cf(),false)
    assert(fired==1)
    c:Destroy()
end)
print("Character tests passed: "..count)
