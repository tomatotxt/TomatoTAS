return function(import,config)
    local Scope=import("core/Scope")
    local RS=game:GetService("RunService")
    local Players=game:GetService("Players")
    local Storage=game:GetService("ReplicatedStorage")
    local Map={}
    Map.__index=Map
    function Map.new()
        local self=setmetatable({scope=Scope.new(),generation=0},Map)
        local remote=Storage:FindFirstChild("Remote")
        local rope=remote and remote:FindFirstChild("UpdRopeData")
        if rope then
            self.scope:Add(rope.OnClientEvent:Connect(function(data)
                if type(data)=="table" then
                    self.ropes=data
                    local multiplayer=workspace:FindFirstChild("Multiplayer")
                    self.ropeMap=multiplayer and (multiplayer:FindFirstChild("NewMap") or multiplayer:FindFirstChild("Map"))
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
        self.generation+=1
        local token=self.generation
        local multiplayer=assert(workspace:FindFirstChild("Multiplayer"),"FE2 Multiplayer container missing")
        local live=multiplayer:FindFirstChild("Map")
        if not live then
            -- Subscribe before checking again so arrival and rename cannot be missed.
            local watch=Scope.new()
            local function inspect(model)
                if model.Name=="Map" then live=model
                elseif model.Name=="NewMap" then
                    watch:Add(model:GetPropertyChangedSignal("Name"):Connect(function()
                        if model.Name=="Map" then live=model end
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
        if self.ropeMap~=live then
            self.ropes=nil
            -- Joining mid-round can miss the remote. Recover only the table already
            -- installed in this character's documented FE2 closure.
            local scriptObject=character:FindFirstChild("FE2_Character")
            if scriptObject then
                local ok,data=pcall(function()
                    local fn=getsenv(scriptObject).startZipline
                    return type(fn)=="function" and getupvalue(fn,2) or nil
                end)
                if ok and type(data)=="table" then self.ropes=data; self.ropeMap=live end
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
            local current=spawn.CFrame
            local _,angle=anchor:ToObjectSpace(current):ToAxisAngle()
            if (current.Position-anchor.Position).Magnitude>=0.005 or math.abs(angle)>0.0001 then
                anchor=current; since=os.clock()
            end
        end
        self:Check(token,deadline)
    end
    function Map:RestoreRopes(character,quiet)
        if not self.ropes then
            if not quiet then warn("[TomatoTAS] No zipline data available. Join a new round before cloning for zipline support.") end
            return
        end
        local scriptObject=if quiet then character:FindFirstChild("FE2_Character") else character:WaitForChild("FE2_Character",10)
        if quiet and not scriptObject then return end
        assert(scriptObject,"FE2_Character missing after respawn")
        local env=getsenv(scriptObject)
        if quiet and type(env.startZipline)~="function" then return end
        assert(type(env.startZipline)=="function","startZipline closure unavailable")
        local current=getupvalue(env.startZipline,2)
        assert(current==nil or type(current)=="table","Zipline upvalue layout changed; refusing to overwrite")
        setupvalue(env.startZipline,2,self.ropes)
        assert(getupvalue(env.startZipline,2)==self.ropes,"Zipline table restore failed")
    end
    function Map:Clone()
        assert(self.live and self.live.Parent,"Prepare a live map first")
        assert(not self.clone,"Clone already prepared")
        local token=self.generation
        local deadline=os.clock()+config.Timeout
        self:Settle(self.spawn,token)
        local character=Players.LocalPlayer.Character
        assert(character and character:FindFirstChild("HumanoidRootPart"),"Character unavailable")
        self.offset=self.spawn.CFrame:ToObjectSpace(character.HumanoidRootPart.CFrame)
        local queue={self.live}
        for _,item in ipairs(self.live:GetDescendants()) do table.insert(queue,item) end
        local changed,connections={},{}
        local clone
        local ok,err=xpcall(function()
            for index,item in ipairs(queue) do
                self:Check(token,deadline)
                assert(self.live.Parent,"Live map removed during clone preparation")
                if item.Parent then
                    for _,connection in ipairs(getconnections(item:GetPropertyChangedSignal("Archivable"))) do
                        if connection.Enabled~=false then
                            assert(type(connection.Disable)=="function" and type(connection.Enable)=="function",
                                "Reversible signal disabling is required")
                            connection:Disable(); table.insert(connections,connection)
                        end
                    end
                    changed[item]=item.Archivable
                    item.Archivable=true
                end
                if index%config.BatchSize==0 then RS.Heartbeat:Wait() end
            end
            -- A changing hierarchy cannot be cloned consistently; retry once the map is quiet.
            self:Check(token,deadline)
            assert(#self.live:GetDescendants()==#queue-1,"Map hierarchy changed; retry cloning")
            local tag="TomatoTAS_"..game:GetService("HttpService"):GenerateGUID(false)
            self.spawn:SetAttribute(tag,true)
            local copied,copyError=pcall(function() clone=self.live:Clone() end)
            self.spawn:SetAttribute(tag,nil)
            assert(copied,copyError)
            assert(clone,"Clone failed")
            for _,item in ipairs(clone:GetDescendants()) do
                if item:GetAttribute(tag) then self.cloneSpawn=item; item:SetAttribute(tag,nil) end
                if item:IsA("BaseScript") then item.Disabled=true end
            end
            assert(self.cloneSpawn,"Cloned spawn missing")
        end,debug.traceback)
        -- Restore Archivable while listeners are still disabled.
        for item,value in pairs(changed) do pcall(function() item.Archivable=value end) end
        for _,connection in ipairs(connections) do pcall(function() connection:Enable() end) end
        if not ok then if clone then clone:Destroy() end; error(err) end
        clone.Name="TomatoTAS_Sandbox"
        -- Preserve world coordinates so cached rope positions remain valid. The live
        -- map is moved locally into storage until the sandbox is destroyed.
        self.liveParent=self.live.Parent
        self.live.Parent=Storage
        clone.Parent=workspace
        self.clone=clone
        self.origin=self.cloneSpawn.CFrame
        return clone
    end
    function Map:Respawn()
        assert(self.clone,"Clone first")
        local token=self.generation
        local old=Players.LocalPlayer.Character
        local h=old and old:FindFirstChildOfClass("Humanoid")
        assert(h,"Character unavailable")
        h.Health=0
        local c=self:Wait(function()
            local nextCharacter=Players.LocalPlayer.Character
            if nextCharacter and nextCharacter~=old and nextCharacter:FindFirstChild("HumanoidRootPart")
                and nextCharacter:FindFirstChildOfClass("Humanoid") then return nextCharacter end
            return nil
        end,token)
        local remote=Storage:FindFirstChild("Remote")
        if remote and remote:FindFirstChild("RemoveWaiting") then remote.RemoveWaiting:FireServer() end
        self:RestoreRopes(c)
        self:Settle(self.cloneSpawn,token)
        c.HumanoidRootPart.CFrame=self.cloneSpawn.CFrame*self.offset
        c.HumanoidRootPart.AssemblyLinearVelocity=Vector3.zero
        c.HumanoidRootPart.AssemblyAngularVelocity=Vector3.zero
        return c
    end
    function Map:Destroy()
        self.generation+=1
        self.scope:Destroy()
        if self.clone then self.clone:Destroy(); self.clone=nil end
        if self.liveParent and self.live and self.live.Parent==Storage then
            pcall(function() self.live.Parent=self.liveParent end)
        end
    end
    return Map
end
