return function(import)
    local Q=import("core/Quaternion")
    local Scope=import("core/Scope")
    local Players=game:GetService("Players")
    local Character={}
    Character.__index=Character
    local function vec(v) return {v.X,v.Y,v.Z} end
    local function vector(v) return Vector3.new(v[1],v[2],v[3]) end
    local function pack(cf)
        local x,y,z,a,b,c,d,e,f,g,h,i=cf:GetComponents()
        return {x,y,z,Q.fromMatrix(a,b,c,d,e,f,g,h,i)}
    end
    local function unpackCF(a)
        return CFrame.new(a[1],a[2],a[3],Q.matrix(a[4],a[5],a[6],a[7]))
    end
    Character.pack=pack
    Character.unpack=unpackCF
    function Character.new(model)
        local self=setmetatable({model=model,scope=Scope.new(),flags={0,0,0},tracks={}},Character)
        self.root=assert(model:FindFirstChild("HumanoidRootPart"),"Character root not ready")
        self.hum=assert(model:FindFirstChildOfClass("Humanoid"),"Humanoid not ready")
        self.animator=self.hum:FindFirstChildOfClass("Animator")
        self.hitbox=model:FindFirstChild("FE2_Hitbox",true)
        self.animate=model:FindFirstChild("Animate")
        for i,name in ipairs({"Sliding","Swinging","Walljump"}) do
            local signal=self.animate and self.animate:FindFirstChild(name)
            if signal and signal:IsA("BindableEvent") then
                self.scope:Add(signal.Event:Connect(function(active) self.flags[i]=if active then 1 else 0 end))
            end
        end
        return self
    end
    function Character:Valid()
        return self.model==Players.LocalPlayer.Character and self.root.Parent~=nil and self.hum.Health>0
    end
    function Character:Capture(time,origin)
        assert(self:Valid(),"Character died or changed")
        local tracks={}
        if self.animator then
            for _,track in ipairs(self.animator:GetPlayingAnimationTracks()) do
                if track.Animation then
                    table.insert(tracks,{id=track.Animation.AnimationId,time=track.TimePosition,speed=track.Speed,
                        weight=track.WeightCurrent,priority=track.Priority.Value,looped=if track.Looped then 1 else 0})
                end
            end
        end
        local r,h=self.root,self.hum
        local hit=self.hitbox and self.hitbox.Size or r.Size
        local flags=table.clone(self.flags)
        flags[1]=if h.HipHeight < -1 or r.Size.Y<1.5 then 1 else flags[1]
        local camera=workspace.CurrentCamera
        return {time=time,root=pack(origin:ToObjectSpace(r.CFrame)),
            velocity=vec(origin:VectorToObjectSpace(r.AssemblyLinearVelocity)),
            angular=vec(origin:VectorToObjectSpace(r.AssemblyAngularVelocity)),
            camera=pack(origin:ToObjectSpace(camera and camera.CFrame or r.CFrame)),
            geometry={r.Size.X,r.Size.Y,r.Size.Z,hit.X,hit.Y,hit.Z,h.HipHeight},
            humanoid={h:GetState().Value,h.WalkSpeed,h.JumpPower,h.JumpHeight,if h.AutoRotate then 1 else 0,
                if h.PlatformStand then 1 else 0,h.Health},flags=flags,tracks=tracks}
    end
    function Character:Acquire()
        if self.saved then return end
        assert(self:Valid(),"Character not available")
        local r,h=self.root,self.hum
        self.saved={anchored=r.Anchored,size=r.Size,hitbox=self.hitbox and self.hitbox.Size,
            hip=h.HipHeight,rotate=h.AutoRotate,platform=h.PlatformStand,speed=h.WalkSpeed,
            jump=h.JumpPower,height=h.JumpHeight,state=h:GetState(),scripts={}}
        for _,name in ipairs({"CL_AntiSideClip","CL_AirMomentum","FE2_Character","Animate"}) do
            local scriptObject=self.model:FindFirstChild(name)
            if scriptObject and scriptObject:IsA("LocalScript") then
                self.saved.scripts[scriptObject]=scriptObject.Disabled
                scriptObject.Disabled=true
            end
        end
        if self.animator then
            for _,track in ipairs(self.animator:GetPlayingAnimationTracks()) do track:Stop(0) end
        end
        local env=getgenv()
        if not env.__TomatoTASMoveHook then
            local state={humanoid=nil,direction=Vector3.zero}
            local previous
            previous=hookmetamethod(game,"__index",newcclosure(function(object,key)
                if object==state.humanoid and key=="MoveDirection" then return state.direction end
                return previous(object,key)
            end))
            env.__TomatoTASMoveHook=state
        end
        self.hook=env.__TomatoTASMoveHook
        self.hook.humanoid=h
    end
    function Character:Apply(frame,origin,cameraEnabled)
        assert(self:Valid(),"Character died or changed")
        self:Acquire()
        local r,h=self.root,self.hum
        local g,v=frame.geometry,origin:VectorToWorldSpace(vector(frame.velocity))
        r.Anchored=true -- prevents physics from integrating past the recorded sample
        r.CFrame=origin*unpackCF(frame.root)
        r.AssemblyLinearVelocity=v
        r.AssemblyAngularVelocity=origin:VectorToWorldSpace(vector(frame.angular))
        r.Size=Vector3.new(g[1],g[2],g[3])
        if self.hitbox then self.hitbox.Size=Vector3.new(g[4],g[5],g[6]) end
        h.HipHeight=g[7]
        h.WalkSpeed=frame.humanoid[2]; h.JumpPower=frame.humanoid[3]; h.JumpHeight=frame.humanoid[4]
        h.AutoRotate=false; h.PlatformStand=frame.humanoid[6]==1
        local state=Enum.HumanoidStateType:FromValue(frame.humanoid[1])
        if state and state~=Enum.HumanoidStateType.Dead then h:ChangeState(state) end
        self.hook.direction=if v.Magnitude>1e-8 then v.Unit else Vector3.zero
        for i,name in ipairs({"Sliding","Swinging","Walljump"}) do
            if not self.appliedFlags or self.appliedFlags[i]~=frame.flags[i] then
                local signal=self.animate and self.animate:FindFirstChild(name)
                if signal and signal:IsA("BindableEvent") then signal:Fire(frame.flags[i]==1) end
            end
        end
        self.appliedFlags=table.clone(frame.flags)
        local particles=r:FindFirstChild("SlideParticles")
        if particles and particles:IsA("ParticleEmitter") then
            if self.saved.particles==nil then self.saved.particles=particles.Enabled end
            particles.Enabled=frame.flags[1]==1
        end
        self:Animations(frame.tracks)
        if cameraEnabled then self:Camera(frame,origin) end
    end
    function Character:Animations(samples)
        if not self.animator then return end
        local alive={}
        for i,sample in ipairs(samples) do
            local key=sample.id..":"..i
            alive[key]=true
            local track=self.tracks[key]
            if not track then
                local animation=Instance.new("Animation")
                animation.AnimationId=sample.id
                track=self.animator:LoadAnimation(animation)
                animation:Destroy()
                self.tracks[key]=track
                track:Play(0,0,0)
            end
            local priority=Enum.AnimationPriority:FromValue(sample.priority)
            if priority then track.Priority=priority end
            track.Looped=sample.looped==1
            if not track.IsPlaying then track:Play(0,0,0) end
            track:AdjustSpeed(0)
            track:AdjustWeight(math.clamp(sample.weight,0,1),0)
            track.TimePosition=sample.time
        end
        for key,track in pairs(self.tracks) do
            if not alive[key] then track:Stop(0); track:Destroy(); self.tracks[key]=nil end
        end
    end
    function Character:Camera(frame,origin)
        local camera=workspace.CurrentCamera
        if not camera then return end
        if not self.cameraSaved then self.cameraSaved={object=camera,kind=camera.CameraType,subject=camera.CameraSubject,cf=camera.CFrame} end
        camera.CameraType=Enum.CameraType.Scriptable
        camera.CFrame=origin*unpackCF(frame.camera)
    end
    function Character:Release()
        local s=self.saved
        if self.hook and self.hook.humanoid==self.hum then self.hook.humanoid=nil end
        for _,track in pairs(self.tracks) do track:Stop(0); track:Destroy() end
        table.clear(self.tracks)
        if s then
            self.root.Anchored=s.anchored; self.root.Size=s.size
            if self.hitbox and s.hitbox then self.hitbox.Size=s.hitbox end
            self.hum.HipHeight=s.hip; self.hum.AutoRotate=s.rotate; self.hum.PlatformStand=s.platform
            self.hum.WalkSpeed=s.speed; self.hum.JumpPower=s.jump; self.hum.JumpHeight=s.height
            if self.hum.Health>0 then self.hum:ChangeState(s.state) end
            local particles=self.root:FindFirstChild("SlideParticles")
            if particles and s.particles~=nil then particles.Enabled=s.particles end
            for scriptObject,disabled in pairs(s.scripts) do if scriptObject.Parent then scriptObject.Disabled=disabled end end
            self.saved=nil
        end
        if self.cameraSaved then
            local c=self.cameraSaved
            c.object.CameraType=c.kind; c.object.CameraSubject=c.subject; c.object.CFrame=c.cf
            self.cameraSaved=nil
        end
        self.appliedFlags=nil
    end
    function Character:Resume(frame,origin)
        self:Release()
        local g,h=frame.geometry,self.hum
        self.root.CFrame=origin*unpackCF(frame.root)
        self.root.AssemblyLinearVelocity=origin:VectorToWorldSpace(vector(frame.velocity))
        self.root.AssemblyAngularVelocity=origin:VectorToWorldSpace(vector(frame.angular))
        self.root.Size=Vector3.new(g[1],g[2],g[3])
        if self.hitbox then self.hitbox.Size=Vector3.new(g[4],g[5],g[6]) end
        h.HipHeight=g[7]; h.WalkSpeed=frame.humanoid[2]; h.JumpPower=frame.humanoid[3]; h.JumpHeight=frame.humanoid[4]
        h.AutoRotate=frame.humanoid[5]==1; h.PlatformStand=frame.humanoid[6]==1
        local state=Enum.HumanoidStateType:FromValue(frame.humanoid[1])
        if state and state~=Enum.HumanoidStateType.Dead then h:ChangeState(state) end
        self.flags=table.clone(frame.flags)
        for i,name in ipairs({"Sliding","Swinging","Walljump"}) do
            local signal=self.animate and self.animate:FindFirstChild(name)
            if signal and signal:IsA("BindableEvent") then signal:Fire(frame.flags[i]==1) end
        end
    end
    function Character:Destroy() self:Release(); self.scope:Destroy() end
    return Character
end
