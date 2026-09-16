return function(import)
    local Q=import("core/Quaternion")
    local Scope=import("core/Scope")
    local Players=game:GetService("Players")
    local Character={}
    Character.__index=Character
    local flagNames={"Sliding","Swinging","Walljump"}
    local scriptNames={"CL_AntiSideClip","CL_AirMomentum","FE2_Character","Animate"}
    local function cleanup(label,fn)
        local ok,err=pcall(fn)
        if not ok then warn("[TomatoTAS] "..label..": "..tostring(err)) end
        return ok
    end
    local function destroyTrack(track)
        cleanup("Animation stop",function() track:Stop(0) end)
        cleanup("Animation cleanup",function() track:Destroy() end)
    end
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
        local self=setmetatable({model=model,scope=Scope.new(),flags={0,0,0},tracks={},
            failedAnimations={},flagConnections={},flagSignals={},captureOrder=setmetatable({},{__mode="k"}),
            nextTrackID=0},Character)
        self.root=assert(model:FindFirstChild("HumanoidRootPart"),"Character root not ready")
        assert(self.root:IsA("BasePart"),"Character root must be a BasePart")
        self.hum=assert(model:FindFirstChildOfClass("Humanoid"),"Humanoid not ready")
        self.scope:Add(function()
            for _,connection in pairs(self.flagConnections) do
                cleanup("Character event cleanup",function() connection:Disconnect() end)
            end
            table.clear(self.flagConnections)
            table.clear(self.flagSignals)
        end)
        self:Refresh()
        return self
    end
    function Character:Refresh()
        -- FE2 installs the hitbox, Animate events and Animator after character spawn.
        local animator=self.hum:FindFirstChildOfClass("Animator")
        if animator~=self.animator then
            for _,track in pairs(self.tracks) do destroyTrack(track) end
            table.clear(self.tracks)
            table.clear(self.failedAnimations)
            self.animator=animator
        end
        local hitbox=self.model:FindFirstChild("FE2_Hitbox",true)
        self.hitbox=if hitbox and hitbox:IsA("BasePart") then hitbox else nil
        self.animate=self.model:FindFirstChild("Animate")
        for i,name in ipairs(flagNames) do
            local signal=self.animate and self.animate:FindFirstChild(name)
            if signal and not signal:IsA("BindableEvent") then signal=nil end
            if self.flagSignals[i]~=signal then
                if self.flagConnections[i] then self.flagConnections[i]:Disconnect() end
                self.flagSignals[i]=signal
                -- A replacement BindableEvent has not received the current
                -- puppet flag even when the recorded state itself is unchanged.
                if self.appliedFlags then self.appliedFlags[i]=nil end
                self.flagConnections[i]=if signal then signal.Event:Connect(function(active)
                    self.flags[i]=if active then 1 else 0
                end) else nil
            end
        end
    end
    function Character:Valid()
        return not self.scope.dead and self.model==Players.LocalPlayer.Character and self.model.Parent~=nil
            and self.root.Parent==self.model and self.hum.Parent==self.model and self.hum.Health>0
    end
    function Character:Capture(time,origin)
        assert(self:Valid(),"Character died or changed")
        self:Refresh()
        local tracks={}
        if self.animator then
            local playing=self.animator:GetPlayingAnimationTracks()
            for _,track in ipairs(playing) do
                if not self.captureOrder[track] then
                    self.nextTrackID+=1
                    self.captureOrder[track]=self.nextTrackID
                end
            end
            -- Roblox does not promise a stable order for playing tracks. Keep the
            -- same asset occurrences aligned across captures and interpolation.
            table.sort(playing,function(a,b)
                local aID,bID=a.Animation and a.Animation.AnimationId or "",b.Animation and b.Animation.AnimationId or ""
                if aID~=bID then return aID<bID end
                return self.captureOrder[a]<self.captureOrder[b]
            end)
            for _,track in ipairs(playing) do
                if track.Animation then
                    table.insert(tracks,{id=track.Animation.AnimationId,time=track.TimePosition,speed=track.Speed,
                        weight=track.WeightCurrent,priority=track.Priority.Value,looped=if track.Looped then 1 else 0})
                end
            end
        end
        local r,h=self.root,self.hum
        local hit=self.hitbox and self.hitbox.Size or r.Size
        local flags=table.clone(self.flags)
        -- Geometry also recovers the sliding state when attaching mid-slide.
        flags[1]=if h.HipHeight < -1 or r.Size.Y<1.5 then 1 else 0
        local camera=workspace.CurrentCamera
        return {time=time,root=pack(origin:ToObjectSpace(r.CFrame)),
            velocity=vec(origin:VectorToObjectSpace(r.AssemblyLinearVelocity)),
            angular=vec(origin:VectorToObjectSpace(r.AssemblyAngularVelocity)),
            camera=pack(origin:ToObjectSpace(camera and camera.CFrame or r.CFrame)),
            geometry={r.Size.X,r.Size.Y,r.Size.Z,hit.X,hit.Y,hit.Z,h.HipHeight},
            humanoid={h:GetState().Value,h.WalkSpeed,h.JumpPower,h.JumpHeight,if h.AutoRotate then 1 else 0,
                if h.PlatformStand then 1 else 0,h.Health},flags=flags,tracks=tracks}
    end
    function Character:SuspendScripts()
        for _,name in ipairs(scriptNames) do
            local scriptObject=self.model:FindFirstChild(name)
            if scriptObject and scriptObject:IsA("LocalScript") then
                if self.saved.scripts[scriptObject]==nil then self.saved.scripts[scriptObject]=scriptObject.Disabled end
                scriptObject.Disabled=true
            end
        end
    end
    function Character:Acquire()
        if self.saved then return end
        assert(self:Valid(),"Character not available")
        self:Refresh()
        local r,h=self.root,self.hum
        self.saved={anchored=r.Anchored,size=r.Size,hitboxes={},particles={},flags=table.clone(self.flags),
            hip=h.HipHeight,rotate=h.AutoRotate,platform=h.PlatformStand,speed=h.WalkSpeed,
            jump=h.JumpPower,height=h.JumpHeight,state=h:GetState(),scripts={}}
        local ok,err=xpcall(function()
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
            local hook=env.__TomatoTASMoveHook
            assert(type(hook)=="table" and (hook.owner==nil or hook.owner==self),"Character is controlled by another TomatoTAS instance")
            self.hook=hook
            hook.owner=self; hook.humanoid=h; hook.direction=Vector3.zero
            self:SuspendScripts()
            if self.animator then
                for _,track in ipairs(self.animator:GetPlayingAnimationTracks()) do track:Stop(0) end
            end
        end,debug.traceback)
        if not ok then
            self:Release()
            error(err,0)
        end
    end
    function Character:Apply(frame,origin,cameraEnabled)
        assert(self:Valid(),"Character died or changed")
        self:Acquire()
        self:Refresh()
        self:SuspendScripts()
        local r,h=self.root,self.hum
        local g,v=frame.geometry,origin:VectorToWorldSpace(vector(frame.velocity))
        r.Anchored=true -- prevents physics from integrating past the recorded sample
        r.CFrame=origin*unpackCF(frame.root)
        r.AssemblyLinearVelocity=v
        r.AssemblyAngularVelocity=origin:VectorToWorldSpace(vector(frame.angular))
        r.Size=Vector3.new(g[1],g[2],g[3])
        if self.hitbox then
            if self.saved.hitboxes[self.hitbox]==nil then self.saved.hitboxes[self.hitbox]=self.hitbox.Size end
            self.hitbox.Size=Vector3.new(g[4],g[5],g[6])
        end
        h.HipHeight=g[7]
        h.WalkSpeed=frame.humanoid[2]; h.JumpPower=frame.humanoid[3]; h.JumpHeight=frame.humanoid[4]
        h.AutoRotate=false; h.PlatformStand=frame.humanoid[6]==1
        local state=Enum.HumanoidStateType:FromValue(frame.humanoid[1])
        if state and state~=Enum.HumanoidStateType.Dead then h:ChangeState(state) end
        local horizontal=Vector3.new(v.X,0,v.Z)
        self.hook.direction=if horizontal.Magnitude>1e-8 then horizontal.Unit else Vector3.zero
        for i in ipairs(flagNames) do
            if not self.appliedFlags or self.appliedFlags[i]~=frame.flags[i] then
                local signal=self.flagSignals[i]
                if signal then signal:Fire(frame.flags[i]==1) end
            end
        end
        self.appliedFlags=table.clone(frame.flags)
        local particles=r:FindFirstChild("SlideParticles")
        if particles and particles:IsA("ParticleEmitter") then
            if self.saved.particles[particles]==nil then self.saved.particles[particles]=particles.Enabled end
            particles.Enabled=frame.flags[1]==1
        end
        self:Animations(frame.tracks)
        if cameraEnabled then self:Camera(frame,origin) end
    end
    function Character:Animations(samples)
        if not self.animator then return end
        local alive,occurrences,owned={},{},{}
        for _,sample in ipairs(samples) do
            occurrences[sample.id]=(occurrences[sample.id] or 0)+1
            local key=sample.id..":"..occurrences[sample.id]
            alive[key]=true
            local track=self.tracks[key]
            if not self.failedAnimations[sample.id] then
                local animation
                local ok,err=pcall(function()
                    if not track then
                        animation=Instance.new("Animation")
                        animation.AnimationId=sample.id
                        track=self.animator:LoadAnimation(animation)
                        self.tracks[key]=track
                    end
                    local priority=Enum.AnimationPriority:FromValue(sample.priority)
                    if priority then track.Priority=priority end
                    track.Looped=sample.looped==1
                    if not track.IsPlaying then track:Play(0,0,0) end
                    track:AdjustSpeed(0)
                    -- Roblox weights can exceed one; clamping changes the
                    -- relative blend between otherwise identical recordings.
                    track:AdjustWeight(math.max(sample.weight,0),0)
                    track.TimePosition=sample.time
                end)
                if animation then cleanup("Animation asset cleanup",function() animation:Destroy() end) end
                if ok then owned[track]=true
                else
                    self.failedAnimations[sample.id]=true
                    if track then destroyTrack(track); self.tracks[key]=nil end
                    warn("[TomatoTAS] Animation "..sample.id.." unavailable: "..tostring(err))
                end
            end
        end
        for key,track in pairs(self.tracks) do
            if not alive[key] or not owned[track] then destroyTrack(track); self.tracks[key]=nil end
        end
        -- Remote/game scripts can start tracks after takeover. They must not blend
        -- unrecorded poses into the puppet, even when Animate is disabled.
        for _,track in ipairs(self.animator:GetPlayingAnimationTracks()) do
            if not owned[track] then cleanup("Unrecorded animation stop",function() track:Stop(0) end) end
        end
    end
    function Character:Camera(frame,origin)
        local camera=workspace.CurrentCamera
        if self.cameraSaved and self.cameraSaved.object~=camera then self:ReleaseCamera() end
        if not camera then return end
        if not self.cameraSaved then self.cameraSaved={object=camera,kind=camera.CameraType,subject=camera.CameraSubject,cf=camera.CFrame} end
        camera.CameraType=Enum.CameraType.Scriptable
        camera.CFrame=origin*unpackCF(frame.camera)
    end
    function Character:ReleaseCamera()
        local c=self.cameraSaved
        if not c then return end
        self.cameraSaved=nil
        cleanup("Camera subject restore",function() c.object.CameraSubject=c.subject end)
        cleanup("Camera transform restore",function() c.object.CFrame=c.cf end)
        cleanup("Camera mode restore",function() c.object.CameraType=c.kind end)
    end
    function Character:Release()
        local s=self.saved
        self.saved=nil
        if self.hook and self.hook.owner==self then
            self.hook.humanoid=nil; self.hook.owner=nil; self.hook.direction=Vector3.zero
        end
        self.hook=nil
        for _,track in pairs(self.tracks) do destroyTrack(track) end
        table.clear(self.tracks)
        table.clear(self.failedAnimations)
        if s then
            -- Every restoration is isolated: one destroyed Instance must not leave
            -- the root anchored, scripts disabled or the camera captured.
            cleanup("Root anchor restore",function() self.root.Anchored=s.anchored end)
            cleanup("Root size restore",function() self.root.Size=s.size end)
            for hitbox,size in pairs(s.hitboxes) do cleanup("Hitbox restore",function() hitbox.Size=size end) end
            for property,key in pairs({HipHeight="hip",AutoRotate="rotate",PlatformStand="platform",
                WalkSpeed="speed",JumpPower="jump",JumpHeight="height"}) do
                cleanup("Humanoid "..property.." restore",function() self.hum[property]=s[key] end)
            end
            cleanup("Humanoid state restore",function()
                if self.hum.Health>0 then self.hum:ChangeState(s.state) end
            end)
            for particles,enabled in pairs(s.particles) do cleanup("Slide particles restore",function() particles.Enabled=enabled end) end
            self.flags=table.clone(s.flags)
            for scriptObject,disabled in pairs(s.scripts) do
                cleanup("Character script restore",function() if scriptObject.Parent then scriptObject.Disabled=disabled end end)
            end
        end
        self:ReleaseCamera()
        self.appliedFlags=nil
    end
    function Character:Resume(frame,origin)
        assert(self:Valid(),"Character died or changed")
        self:Release()
        self:Refresh()
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
        for i in ipairs(flagNames) do
            local signal=self.flagSignals[i]
            if signal then signal:Fire(frame.flags[i]==1) end
        end
        local particles=self.root:FindFirstChild("SlideParticles")
        if particles and particles:IsA("ParticleEmitter") then particles.Enabled=frame.flags[1]==1 end
    end
    function Character:Destroy() self:Release(); self.scope:Destroy() end
    return Character
end
