return function(import,config)
    local Scope=import("core/Scope")
    local RS=game:GetService("RunService")
    local Players=game:GetService("Players")
    local Storage=game:GetService("ReplicatedStorage")
    local Map={}
    Map.__index=Map
    function Map.new()
        local self=setmetatable({scope=Scope.new(),generation=0,ropeCache=setmetatable({},{__mode="k"})},Map)
        local remote=Storage:FindFirstChild("Remote")
        local rope=remote and remote:FindFirstChild("UpdRopeData")
        if rope then
            self.scope:Add(rope.OnClientEvent:Connect(function(data)
                if type(data)=="table" then
                    local multiplayer=workspace:FindFirstChild("Multiplayer")
                    local source=multiplayer and (multiplayer:FindFirstChild("NewMap") or multiplayer:FindFirstChild("Map"))
                    if source then
                        self.ropeCache[source]=data
                        -- A later live round must not replace the sandbox's cached nodes.
                        if source==self.live and not self.clone then self.ropes=data end
                    end
                end
            end))
        end
        return self
    end
    function Map:Check(token,deadline,timeoutMessage)
        assert(not self.scope.dead and self.generation==token,"Map operation cancelled")
        assert(os.clock()<deadline,timeoutMessage or "Map operation timed out")
    end
    function Map:Wait(predicate,token,timeoutMessage)
        local deadline=os.clock()+config.Timeout
        repeat
            self:Check(token,deadline,timeoutMessage)
            local result=predicate()
            if result then return result end
            RS.Heartbeat:Wait()
        until false
    end
    function Map:LivingCharacter()
        local character=Players.LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health>0 then return character end
        return nil
    end
    function Map:ReadyReason()
        if self.scope.dead then return "Map runtime has been destroyed" end
        local model=self.clone or self.live
        if not model then return "Prepare a map first" end
        if self.clone then
            if model.Parent~=workspace then return "Sandbox was removed; reload and prepare again" end
        else
            local multiplayer=workspace:FindFirstChild("Multiplayer")
            if not multiplayer or model.Parent~=multiplayer or multiplayer:FindFirstChild("Map")~=model then
                return "Live map changed; prepare the current round first"
            end
        end
        local spawn=if self.clone then self.cloneSpawn else self.spawn
        if not spawn or not spawn:IsDescendantOf(model) then return "Prepared spawn was removed; prepare again" end
        return nil
    end
    function Map:FindSpawn(live,root)
        local spawn=live:FindFirstChild("Spawn",true)
        if spawn and spawn:IsA("BasePart") and (spawn.Position-root.Position).Magnitude<60 then
            return spawn
        end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={live}
        local result=workspace:Raycast(root.Position,Vector3.new(0,-25,0),params)
        spawn=result and result.Instance
        return if spawn and spawn:IsA("BasePart") and spawn:IsDescendantOf(live) then spawn else nil
    end
    function Map:AutoCandidate()
        if self.scope.dead or self.clone then return nil end
        local multiplayer=workspace:FindFirstChild("Multiplayer")
        local live=multiplayer and multiplayer:FindFirstChild("Map")
        local character=self:LivingCharacter()
        if not live or not live:IsA("Model") or not character then return nil end
        if self:FindSpawn(live,character:FindFirstChild("HumanoidRootPart")) then return live,character end
        return nil
    end
    function Map:Acquire()
        assert(not self.scope.dead,"Map operation cancelled")
        assert(not self.clone,"Destroy the sandbox before acquiring another map")
        self.generation+=1
        local token=self.generation
        local multiplayer=self:Wait(function() return workspace:FindFirstChild("Multiplayer") end,token,
            "Timed out waiting for FE2's Multiplayer container. Wait for the game to load and retry Prepare.")
        self:Wait(function()
            multiplayer=workspace:FindFirstChild("Multiplayer")
            local live=multiplayer and multiplayer:FindFirstChild("Map")
            return if live and live:IsA("Model") then live else nil
        end,token,
            "Timed out waiting for the FE2 map. Start a round and retry Prepare.")
        -- FE2 can temporarily anchor the root or lower WalkSpeed while placing a
        -- player at spawn. The live map and spawn checks below are the authority
        -- for location; neither movement state nor a hard-coded lobby position is.
        local live,root,spawn
        local character=self:Wait(function()
            -- Map replication can finish before the lobby character is moved. Look
            -- up the current map each time so a new round cannot leave a stale map.
            multiplayer=workspace:FindFirstChild("Multiplayer")
            live=multiplayer and multiplayer:FindFirstChild("Map")
            local candidate=self:LivingCharacter()
            if not live or not live:IsA("Model") or not candidate then return nil end
            root=candidate:FindFirstChild("HumanoidRootPart")
            spawn=self:FindSpawn(live,root)
            return if spawn then candidate else nil
        end,token,"Timed out waiting for a living character at the FE2 map spawn. Join a round and retry Prepare.")
        self:Settle(spawn,token)
        assert(self:LivingCharacter()==character and character:FindFirstChild("HumanoidRootPart")==root,
            "Character changed or died during settling; retry Prepare.")
        assert(workspace:FindFirstChild("Multiplayer")==multiplayer and live.Parent==multiplayer
            and multiplayer:FindFirstChild("Map")==live and spawn:IsDescendantOf(live),
            "Map/spawn changed during settling; retry Prepare.")
        assert(self:FindSpawn(live,root)==spawn,"Character left the spawn during settling; retry Prepare.")
        local settings=live:FindFirstChild("Settings")
        self.live,self.spawn=live,spawn
        self.ropes=self.ropeCache[live]
        if not self.ropes then
            -- Joining mid-round can miss the remote. Recover only the table already
            -- installed in this character's documented FE2 closure.
            local scriptObject=character:FindFirstChild("FE2_Character")
            if scriptObject then
                local ok,data=pcall(function()
                    local fn=getsenv(scriptObject).startZipline
                    return type(fn)=="function" and getupvalue(fn,2) or nil
                end)
                if ok and type(data)=="table" then self.ropes=data; self.ropeCache[live]=data end
            end
        end
        self.name=tostring(settings and settings:GetAttribute("MapName") or live.Name)
        self.spawnName=spawn:GetFullName():sub(#live:GetFullName()+2)
        self.origin=spawn.CFrame
        self.offset=spawn.CFrame:ToObjectSpace(root.CFrame)
        return self,character
    end
    function Map:Settle(spawn,token)
        token=token or self.generation
        local deadline=os.clock()+config.Timeout
        local anchor=spawn.CFrame
        local since=os.clock()
        while os.clock()-since<1 do
            self:Check(token,deadline,"Spawn kept moving for too long; wait for the platform to settle and retry.")
            assert(spawn.Parent,"Spawn removed while settling")
            RS.Heartbeat:Wait()
            self:Check(token,deadline,"Spawn kept moving for too long; wait for the platform to settle and retry.")
            assert(spawn.Parent,"Spawn removed while settling")
            local current=spawn.CFrame
            local _,angle=anchor:ToObjectSpace(current):ToAxisAngle()
            if (current.Position-anchor.Position).Magnitude>=0.005 or math.abs(angle)>0.0001 then
                anchor=current; since=os.clock()
            end
        end
        self:Check(token,deadline,"Spawn kept moving for too long; wait for the platform to settle and retry.")
    end
    function Map:RestoreRopes(character,quiet)
        if self.scope.dead then return false end
        if not self.ropes then
            if not quiet then warn("[TomatoTAS] No zipline data available. Join a new round before cloning for zipline support.") end
            return false
        end
        local token=self.generation
        local function closure()
            assert(Players.LocalPlayer.Character==character,"Character changed while restoring ziplines")
            local scriptObject=character:FindFirstChild("FE2_Character")
            if not scriptObject then return nil end
            -- A newly replicated LocalScript may exist before its environment is ready.
            local ok,env=pcall(getsenv,scriptObject)
            return if ok and type(env)=="table" and type(env.startZipline)=="function" then env.startZipline else nil
        end
        local fn=if quiet then closure() else self:Wait(closure,token,
            "Timed out waiting for FE2's zipline script to initialize. Respawn and retry.")
        if not fn then return false end
        local current=getupvalue(fn,2)
        if current==self.ropes then return true end
        assert(current==nil or type(current)=="table","Zipline upvalue layout changed; refusing to overwrite")
        setupvalue(fn,2,self.ropes)
        assert(getupvalue(fn,2)==self.ropes,"Zipline table restore failed")
        return true
    end
    function Map:Clone()
        assert(self.live and self.live.Parent,"Prepare a live map first")
        assert(not self.clone,"Clone already prepared")
        local token=self.generation
        local live,spawn=self.live,self.spawn
        local liveParent=live.Parent
        self:Settle(spawn,token)
        local deadline=os.clock()+config.Timeout
        self:Check(token,deadline)
        assert(live.Parent==liveParent,"Live map changed during settling")
        local character=assert(self:LivingCharacter(),"Living character unavailable")
        local offset=spawn.CFrame:ToObjectSpace(character.HumanoidRootPart.CFrame)
        local queue={live}
        for _,item in ipairs(live:GetDescendants()) do table.insert(queue,item) end
        local parents={}
        for _,item in ipairs(queue) do parents[item]=item.Parent end
        assert(parents[spawn],"Prepared spawn is no longer in the live map")
        local changed,connections={},{}
        local clone,cloneSpawn,tag
        local function validate()
            self:Check(token,deadline)
            assert(self.live==live and self.spawn==spawn and live.Parent==liveParent,"Live map changed during clone preparation")
            assert(Players.LocalPlayer.Character==character,"Character changed during clone preparation")
            local descendants=live:GetDescendants()
            assert(#descendants==#queue-1,"Map hierarchy changed; retry cloning")
            for _,item in ipairs(descendants) do
                assert(parents[item] and item.Parent==parents[item],"Map hierarchy changed; retry cloning")
            end
        end
        local ok,err=xpcall(function()
            for index,item in ipairs(queue) do
                self:Check(token,deadline)
                assert(live.Parent==liveParent,"Live map changed during clone preparation")
                assert(item.Parent==parents[item],"Map hierarchy changed; retry cloning")
                for _,connection in ipairs(getconnections(item:GetPropertyChangedSignal("Archivable"))) do
                    if connection.Enabled~=false then
                        assert(type(connection.Disable)=="function" and type(connection.Enable)=="function",
                            "Reversible signal disabling is required")
                        table.insert(connections,connection)
                        connection:Disable()
                    end
                end
                changed[item]=item.Archivable
                item.Archivable=true
                if index%config.BatchSize==0 then RS.Heartbeat:Wait() end
            end
            -- A changing hierarchy cannot be cloned consistently; retry once the map is quiet.
            validate()
            tag="TomatoTAS_"..game:GetService("HttpService"):GenerateGUID(false)
            spawn:SetAttribute(tag,true)
            clone=live:Clone()
            assert(clone,"Clone failed")
            for _,item in ipairs(clone:GetDescendants()) do
                if item:GetAttribute(tag) then cloneSpawn=item; item:SetAttribute(tag,nil) end
                if item:IsA("BaseScript") then item.Disabled=true end
            end
            assert(cloneSpawn,"Cloned spawn missing")
        end,debug.traceback)
        local cleanupErrors={}
        local function cleanup(fn)
            local restored,restoreError=pcall(fn)
            if not restored then table.insert(cleanupErrors,tostring(restoreError)) end
        end
        if tag then cleanup(function() spawn:SetAttribute(tag,nil) end) end
        -- Restore Archivable while listeners are still disabled.
        for item,value in pairs(changed) do cleanup(function() item.Archivable=value end) end
        for _,connection in ipairs(connections) do cleanup(function() connection:Enable() end) end
        if ok and #cleanupErrors==0 then
            ok,err=xpcall(function()
                validate()
                clone.Name="TomatoTAS_Sandbox"
                -- Preserve world coordinates so cached rope positions remain valid.
                -- Both reparentings are transactional: neither failure strands the live map.
                live.Parent=Storage
                clone.Parent=workspace
                self.liveParent,self.clone,self.cloneSpawn=liveParent,clone,cloneSpawn
                self.offset,self.origin=offset,cloneSpawn.CFrame
            end,debug.traceback)
        end
        if not ok or #cleanupErrors>0 then
            if live.Parent==Storage then cleanup(function() live.Parent=liveParent end) end
            if clone then cleanup(function() clone:Destroy() end) end
            if #cleanupErrors>0 then warn("[TomatoTAS] Clone cleanup: "..table.concat(cleanupErrors,"; ")) end
            error(err or "Clone preparation could not restore the source map")
        end
        return clone
    end
    function Map:Respawn()
        assert(self.clone,"Clone first")
        self.sandboxCharacter=nil
        local token=self.generation
        self:Check(token,os.clock()+config.Timeout)
        local clone,spawn,offset=self.clone,self.cloneSpawn,self.offset
        assert(clone.Parent and spawn and spawn.Parent,"Sandbox was removed")
        local old=Players.LocalPlayer.Character
        local h=old and old:FindFirstChildOfClass("Humanoid")
        assert(h,"Character unavailable")
        h.Health=0
        local c=self:Wait(function()
            local nextCharacter=Players.LocalPlayer.Character
            local humanoid=nextCharacter and nextCharacter:FindFirstChildOfClass("Humanoid")
            if nextCharacter and nextCharacter~=old and nextCharacter:FindFirstChild("HumanoidRootPart")
                and humanoid and humanoid.Health>0 then return nextCharacter end
            return nil
        end,token,"Timed out waiting for a new living character. Respawn and retry sandbox respawn.")
        local remote=Storage:FindFirstChild("Remote")
        if remote and remote:FindFirstChild("RemoveWaiting") then remote.RemoveWaiting:FireServer() end
        self:RestoreRopes(c)
        self:Wait(function()
            assert(self:LivingCharacter()==c,"Character changed during sandbox respawn")
            return not c:FindFirstChild("HumanoidRootPart").Anchored
        end,token,"Timed out waiting for FE2 to release the respawned character. Leave the waiting area and retry sandbox respawn.")
        self:Settle(spawn,token)
        assert(self:LivingCharacter()==c,
            "Character changed during sandbox respawn")
        assert(self.clone==clone and clone.Parent and spawn:IsDescendantOf(clone),"Sandbox was removed during respawn")
        local root=c:FindFirstChild("HumanoidRootPart")
        root.CFrame=spawn.CFrame*offset
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        self.sandboxCharacter=c
        return c
    end
    function Map:CommitSandbox()
        assert(not self.scope.dead,"Map operation cancelled")
        assert(self.clone and self.clone.Parent==workspace and self.cloneSpawn
            and self.cloneSpawn:IsDescendantOf(self.clone),"Sandbox was removed before setup completed")
        if self.sandboxCommitted then return self.clone end
        assert(self.sandboxCharacter and self:LivingCharacter()==self.sandboxCharacter,
            "Finish sandbox respawn before removing the source map")
        -- Keep the source recoverable until the caller has successfully respawned
        -- and attached to the sandbox character. Only then is it disposable.
        local live=assert(self.live,"Sandbox source map unavailable")
        live:Destroy()
        self.live,self.liveParent,self.spawn=nil,nil,nil
        self.sandboxCommitted=true
        return self.clone
    end
    function Map:SetRecording(active)
        if not active then
            self.recording=false
            if self.recordingScope then self.recordingScope:Destroy(); self.recordingScope=nil end
            return
        end
        assert(not self.scope.dead,"Map operation cancelled")
        -- Live recording keeps the server's map. Only a completed sandbox owns
        -- the local removal policy for subsequently replicated rounds.
        if not self.clone then self:SetRecording(false); return end
        assert(self.sandboxCommitted,"Complete sandbox setup before recording")
        local reason=self:ReadyReason()
        assert(not reason,reason)
        if self.recordingScope then return end
        local recordingScope=Scope.new()
        self.recording,self.recordingScope=true,recordingScope
        local multiplayer,containerScope
        local function guarded(fn)
            return function(...)
                if recordingScope.dead then return end
                local ok,err=xpcall(fn,debug.traceback,...)
                if not ok then
                    self:SetRecording(false)
                    warn("[TomatoTAS] Incoming map cleanup stopped: "..tostring(err))
                end
            end
        end
        local function allowed()
            return not recordingScope.dead and self.recording and not self.scope.dead
                and self.clone and self.clone.Parent==workspace and self.cloneSpawn
                and self.cloneSpawn:IsDescendantOf(self.clone)
        end
        local function refresh()
            if not allowed() then return end
            local current=workspace:FindFirstChild("Multiplayer")
            if current==multiplayer then return end
            if containerScope then containerScope:Destroy(); containerScope=nil end
            multiplayer=current
            if not current then return end
            containerScope=Scope.new()
            local children={}
            containerScope:Add(function()
                for _,scope in pairs(children) do scope:Destroy() end
                table.clear(children)
            end)
            local function remove(child)
                if allowed() and workspace:FindFirstChild("Multiplayer")==current and child.Parent==current
                    and child~=self.clone and child:IsA("Model") and (child.Name=="Map" or child.Name=="NewMap") then
                    child:Destroy()
                end
            end
            local function watch(child)
                if not child:IsA("Model") or children[child] then return end
                local scope=Scope.new()
                children[child]=scope
                scope:Add(child:GetPropertyChangedSignal("Name"):Connect(guarded(function() remove(child) end)))
                remove(child)
            end
            containerScope:Add(current.ChildAdded:Connect(guarded(watch)))
            containerScope:Add(current.ChildRemoved:Connect(guarded(function(child)
                if children[child] then children[child]:Destroy(); children[child]=nil end
            end)))
            containerScope:Add(current:GetPropertyChangedSignal("Name"):Connect(guarded(refresh)))
            -- Subscribe before enumerating so maps arriving during setup are covered.
            for _,child in ipairs(current:GetChildren()) do watch(child) end
        end
        recordingScope:Add(function() if containerScope then containerScope:Destroy() end end)
        local ok,err=xpcall(function()
            recordingScope:Add(workspace.ChildAdded:Connect(guarded(refresh)))
            recordingScope:Add(workspace.ChildRemoved:Connect(guarded(refresh)))
            refresh()
        end,debug.traceback)
        if not ok then self:SetRecording(false); error(err) end
    end
    function Map:Destroy()
        self.generation+=1
        self:SetRecording(false)
        self.scope:Destroy()
        if self.clone then
            local ok,err=pcall(function() self.clone:Destroy() end)
            if ok then self.clone=nil; self.cloneSpawn=nil
            else warn("[TomatoTAS] Sandbox cleanup: "..tostring(err)) end
        end
        if self.liveParent and self.live and self.live.Parent==Storage then
            local ok,err=pcall(function() self.live.Parent=self.liveParent end)
            if ok then self.liveParent=nil
            else warn("[TomatoTAS] Live map restore: "..tostring(err)) end
        end
        self.ropes=nil
        self.sandboxCharacter=nil
        table.clear(self.ropeCache)
    end
    return Map
end
