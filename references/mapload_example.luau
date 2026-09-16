--[[
    FE2 TAS - Map Cloner & Dynamic Spawn Settle Engine
    
    Features:
    - Event-driven map acquisition (NewMap -> Map)
    - Connection-stripper clone fix (bypasses Archivable integrity crash without FPS drop)
    - In-game verification (ensures player is out of lobby bounds)
    - Dynamic Spawn Stabilization: Waits until spawn platform position is static for 1.0s
    - Sub-stud CFrame offset calculation recorded at rest
    - Clean map cloning, Highlight adornment, character reset, and precision teleport
]]

-- // SERVICES //
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Multiplayer = Workspace:WaitForChild("Multiplayer")
local LobbyLiftPos = Vector3.new(-25, -144, 139)

-- // 1. BATCH CONNECTION-STRIPPER (CLONE FIX) //
local BatchSize = 100
local Queue = {}
local QueueIndex = 1
local Queued = {}

local function QueueInstance(Inst)
    if Queued[Inst] then return end
    Queued[Inst] = true
    table.insert(Queue, Inst)
end

local function RemoveCheck(Inst)
    if not Inst.Parent then return end

    local Success, Connections = pcall(function()
        return getconnections(Inst:GetPropertyChangedSignal("Archivable"))
    end)

    if Success and Connections then
        for _, Connection in ipairs(Connections) do
            pcall(function()
                if Connection.Disable then
                    Connection:Disable()
                elseif Connection.Disconnect then
                    Connection:Disconnect()
                end
            end)
        end
    end

    pcall(function()
        Inst.Archivable = true
    end)
end

local DescendantConnection = Multiplayer.DescendantAdded:Connect(QueueInstance)
for _, Descendant in ipairs(Multiplayer:GetDescendants()) do
    QueueInstance(Descendant)
end

local HeartbeatConnection
HeartbeatConnection = RunService.Heartbeat:Connect(function()
    local totalInQueue = #Queue
    if totalInQueue == 0 then return end

    local Processed = 0
    while Processed < BatchSize and QueueIndex <= totalInQueue do
        local Inst = Queue[QueueIndex]
        QueueIndex += 1
        Processed += 1

        if Inst then
            Queued[Inst] = nil
            RemoveCheck(Inst)
        end
    end

    if QueueIndex > totalInQueue then
        Queue = {}
        QueueIndex = 1
    end
end)

local function FlushQueueSynchronous(targetModel)
    for _, desc in ipairs(targetModel:GetDescendants()) do
        RemoveCheck(desc)
    end
    RemoveCheck(targetModel)
end

print("[TAS Engine] Archivable connection-stripper initialized.")

-- // 2. EVENT-DRIVEN MAP LIFECYCLE HANDSHAKE //
print("[TAS Engine] Monitoring for incoming map container ('NewMap')...")

local liveMap = Multiplayer:WaitForChild("NewMap", 9999)

-- Yield cleanly on the engine event until the server completes loading and renames to "Map"
if liveMap.Name ~= "Map" then
    print("[TAS Engine] 'NewMap' received. Waiting for server loading completion ('Map')...")
    repeat
        liveMap:GetPropertyChangedSignal("Name"):Wait()
    until liveMap.Name == "Map"
end

print("[TAS Engine] Map initialized and fully renamed to: " .. liveMap.Name)

-- // 3. VERIFY PHYSICAL IN-GAME PRESENCE //
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart", 10)
local humanoid = character:WaitForChild("Humanoid", 10)

print("[TAS Engine] Awaiting player teleportation into map...")
while true do
    local distFromLobby = (rootPart.Position - LobbyLiftPos).Magnitude
    
    -- Ensure player is far from lobby bounds and actively in play
    if distFromLobby > 300 and not rootPart.Anchored and humanoid.WalkSpeed >= 20 then
        break
    end
    
    task.wait(0.1)
    character = LocalPlayer.Character or character
    rootPart = character:FindFirstChild("HumanoidRootPart") or rootPart
    humanoid = character:FindFirstChild("Humanoid") or humanoid
end

print("[TAS Engine] Player verified inside map bounds.")

