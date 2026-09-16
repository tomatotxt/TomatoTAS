return function(import,config)
    local Tree=import("core/Tree")
    local Scope=import("core/Scope")
    local Sampling=import("core/Sampling")
    local Character=import("runtime/Character")
    local Map=import("runtime/Map")
    local Storage=import("runtime/Storage")
    local RS=game:GetService("RunService")
    local UIS=game:GetService("UserInputService")
    local Players=game:GetService("Players")
    local App={}
    App.__index=App
    function App.new()
        for _,name in ipairs({"getconnections","getsenv","getupvalue","setupvalue","hookmetamethod","newcclosure",
            "readfile","writefile","isfile","isfolder","makefolder","listfiles","delfile"}) do
            assert(type(getfenv()[name] or getgenv()[name])=="function","Missing executor capability: "..name)
        end
        local self=setmetatable({scope=Scope.new(),map=Map.new(),mode="idle",speed=1,camera=true,
            playbackMode="time",time=0,frameIndex=1,busy=false},App)
        self.scope:Add(RS.PostSimulation:Connect(function(dt)
            self:Guard(function()
                if self.mode=="recording" or self.mode=="stepping" then
                    if dt<=0 then return end
                    self.time+=dt
                    self.tree:Append(self.character:Capture(self.time,self.map.origin))
                    if self.mode=="stepping" then self:Pause() end
                end
            end)
        end))
        self.scope:Add(RS.PreSimulation:Connect(function(dt)
            self:Guard(function()
                if self.map.clone and (self.mode=="recording" or self.mode=="stepping") then
                    self.map:RestoreRopes(self.character.model,true)
                end
                if self.mode=="playing" then
                    if self.playbackMode=="frames" then
                        local id=self.path[self.frameIndex]
                        self.tree.cursor=id
                        self.time=self.tree.nodes[id].frame.time
                        self.current=self.tree.nodes[id].frame
                        self.frameIndex+=1
                        if self.frameIndex>#self.path then self.mode="paused" end
                    else
                        self.time=math.min(self.time+dt*self.speed,self.duration)
                        local index
                        self.current,index=Sampling.at(self.tree,self.path,self.time)
                        self.tree.cursor=self.path[index]
                        if self.time>=self.duration then self.mode="paused" end
                    end
                end
                if (self.mode=="playing" or self.mode=="paused") and self.current then
                    self.character:Apply(self.current,self.map.origin,false)
                end
            end)
        end))
        self.scope:Add(RS.RenderStepped:Connect(function()
            self:Guard(function()
                if self.camera and self.current and (self.mode=="playing" or self.mode=="paused") then
                    self.character:Camera(self.current,self.map.origin)
                end
            end)
        end))
        self.scope:Add(Players.LocalPlayer.CharacterAdded:Connect(function()
            if not self.busy then self:Stop(); warn("[TomatoTAS] Character changed. Prepare again before continuing.") end
        end))
        self.scope:Add(UIS.InputBegan:Connect(function(input,processed)
            if processed or UIS:GetFocusedTextBox() then return end
            if input.KeyCode==Enum.KeyCode.End then self:Destroy(); return end
            if input.KeyCode==Enum.KeyCode.F9 then self.map.generation+=1; self:Stop(); return end
            if self.busy then return end
            local actions={
                [Enum.KeyCode.F1]=function() self:Prepare() end,
                [Enum.KeyCode.F2]=function() if self.mode=="recording" then self:Pause() else self:Record() end end,
                [Enum.KeyCode.F3]=function() if self.mode=="playing" then self:Pause() else self:Play() end end,
                [Enum.KeyCode.F4]=function() self:Mark("quick") end,
                [Enum.KeyCode.F5]=function() self:Restore("quick") end,
                [Enum.KeyCode.F6]=function() self:Save(config.File) end,
                [Enum.KeyCode.F7]=function() self:Load(config.File) end,
                [Enum.KeyCode.F8]=function() self:PrepareClone() end,
                [Enum.KeyCode.F9]=function() self:Stop() end,
                [Enum.KeyCode.F10]=function() self:Step() end,
                [Enum.KeyCode.LeftBracket]=function() self:SeekRelative(-1) end,
                [Enum.KeyCode.RightBracket]=function() self:SeekRelative(1) end,
                [Enum.KeyCode.BackSlash]=function() self:NextBranch() end,
                [Enum.KeyCode.End]=function() self:Destroy() end,
            }
            local action=actions[input.KeyCode]
            if action then task.spawn(function() self:Command(action) end) end
        end))
        return self
    end
    function App:Guard(fn)
        if self.scope.dead then return end
        local ok,err=xpcall(fn,debug.traceback)
        if not ok then
            self.mode="idle"
            if self.character then pcall(function() self.character:Release() end) end
            warn("[TomatoTAS] "..tostring(err))
        end
        return ok
    end
    function App:Command(fn)
        if self.busy or self.scope.dead then return end
        self.busy=true
        self:Guard(fn)
        self.busy=false
    end
    function App:Attach(character)
        if self.character then self.character:Destroy() end
        self.character=Character.new(character)
    end
    function App:Prepare()
        self:Stop()
        assert(not self.map.clone,"Destroy/reload the tool before changing maps from a sandbox")
        self.map:Acquire()
        self:Attach(Players.LocalPlayer.Character)
        print("[TomatoTAS] Prepared "..self.map.name)
    end
    function App:PrepareClone()
        self:Stop()
        if not self.map.live then self:Prepare() end
        local ok,err=xpcall(function()
            self.map:Clone()
            self:Attach(self.map:Respawn())
        end,debug.traceback)
        if not ok then
            self.map:Destroy()
            if not self.scope.dead then self.map=Map.new() end
            error(err)
        end
        warn("[TomatoTAS] Static sandbox ready. Server-driven map mechanics and full world rewind are not implemented.")
    end
    function App:Ready(ignoreRun)
        assert(self.character and self.character:Valid() and self.map.origin,"Prepare a map and living character first")
        assert((self.map.clone or self.map.live).Parent,"Prepared map was removed")
        if self.tree and not ignoreRun then
            assert(self.tree.metadata.map==self.map.name,"Loaded run belongs to another map; call NewRun to start fresh")
            assert(self.tree.metadata.spawn==self.map.spawnName,"Spawn path differs from the recorded map")
        end
    end
    function App:NewRun()
        self:Stop(); self:Ready(true)
        self.tree=Tree.new({map=self.map.name,spawn=self.map.spawnName,author=Players.LocalPlayer.Name,created=os.time()})
        self.time=0; self.path=nil; self.current=nil
        self.tree:Append(self.character:Capture(0,self.map.origin))
    end
    function App:Record()
        self:Ready()
        assert(self.mode~="playing","Pause playback before recording a branch")
        if not self.tree then self:NewRun() end
        self.time=self.tree.nodes[self.tree.cursor].frame.time
        self.character:Resume(self.tree.nodes[self.tree.cursor].frame,self.map.origin)
        self.current=nil; self.path=nil
        self.mode="recording"
        print("[TomatoTAS] Recording from node "..self.tree.cursor)
    end
    function App:Pause()
        self:Ready()
        assert(self.tree and self.tree.cursor>0,"No recorded frames")
        self.mode="paused"
        -- Use an exact stored frame when pausing; never branch from an interpolated pose.
        self.current=self.tree.nodes[self.tree.cursor].frame
        self.time=self.current.time
        self.character:Apply(self.current,self.map.origin,self.camera)
    end
    function App:Play(tip,mode)
        self:Ready()
        assert(self.tree,"No run loaded or recorded")
        assert(mode==nil or mode=="time" or mode=="frames","Playback mode must be time or frames")
        if tip then self.tree:Seek(tip) end
        if tip or not self.path or self.mode~="paused" or self.time>=self.duration then
            self.path=self.tree:Path(self.tree.cursor)
            self.time=0; self.frameIndex=1
        else
            local index=table.find(self.path,self.tree.cursor)
            if not index then self.path=self.tree:Path(self.tree.cursor); self.time=0; self.frameIndex=1
            else self.frameIndex=index end
        end
        self.duration=self.tree.nodes[self.path[#self.path]].frame.time
        self.playbackMode=mode or self.playbackMode
        self.current=self.tree.nodes[self.path[self.frameIndex]].frame
        self.character:Apply(self.current,self.map.origin,self.camera)
        self.mode="playing"
    end
    function App:Seek(node)
        self:Ready()
        assert(self.tree,"No run")
        self.tree:Seek(node)
        self:Pause()
    end
    function App:SeekRelative(delta)
        assert(self.tree,"No run")
        if not self.path or not table.find(self.path,self.tree.cursor) then self.path=self.tree:Path() end
        local index=table.find(self.path,self.tree.cursor)
        self:Seek(self.path[math.clamp(index+delta,1,#self.path)])
    end
    function App:NextBranch()
        assert(self.tree,"No run")
        local tips=self.tree:Branches()
        local index=table.find(tips,self.path and self.path[#self.path] or self.tree.cursor) or 0
        local tip=tips[index%#tips+1]
        self.path=self.tree:Path(tip)
        self:Seek(tip)
        print("[TomatoTAS] Branch tip "..tip)
    end
    function App:Step()
        assert(self.mode=="paused","Pause before stepping one physics frame")
        self:Record()
        self.mode="stepping"
    end
    function App:Mark(name)
        self:Pause(); self.tree:Mark(name)
        warn("[TomatoTAS] Character mark saved. World state is not captured in this version.")
    end
    function App:Restore(name)
        assert(self.tree and self.tree.marks[name],"Unknown character mark")
        self:Seek(self.tree.marks[name])
        warn("[TomatoTAS] Character restored. Map timers, buttons and liquids have not been rewound.")
    end
    function App:SetSpeed(speed)
        assert(type(speed)=="number" and speed>0 and speed<=16,"Playback speed must be >0 and <=16")
        self.speed=speed
    end
    function App:Stop()
        self.mode="idle"; self.current=nil; self.path=nil
        if self.character then
            local ok,err=pcall(function() self.character:Release() end)
            if not ok then warn("[TomatoTAS] Character cleanup: "..tostring(err)) end
        end
    end
    function App:Save(name)
        assert(self.tree and #self.tree.nodes>0,"No run to save")
        local target,size=Storage.save(name or config.File,self.tree)
        print("[TomatoTAS] Saved "..target.." ("..size.." bytes)")
        return target
    end
    function App:Load(name)
        local tree=Storage.load(name or config.File)
        if self.map.name then assert(tree.metadata.map==self.map.name,"File map does not match prepared map") end
        self:Stop(); self.tree=tree; self.time=tree.nodes[tree.cursor].frame.time
        print("[TomatoTAS] Loaded "..#tree.nodes.." frames across "..#tree:Branches().." branches")
    end
    function App:ListFiles() return Storage.list() end
    function App:Status()
        return {mode=self.mode,map=self.map.name,time=self.time,node=self.tree and self.tree.cursor or 0,
            nodes=self.tree and #self.tree.nodes or 0,branches=self.tree and self.tree:Branches() or {},worldRewind=false}
    end
    function App:RestoreWorld() error("Full map rewind is deferred; no world-state provider is installed") end
    function App:Destroy()
        if self.scope.dead then return end
        self:Stop(); self.scope:Destroy()
        if self.character then
            local ok,err=pcall(function() self.character:Destroy() end)
            if not ok then warn("[TomatoTAS] Character unload: "..tostring(err)) end
        end
        local ok,err=pcall(function() self.map:Destroy() end)
        if not ok then warn("[TomatoTAS] Map unload: "..tostring(err)) end
        if getgenv().TomatoTAS==self then getgenv().TomatoTAS=nil end
        print("[TomatoTAS] Unloaded")
    end
    return App
end
