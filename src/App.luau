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
    local defaultKeys={Prepare="F1",Record="F2",Play="F3",Mark="F4",Restore="F5",Save="F6",Load="F7",
        Clone="F8",Stop="F9",Step="F10",PreviousFrame="LeftBracket",NextFrame="RightBracket",
        NextBranch="BackSlash",Unload="End"}
    local actions={
        Prepare=function(self) self:Prepare() end,
        Record=function(self) if self.mode=="recording" then self:Pause() else self:Record() end end,
        Play=function(self) if self.mode=="playing" then self:Pause() else self:Play() end end,
        Mark=function(self) self:Mark("quick") end,
        Restore=function(self) self:Restore("quick") end,
        Save=function(self) self:FileCommand("Save",config.File) end,
        Load=function(self) self:FileCommand("Load",config.File) end,
        Clone=function(self) self:PrepareClone() end,
        Stop=function(self) self:Cancel() end,
        Step=function(self) self:Step() end,
        PreviousFrame=function(self) self:SeekRelative(-1) end,
        NextFrame=function(self) self:SeekRelative(1) end,
        NextBranch=function(self) self:NextBranch() end,
        Unload=function(self) self:Destroy() end,
    }
    local function bindings()
        local overrides=config.Keybinds or {}
        assert(type(overrides)=="table","Keybinds must be a table of action names to key names or false")
        for action in pairs(overrides) do assert(defaultKeys[action],"Unknown keybind action: "..tostring(action)) end
        local result={}
        for action,default in pairs(defaultKeys) do
            local key=overrides[action]
            if key==nil then key=default end
            if key~=false then
                assert(type(key)=="string","Keybind for "..action.." must be a key name or false")
                local code=Enum.KeyCode:FromName(key)
                assert(code and code~=Enum.KeyCode.Unknown,"Unknown key: "..key)
                assert(not result[code],"Duplicate keybind: "..key)
                result[code]=action
            end
        end
        return result
    end
    function App.Validate()
        for _,name in ipairs({"getconnections","getsenv","getupvalue","setupvalue","hookmetamethod","newcclosure",
            "readfile","writefile","isfile","isfolder","makefolder","listfiles","delfile"}) do
            assert(type(getfenv()[name] or getgenv()[name])=="function","Missing executor capability: "..name)
        end
        return bindings()
    end
    function App.new()
        local keys=App.Validate()
        local self=setmetatable({scope=Scope.new(),map=Map.new(),mode="idle",speed=1,camera=true,
            playbackMode="time",time=0,frameIndex=1,busy=false,cancelId=0,keys=keys},App)
        self.scope:Add(RS.PostSimulation:Connect(function(dt)
            self:Guard(function()
                if self.mode=="recording" or self.mode=="stepping" then
                    self:Ready()
                    if dt<=0 then return end
                    self.time+=dt
                    self.tree:Append(self.character:Capture(self.time,self.map.origin))
                    if self.mode=="stepping" then self:Pause() end
                end
            end)
        end))
        self.scope:Add(RS.PreSimulation:Connect(function(dt)
            self:Guard(function()
                -- A step requested after physics must not capture that already
                -- completed frame. Release the held character at the next boundary.
                if self.mode=="stepPending" then
                    self:Record()
                    self.mode="stepping"
                end
                if self.mode=="playing" or self.mode=="paused" then self:Ready() end
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
                if self.camera and self.current and (self.mode=="playing" or self.mode=="paused" or self.mode=="stepPending") then
                    self.character:Camera(self.current,self.map.origin)
                elseif self.character then
                    self.character:ReleaseCamera()
                end
            end)
        end))
        self.scope:Add(Players.LocalPlayer.CharacterAdded:Connect(function()
            if not self.busy then
                self:Stop()
                if self.character then self.character:Destroy(); self.character=nil end
                print("[TomatoTAS] Character changed. Prepare again before continuing.")
            end
        end))
        self.scope:Add(UIS.InputBegan:Connect(function(input,processed)
            if processed or UIS:GetFocusedTextBox() then return end
            local action=self.keys[input.KeyCode]
            if action=="Stop" or action=="Unload" then self:Dispatch(action); return end
            if action and not self.busy then task.spawn(function() self:Dispatch(action) end) end
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
        local token=self.cancelId
        local ok,err=xpcall(fn,debug.traceback)
        if not ok and token==self.cancelId and not self.scope.dead then
            self:Stop()
            warn("[TomatoTAS] "..tostring(err))
        end
        self.busy=false
        return ok
    end
    function App:Cancel()
        self.cancelId+=1
        self.map.generation+=1
        self:Stop()
    end
    function App:Dispatch(action)
        assert(actions[action],"Unknown action: "..tostring(action))
        if self.scope.dead then return false end
        if action=="Stop" or action=="Unload" then actions[action](self); return true end
        if self.busy then return false end
        local reason=self:ActionReason(action)
        if reason then print("[TomatoTAS] "..reason); return false end
        return self:Command(function() actions[action](self) end)
    end
    function App:ActionReason(action)
        if action=="Load" then return nil end
        if action=="Prepare" then
            return if self.map.clone then "Unload the sandbox before preparing a different map." else nil
        end
        if action=="Clone" then
            return if self.map.clone then "The sandbox is already prepared." else nil
        end
        local hasRun=self.tree and #self.tree.nodes>0
        if action~="Record" and not hasRun then return "No run yet. Prepare with F1 and record with F2, or load with F7." end
        if action=="Save" then return nil end
        -- Cycling with no alternate future is a harmless status request.
        if action=="NextBranch" and #self.tree:Branches()<2 then return "No alternate branches to cycle yet." end
        local ready=self:ReadyReason()
        if ready then return ready end
        if action=="Record" and self.mode=="playing" then return "Pause playback before recording a branch." end
        if action=="Step" and self.mode~="paused" then return "Pause before advancing one physics frame." end
        if action=="Restore" and not self.tree.marks.quick then return "No quick character mark. Save one with F4 first." end
        return nil
    end
    function App:FileCommand(method,...)
        local ok,result=pcall(self[method],self,...)
        if not ok then warn("[TomatoTAS] "..method.." failed: "..tostring(result)) end
        return ok,result
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
    function App:ReadyReason(ignoreRun)
        if not self.character or not self.character:Valid() or not self.map.origin then return "Prepare a map and living character first." end
        local model=self.map.clone or self.map.live
        if not model or not model.Parent then return "Prepared map was removed. Prepare the current map first." end
        if self.tree and not ignoreRun then
            if self.tree.metadata.map~=self.map.name then return "Loaded run belongs to another map; call NewRun to start fresh." end
            if self.tree.metadata.spawn~=self.map.spawnName then return "Spawn path differs from the recorded map." end
        end
        return nil
    end
    function App:Ready(ignoreRun)
        local reason=self:ReadyReason(ignoreRun)
        assert(not reason,reason)
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
        if tip or not self.path or self.mode~="paused"
            or self.time>=self.tree.nodes[self.path[#self.path]].frame.time then
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
        if not self.path or not table.find(self.path,node) then self.path=self.tree:Path(node) end
        self:Pause()
    end
    function App:SeekRelative(delta)
        assert(self.tree,"No run")
        if not self.path or not table.find(self.path,self.tree.cursor) then self.path=self.tree:Path() end
        local index=table.find(self.path,self.tree.cursor)
        self:Seek(self.path[math.clamp(index+delta,1,#self.path)])
    end
    function App:NextBranch()
        if not self.tree then
            print("[TomatoTAS] No run to cycle. Record with F2 after preparing with F1, or load a run with F7.")
            return false
        end
        local tips=self.tree:Branches()
        if #tips<2 then
            print("[TomatoTAS] No alternate branches. Restore an earlier character mark and record a different continuation first.")
            return false
        end
        local index=table.find(tips,self.path and self.path[#self.path] or self.tree.cursor) or 0
        local tip=tips[index%#tips+1]
        self.path=self.tree:Path(tip)
        self:Seek(tip)
        print("[TomatoTAS] Branch tip "..tip)
        return true
    end
    function App:Step()
        assert(self.mode=="paused","Pause before stepping one physics frame")
        self:Ready()
        self.mode="stepPending"
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
    function App:SetCamera(enabled)
        assert(type(enabled)=="boolean","Camera enabled must be a boolean")
        self.camera=enabled
        if not enabled and self.character then self.character:ReleaseCamera() end
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
    function App:Load(name,source)
        local tree=Storage.load(name or config.File,source)
        if self.map.name then assert(tree.metadata.map==self.map.name,"File map does not match prepared map") end
        if self.map.spawnName then assert(tree.metadata.spawn==self.map.spawnName,"File spawn does not match prepared map") end
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
        self:Cancel(); self.scope:Destroy()
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
