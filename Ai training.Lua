--====================================================
-- AI TRAINING - 100 GOALS (ENHANCED VERSION)
--====================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
local GOAL_TIMEOUT = 78

--====================================================
-- PERSISTENT STATS
--====================================================
local stats = {
	score = 0,
	goalsCollected = 0,
	totalGoals = 100,
	startTime = tick(),
	goalSpawnTime = tick(),
	deaths = 0,
	avgTimePerGoal = 0
}

--====================================================
-- ENHANCED LEARNING SYSTEM
--====================================================
local dangerZones = {}
local pathMemory = {}
local successfulPaths = {} -- NEW: Track successful routes
local currentGoalID = 0
local MAX_DANGER_HISTORY = 50 -- Limit memory size

local function recordDeath(position, goalPosition)
	table.insert(dangerZones, {
		pos = position,
		goal = goalPosition,
		time = tick(),
		severity = 1 -- Can be increased for repeated deaths in same area
	})
	
	-- Limit danger zone memory
	if #dangerZones > MAX_DANGER_HISTORY then
		table.remove(dangerZones, 1)
	end
	
	if not pathMemory[currentGoalID] then
		pathMemory[currentGoalID] = {}
	end
	table.insert(pathMemory[currentGoalID], {
		deathPos = position,
		direction = (goalPosition - position).Unit
	})
	
	print("💀 Death recorded at", position)
end

local function recordSuccess(startPos, goalPos)
	-- NEW: Learn from successful paths
	table.insert(successfulPaths, {
		start = startPos,
		goal = goalPos,
		time = tick()
	})
	
	if #successfulPaths > 30 then
		table.remove(successfulPaths, 1)
	end
end

local function isDangerousPath(startPos, targetPos)
	local dangerScore = 0
	
	-- Check recent deaths
	for i = #dangerZones, math.max(1, #dangerZones - 20), -1 do
		local zone = dangerZones[i]
		local distToZone = (startPos - zone.pos).Magnitude
		
		if distToZone < 12 then
			local ageMultiplier = math.max(0.3, 1 - (tick() - zone.time) / 300)
			dangerScore = dangerScore + (zone.severity or 1) * ageMultiplier
		end
	end
	
	-- Check path memory
	for goalID, failures in pairs(pathMemory) do
		for _, failure in ipairs(failures) do
			local currentDir = (targetPos - startPos).Unit
			local failureDir = failure.direction
			
			if currentDir:Dot(failureDir) > 0.8 then
				local distToDeath = (startPos - failure.deathPos).Magnitude
				if distToDeath < 15 then
					dangerScore = dangerScore + 2
				end
			end
		end
	end
	
	return dangerScore > 1, dangerScore
end

local function hasSuccessfulRoute(startPos, goalPos)
	-- NEW: Check if we've successfully navigated similar routes
	for _, path in ipairs(successfulPaths) do
		local startSimilarity = (startPos - path.start).Magnitude
		local goalSimilarity = (goalPos - path.goal).Magnitude
		
		if startSimilarity < 20 and goalSimilarity < 20 then
			return true, (path.goal - path.start).Unit
		end
	end
	return false, nil
end

--====================================================
-- ENHANCED PATHFINDING SYSTEM
--====================================================
local currentPath = nil
local pathUpdateCooldown = 0
local PATH_UPDATE_INTERVAL = 1.5 -- Faster updates
local lastPathPosition = nil

local function getPathHint(startPos, goalPos)
	if not currentPath then return nil, 0 end
	
	local waypoints = currentPath:GetWaypoints()
	if #waypoints < 2 then return nil, 0 end
	
	-- Find the optimal waypoint to target
	local bestWaypoint = nil
	local bestDist = math.huge
	local waypointIndex = 1
	
	for i = 2, math.min(#waypoints, 8) do -- Look further ahead
		local wp = waypoints[i]
		local dist = (wp.Position - startPos).Magnitude
		
		-- Prefer waypoints that are 5-15 units ahead
		if dist > 5 and dist < 15 and dist < bestDist then
			bestDist = dist
			bestWaypoint = wp.Position
			waypointIndex = i
		end
	end
	
	if bestWaypoint then
		local direction = (bestWaypoint - startPos).Unit
		local confidence = math.clamp(1 - (bestDist / 20), 0, 1)
		return direction, confidence
	end
	
	return nil, 0
end

local function updatePathHint(startPos, goalPos)
	-- Only update if we've moved significantly
	if lastPathPosition and (startPos - lastPathPosition).Magnitude < 8 then
		return
	end
	
	lastPathPosition = startPos
	
	task.spawn(function()
		local success, path = pcall(function()
			return PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				WaypointSpacing = 3, -- More granular waypoints
				Costs = {
					Water = math.huge,
					Danger = math.huge
				}
			})
		end)
		
		if success then
			local computeSuccess = pcall(function()
				path:ComputeAsync(startPos, goalPos)
			end)
			
			if computeSuccess and path.Status == Enum.PathStatus.Success then
				currentPath = path
			else
				currentPath = nil
			end
		end
	end)