-- // 4. SPAWN RESOLUTION //
local function ResolveSpawn(mapModel, playerRoot)
    local namedSpawn = mapModel:FindFirstChild("Spawn", true)
    if namedSpawn and namedSpawn:IsA("BasePart") then
        if (playerRoot.Position - namedSpawn.Position).Magnitude < 60 then
            return namedSpawn
        end
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances = { mapModel }
    
    local hit = Workspace:Raycast(playerRoot.Position, Vector3.new(0, -25, 0), rayParams)
    if hit and hit.Instance and hit.Instance:IsA("BasePart") then
        return hit.Instance
    end

    local closestPart = nil
    local minDistance = math.huge
    for _, part in ipairs(mapModel:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            local dist = (playerRoot.Position - part.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                closestPart = part
            end
        end
    end
    return closestPart
end

local liveSpawn = ResolveSpawn(liveMap, rootPart)
assert(liveSpawn, "[TAS Engine] Fatal: Could not resolve spawn part under player.")
print("[TAS Engine] Target Spawn detected: " .. liveSpawn:GetFullName())

-- // 5. SPAWN STABILIZATION WATCHER (1-SECOND SETTLE) //
print("[TAS Engine] Checking spawn stability (waiting for motion to settle for 1.0s)...")

local function WaitForSpawnToSettle(spawnPart)
    local SETTLE_THRESHOLD = 1.0 -- Must remain stationary for 1 full second
    local EPSILON = 0.005        -- Ignore sub-microscopic physics noise
    
    local lastPosition = spawnPart.Position
    local timeAtRest = 0
    local lastTick = os.clock()
    
    while timeAtRest < SETTLE_THRESHOLD do
        RunService.Heartbeat:Wait()
        
        local currentTick = os.clock()
        local dt = currentTick - lastTick
        lastTick = currentTick
        
        local currentPosition = spawnPart.Position
        local deltaDist = (currentPosition - lastPosition).Magnitude
        
        if deltaDist > EPSILON then
            -- Position changed; reset the rest timer
            if timeAtRest > 0.1 then
                print(string.format("[TAS Engine] Spawn moved (Δ: %.3f studs). Resetting settle timer.", deltaDist))
            end
            timeAtRest = 0
            lastPosition = currentPosition
        else
            -- Position static; increment the accumulation timer
            timeAtRest += dt
        end
    end
end

WaitForSpawnToSettle(liveSpawn)
print("[TAS Engine] Spawn part has been completely stationary for 1.0s.")

-- // 6. CAPTURE STABILIZED SUB-STUD OFFSET //
-- Now that the spawn is guaranteed to be at rest, record the exact offset
character = LocalPlayer.Character or character
rootPart = character:WaitForChild("HumanoidRootPart", 5)

local spawnOffsetCFrame = liveSpawn.CFrame:ToObjectSpace(rootPart.CFrame)
local relativeOffsetPos = rootPart.Position - liveSpawn.Position

print(string.format(
    "[TAS Engine] Final Spawn Offset Locked:\n" ..
    " > (X: %.4f, Y: %.4f, Z: %.4f)",
    relativeOffsetPos.X, relativeOffsetPos.Y, relativeOffsetPos.Z
))

-- Tag live spawn so the clone can instantly identify it
liveSpawn:SetAttribute("TAS_TargetSpawn", true)

-- // 7. CLONE MAP HIERARCHY //
print("[TAS Engine] Stripping remaining checks and cloning map...")
FlushQueueSynchronous(liveMap)

liveMap.Archivable = true
local clonedMap = liveMap:Clone()
clonedMap.Name = "ClonedMap_" .. liveMap.Name
liveSpawn:SetAttribute("TAS_TargetSpawn", nil)

clonedMap.Parent = Workspace
print("[TAS Engine] Cloned map parented to Workspace.")

local clonedSpawn = nil
for _, part in ipairs(clonedMap:GetDescendants()) do
    if part:GetAttribute("TAS_TargetSpawn") == true then
        clonedSpawn = part
        part:SetAttribute("TAS_TargetSpawn", nil)
        break
    end
end
assert(clonedSpawn, "[TAS Engine] Fatal: Failed to resolve spawn in cloned map.")

-- // 8. HIGHLIGHT SPAWN PART //
local highlight = Instance.new("Highlight")
highlight.Name = "TAS_SpawnHighlight"
highlight.Adornee = clonedSpawn
highlight.FillColor = Color3.fromRGB(0, 255, 170)
highlight.FillTransparency = 0.3
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0
highlight.Parent = clonedSpawn

-- // 9. RESET CHARACTER & TELEPORT //
print("[TAS Engine] Resetting character...")
humanoid:ChangeState(Enum.HumanoidStateType.Dead)
humanoid.Health = 0

local newCharacter = LocalPlayer.CharacterAdded:Wait()
local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)

-- Clean up batch workers now that cloning is complete
if HeartbeatConnection then HeartbeatConnection:Disconnect() end
if DescendantConnection then DescendantConnection:Disconnect() end

pcall(function()
    ReplicatedStorage.Remote.RemoveWaiting:FireServer()
end)

task.wait(0.2)

-- Apply offset to the settled spawn position in the cloned map
local targetCFrame = clonedSpawn.CFrame * spawnOffsetCFrame

newRoot.AssemblyLinearVelocity = Vector3.zero
newRoot.AssemblyAngularVelocity = Vector3.zero
newRoot.CFrame = targetCFrame

print("[TAS Engine] Successfully teleported player to cloned spawn with stabilized offset.")