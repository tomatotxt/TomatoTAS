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
    function Map:Check(token,deadline)
        assert(not self.scope.dead and self.generation==token,"Map operation cancelled")
        assert(os.clock()<deadline,"Map operation timed out")
    end
    function Map:Wait(predicate,token)
        local deadline=os.clock()+config.Timeout
        repeat
            self:Check(token,deadline)
            local result=predicate()
            if result then return result end
            RS.Heartbeat:Wait()
        until false
    end
    function Map:Acquire()
        assert(not self.scope.dead,"Map operation cancelled")
        assert(not self.clone,"Destroy the sandbox before acquiring another map")
        self.generation+=1
        local token=self.generation
        local multiplayer=assert(workspace:FindFirstChild("Multiplayer"),"FE2 Multiplayer container missing")
        local live=multiplayer:FindFirstChild("Map")
        if not live then
            -- Subscribe before checking again so arrival and rename cannot be missed.
            local watch=Scope.new()
            local function inspect(model)
                if model.Name=="Map" and model.Parent==multiplayer then live=model
                elseif model.Name=="NewMap" then
                    watch:Add(model:GetPropertyChangedSignal("Name"):Connect(function()
                        if model.Name=="Map" and model.Parent==multiplayer then live=model end
                    end))
                end
            end
            watch:Add(multiplayer.ChildAdded:Connect(inspect))
            for _,model in ipairs(multiplayer:GetChildren()) do inspect(model) end
            local ok,err=pcall(function() self:Wait(function() return live end,token) end)
            watch:Destroy()
            assert(ok,err)
        end
        local character=self:Wait(function()
            local c=Players.LocalPlayer.Character
            local r=c and c:FindFirstChild("HumanoidRootPart")
            local h=c and c:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health>0 and not r.Anchored and h.WalkSpeed>=20
                and (r.Position-Vector3.new(-25,-144,139)).Magnitude>300 then return c end
            return nil
        end,token)
        assert(live.Parent==multiplayer,"Map was removed during acquisition")
        local root=character.HumanoidRootPart
        local spawn=live:FindFirstChild("Spawn",true)
        if not (spawn and spawn:IsA("BasePart") and (spawn.Position-root.Position).Magnitude<60) then
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances={live}
            local result=workspace:Raycast(root.Position,Vector3.new(0,-25,0),params)
            spawn=result and result.Instance
        end
        assert(spawn and spawn:IsA("BasePart"),"No spawn beneath character; stand on spawn and retry")
        self:Settle(spawn,token)
        assert(Players.LocalPlayer.Character==character and live.Parent==multiplayer,"Character/map changed during settling")
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
        return self
    end
    function Map:Settle(spawn,token)
        token=token or self.generation
        local deadline=os.clock()+config.Timeout
        local anchor=spawn.CFrame
        local since=os.clock()
        while os.clock()-since<1 do
            self:Check(token,deadline)
            assert(spawn.Parent,"Spawn removed while settling")
            RS.Heartbeat:Wait()
            self:Check(token,deadline)
            assert(spawn.Parent,"Spawn removed while settling")
            local current=spawn.CFrame
            local _,angle=anchor:ToObjectSpace(current):ToAxisAngle()
            if (current.Position-anchor.Position).Magnitude>=0.005 or math.abs(angle)>0.0001 then
                anchor=current; since=os.clock()
            end
        end
        self:Check(token,deadline)
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
        local fn=if quiet then closure() else self:Wait(closure,token)
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
        local character=Players.LocalPlayer.Character
        assert(character and character:FindFirstChild("HumanoidRootPart"),"Character unavailable")
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
        end,token)
        local remote=Storage:FindFirstChild("Remote")
        if remote and remote:FindFirstChild("RemoveWaiting") then remote.RemoveWaiting:FireServer() end
        self:RestoreRopes(c)
        self:Settle(spawn,token)
        assert(Players.LocalPlayer.Character==c and c:FindFirstChildOfClass("Humanoid").Health>0,
            "Character changed during sandbox respawn")
        assert(self.clone==clone and clone.Parent and spawn.Parent,"Sandbox was removed during respawn")
        c.HumanoidRootPart.CFrame=spawn.CFrame*offset
        c.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
        c.HumanoidRootPart.AssemblyAngularVelocity=Vector3.zero
        return c
    end
    function Map:Destroy()
        self.generation+=1
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
        table.clear(self.ropeCache)
    end
    return Map
end