end

--====================================================
-- UI SETUP
--====================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AITrainingUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local function createLabel(text, position, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 300, 0, 40)
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.TextSize = 20
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = screenGui
	return label
end

local scoreLabel = createLabel("Score: 0", UDim2.new(0, 10, 0, 10))
local goalsLabel = createLabel("Goals: 0/100", UDim2.new(0, 10, 0, 60))
local timeLabel = createLabel("Time: 0s", UDim2.new(0, 10, 0, 110))
local deathLabel = createLabel("Deaths: 0", UDim2.new(0, 10, 0, 160))
local timerLabel = createLabel("Goal Timer: 78s", UDim2.new(0, 10, 0, 210), Color3.fromRGB(255, 255, 100))
local avgLabel = createLabel("Avg: 0s/goal", UDim2.new(0, 10, 0, 260), Color3.fromRGB(150, 255, 150))

local popup = Instance.new("TextLabel")
popup.Size = UDim2.new(0, 400, 0, 50)
popup.Position = UDim2.new(0.5, -200, 0.2, 0)
popup.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
popup.TextColor3 = Color3.fromRGB(255, 255, 255)
popup.TextSize = 22
popup.Font = Enum.Font.GothamBlack
popup.Text = "REROUTING..."
popup.Visible = false
popup.Parent = screenGui
Instance.new("UICorner", popup)

local function showPopup(text, duration, color)
	popup.Text = text
	popup.BackgroundColor3 = color or Color3.fromRGB(200, 0, 0)
	popup.Visible = true
	task.delay(duration, function() popup.Visible = false end)
end

task.spawn(function()
	while true do
		local elapsed = math.floor(tick() - stats.startTime)
		timeLabel.Text = "Time: " .. elapsed .. "s"
		
		if stats.goalsCollected > 0 then
			stats.avgTimePerGoal = elapsed / stats.goalsCollected
			avgLabel.Text = string.format("Avg: %.1fs/goal", stats.avgTimePerGoal)
		end
		
		task.wait(1)
	end
end)

--====================================================
-- GOAL MANAGEMENT
--====================================================
local goalFolder = Instance.new("Folder")
goalFolder.Name = "AIGoals"
goalFolder.Parent = workspace

local currentGoal = nil
local goalStartTime = 0

local function spawnNextGoal()
	stats.goalSpawnTime = tick()
	goalStartTime = tick()
	currentPath = nil
	lastPathPosition = nil
	
	if stats.goalsCollected >= stats.totalGoals then
		timeLabel.Text = "🏆 FINAL TIME: " .. (math.floor(tick() - stats.startTime)) .. "s"
		task.wait(1)
		player:Kick("Training Complete! Goals: 100 | Deaths: " .. stats.deaths .. " | Time: " .. (math.floor(tick() - stats.startTime)) .. "s")
		return
	end

	currentGoalID = currentGoalID + 1
	goalFolder:ClearAllChildren()
	
	local p = Instance.new("Part")
	p.Name = "Goal"
	p.Size = Vector3.new(4, 4, 4)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(0, 255, 0)
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 0.2
	
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = root and root.Position or Vector3.new(0, 10, 0)
	
	local rayResult = nil
	local finalPos = nil
	local attempts = 0
	local maxAttempts = 20

	repeat
		attempts = attempts + 1
		local angle = math.random() * 2 * math.pi
		local distance = math.random(35, 110) -- Slightly adjusted range
		local searchPos = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {player.Character, goalFolder}
		params.FilterType = Enum.RaycastFilterType.Exclude
		
		rayResult = workspace:Raycast(searchPos + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), params)
		
		if rayResult then
			finalPos = rayResult.Position + Vector3.new(0, 2, 0)
			
			-- Avoid spawning in known danger zones
			local isDangerous = false
			for _, zone in ipairs(dangerZones) do
				if (finalPos - zone.pos).Magnitude < 15 then
					isDangerous = true
					break
				end
			end
			
			if isDangerous and attempts < maxAttempts then
				rayResult = nil -- Try again
			end
		end
		task.wait()
	until rayResult ~= nil or attempts >= maxAttempts

	p.Position = finalPos
	p.Parent = goalFolder
	
	currentGoal = p
	
	if root then
		updatePathHint(root.Position, finalPos)
	end
	
	local collected = false
	p.Touched:Connect(function(hit)
		if collected then return end
		local hitPlayer = Players:GetPlayerFromCharacter(hit.Parent)
		
		if hitPlayer == player then
			collected = true
			
			local goalTime = tick() - goalStartTime
			stats.goalsCollected += 1
			stats.score += math.max(5, 15 - math.floor(goalTime / 5)) -- Bonus for speed
			
			scoreLabel.Text = "Score: " .. stats.score
			goalsLabel.Text = "Goals: " .. stats.goalsCollected .. "/" .. stats.totalGoals
			
			if root then
				recordSuccess(root.Position, finalPos)
			end
			
			pathMemory[currentGoalID] = nil
			
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
			sound.Volume = 0.5
			sound.Parent = hit.Parent:FindFirstChild("HumanoidRootPart") or workspace
			sound:Play()
			Debris:AddItem(sound, 1)
			
			showPopup(string.format("GOAL! (+%d pts)", math.max(5, 15 - math.floor(goalTime / 5))), 1, Color3.fromRGB(0, 200, 0))
			p:Destroy()
			currentGoal = nil
			task.wait(0.1)
			spawnNextGoal()
		end
	end)
end

spawnNextGoal()

--====================================================
-- ENHANCED AI BRAIN (WITH VERTICALITY)
--====================================================
local RAY_DIST = 22 
local MOVE_FORCE = 28
local JUMP_COOLDOWN = 0.6 -- Increased slightly for stability
local lastJumpTime = 0

local function activateAI(character)
    local root = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    
    humanoid.WalkSpeed = 22
    
    -- Auto-jump when seated or swimming to avoid getting stuck
    humanoid.Seated:Connect(function(active)
        if active then humanoid.Jump = true end
    end)
    
    -- PHYSICS SETUP: 
    -- MaxForce Y is 0 so gravity still works (allows jumping)
    local bodyVel = Instance.new("BodyVelocity")
    bodyVel.MaxForce = Vector3.new(100000, 0, 100000) 
    bodyVel.P = 10000
    bodyVel.Parent = root
    
    local isAlive = true
    local stuckPos = root.Position
    local stuckTimer = 0
    local velocityHistory = {}
    
    humanoid.Died:Connect(function()
        isAlive = false
        stats.deaths += 1
        deathLabel.Text = "Deaths: " .. stats.deaths
        if currentGoal and currentGoal.Parent then
            recordDeath(root.Position, currentGoal.Position)
        end
    end)
    
    task.spawn(function()
        while isAlive and character.Parent do
            local dt = task.wait(0.04) 
            
            if not currentGoal or not currentGoal.Parent then
                bodyVel.Velocity = Vector3.zero
                continue
            end
            
            -- UI Updates
            local elapsed = tick() - stats.goalSpawnTime
            timerLabel.Text = "Goal Timer: " .. math.ceil(GOAL_TIMEOUT - elapsed) .. "s"
            
            if elapsed >= GOAL_TIMEOUT then
                showPopup("UNREACHABLE - REROUTING", 2, Color3.fromRGB(255, 150, 0))
                spawnNextGoal()
                continue
            end
            
            -- Pathfinding Updates
            pathUpdateCooldown = pathUpdateCooldown - dt
            if pathUpdateCooldown <= 0 then
                pathUpdateCooldown = PATH_UPDATE_INTERVAL
                updatePathHint(root.Position, currentGoal.Position)
            end
            
            -- STUCK DETECTION
            table.insert(velocityHistory, root.AssemblyLinearVelocity.Magnitude)
            if #velocityHistory > 10 then table.remove(velocityHistory, 1) end
            
            local avgVelocity = 0
            for _, v in ipairs(velocityHistory) do avgVelocity = avgVelocity + v end
            avgVelocity = avgVelocity / #velocityHistory
            
            if (root.Position - stuckPos).Magnitude < 1.5 or avgVelocity < 2 then
                stuckTimer = stuckTimer + dt
                -- Stuck logic: Jump if stuck for a bit
                if stuckTimer > 0.5 and tick() - lastJumpTime > JUMP_COOLDOWN then
                    humanoid.Jump = true
                    lastJumpTime = tick()
                end
                if stuckTimer > 1.5 then
                    -- Random spin to unstuck
                    root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(math.random(90, 180)), 0)
                    stuckTimer = 0
                end
            else
                stuckTimer = 0
                stuckPos = root.Position
            end

            -- =============================================
            -- NEW SENSOR SYSTEM (HEIGHT AWARENESS)
            -- =============================================
            local function getFeatures(pos, dir)
                local dist = (pos - currentGoal.Position).Magnitude
                local toGoal = (currentGoal.Position - pos).Unit
                local goalAngle = dir:Dot(toGoal)
                
                -- Vertical Difference (Is target above/below?)
                local yDiff = currentGoal.Position.Y - pos.Y
                
                -- Raycast Params
                local rayParams = RaycastParams.new()
                rayParams.FilterDescendantsInstances = {character, goalFolder}
                rayParams.FilterType = Enum.RaycastFilterType.Exclude

                -- Horizontal Wall Sensors
                local function cast(ang)
                    local rDir = (CFrame.new(Vector3.zero, dir) * CFrame.Angles(0, ang, 0)).LookVector
                    local res = workspace:Raycast(pos, rDir * RAY_DIST, rayParams)
                    return res and (1 - (res.Distance / RAY_DIST)) or 0
                end
                
                -- NEW: Floor/Gap Sensor (Looks diagonally down in front)
                local function checkGap(ang)
                    -- Look 6 studs ahead, then cast DOWN
                    local forwardOffset = (CFrame.new(Vector3.zero, dir) * CFrame.Angles(0, ang, 0)).LookVector * 6
                    local rayOrigin = pos + forwardOffset
                    -- Cast down 50 studs
                    local res = workspace:Raycast(rayOrigin, Vector3.new(0, -50, 0), rayParams)
                    
                    if res then
                        return 0 -- Floor exists
                    else
                        return 1 -- GAP DETECTED (Danger!)
                    end
                end

                return {
                    goalDist = 100 / (dist + 10),
                    goalAngle = goalAngle,
                    goalBehind = goalAngle < -0.7 and 1 or 0,
                    
                    -- Wall Sensors
                    wallFront = cast(0),
                    wallLeft = cast(math.rad(-30)),
                    wallRight = cast(math.rad(30)),
                    
                    -- Gap Sensors (NEW)
                    gapFront = checkGap(0),
                    gapLeft = checkGap(math.rad(-30)),
                    gapRight = checkGap(math.rad(30)),
                    
                    -- Vertical Sensor (NEW)
                    targetAbove = yDiff > 3 and 1 or 0, -- Target is high
                    targetBelow = yDiff < -3 and 1 or 0, -- Target is low
                    
                    momentum = avgVelocity / 22
                }
            end
            
            -- DECISION MAKING
            local currentDir = root.CFrame.LookVector
            local feat = getFeatures(root.Position, currentDir)

            -- 1. JUMP LOGIC (Priority)
            local shouldJump = false
            
            -- Jump if there is a gap ahead (Obby logic)
            if feat.gapFront > 0 then 
                shouldJump = true 
            end
            
            -- Jump if target is high up and we are hitting a wall (Climbing logic)
            if feat.targetAbove > 0 and feat.wallFront > 0.5 then
                shouldJump = true
            end

            -- Execute Jump
            if shouldJump and tick() - lastJumpTime > JUMP_COOLDOWN then
                humanoid.Jump = true
                lastJumpTime = tick()
            end

            -- 2. MOVEMENT LOGIC (Weights)
            -- We want to avoid walls AND avoid gaps
            local weights = {
                goalAngle = 4.0,     -- Desire to face goal
                wallFront = -15.0,   -- Hate walls
                gapFront = -20.0,    -- HATE GAPS (Don't walk off edges)
                wallLeft = -2.0,
                wallRight = -2.0,
                gapLeft = -5.0,      -- Dislike gaps on sides
                gapRight = -5.0
            }

            local actions = {"forward", "left", "right", "slight_left", "slight_right"}
            local bestAction = "forward"
            local maxQ = -math.huge
            
            -- Evaluate best direction
            for _, action in ipairs(actions) do
                local nextDir = currentDir
                local nextPos = root.Position
                
                -- Simulate direction
                if action == "forward" then
                    nextPos = nextPos + (nextDir * 6)
                elseif action == "left" then
                    nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(45), 0)).LookVector
                    nextPos = nextPos + (nextDir * 4)
                elseif action == "right" then
                    nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(-45), 0)).LookVector
                    nextPos = nextPos + (nextDir * 4)
                -- (Add slight turns similarly if desired)
                end
                
                -- Get simulated features for that future position
                local simFeat = getFeatures(nextPos, nextDir)
                local q = 0
                
                -- Calculate Score
                for k, v in pairs(simFeat) do
                    if weights[k] then
                        q = q + (weights[k] * v)
                    end
                end
                
                if q > maxQ then
                    maxQ = q
                    bestAction = action
                end
            end
            
            -- APPLY MOVEMENT
            if bestAction == "left" then
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(15), 0)
            elseif bestAction == "right" then
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(-15), 0)
            end
            
            -- Move forward
            bodyVel.Velocity = root.CFrame.LookVector * MOVE_FORCE
        end
    end)
end


player.CharacterAdded:Connect(activateAI)
if player.Character then activateAI(player.Character) end

print("🤖 AI Master Enhanced: Better Learning + Smoother Navigation!")
