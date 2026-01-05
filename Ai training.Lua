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
-- ENHANCED AI BRAIN
--====================================================
local RAY_DIST = 22 -- Slightly longer vision
local MOVE_FORCE = 28
local JUMP_COOLDOWN = 0.5
local lastJumpTime = 0

local function activateAI(character)
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	
	humanoid.WalkSpeed = 22
	
	humanoid.Seated:Connect(function(active)
		if active then humanoid.Jump = true end
	end)
	
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVel.P = 10000
	bodyVel.Parent = root
	
	local isAlive = true
	local stuckPos = root.Position
	local stuckTimer = 0
	local lastPosition = root.Position
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
			local dt = task.wait(0.04) -- Faster tick rate
			
			if not currentGoal or not currentGoal.Parent then
				bodyVel.Velocity = Vector3.zero
				continue
			end
			
			local elapsed = tick() - stats.goalSpawnTime
			timerLabel.Text = "Goal Timer: " .. math.ceil(GOAL_TIMEOUT - elapsed) .. "s"
			
			if elapsed >= GOAL_TIMEOUT then
				showPopup("UNREACHABLE - REROUTING", 2, Color3.fromRGB(255, 150, 0))
				spawnNextGoal()
				continue
			end
			
			pathUpdateCooldown = pathUpdateCooldown - dt
			if pathUpdateCooldown <= 0 then
				pathUpdateCooldown = PATH_UPDATE_INTERVAL
				updatePathHint(root.Position, currentGoal.Position)
			end
			
			-- Enhanced stuck detection with velocity tracking
			table.insert(velocityHistory, root.AssemblyLinearVelocity.Magnitude)
			if #velocityHistory > 10 then
				table.remove(velocityHistory, 1)
			end
			
			local avgVelocity = 0
			for _, v in ipairs(velocityHistory) do
				avgVelocity = avgVelocity + v
			end
			avgVelocity = avgVelocity / #velocityHistory
			
			if (root.Position - stuckPos).Magnitude < 1.5 or avgVelocity < 2 then
				stuckTimer = stuckTimer + dt
				
				if stuckTimer > 0.5 and tick() - lastJumpTime > JUMP_COOLDOWN then
					humanoid.Jump = true
					lastJumpTime = tick()
				end
				
				if stuckTimer > 1.5 then
					root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(math.random(90, 180)), 0)
					stuckTimer = 0
				end
			else
				stuckTimer = 0
				stuckPos = root.Position
			end

			-- ENHANCED SENSOR SYSTEM
			local function getFeatures(pos, dir)
				local dist = (pos - currentGoal.Position).Magnitude
				local toGoal = (currentGoal.Position - pos).Unit
				local goalAngle = dir:Dot(toGoal)
				
				local pathHint, pathConfidence = getPathHint(pos, currentGoal.Position)
				local pathAngle = 0
				if pathHint then
					pathAngle = dir:Dot(pathHint) * pathConfidence
				end
				
				local hasSuccess, successDir = hasSuccessfulRoute(pos, currentGoal.Position)
				local successAngle = 0
				if hasSuccess then
					successAngle = dir:Dot(successDir)
				end
				
				local goalBehind = goalAngle < -0.7 and 1 or 0
				local rightVec = root.CFrame.RightVector
				local goalRight = rightVec:Dot(toGoal)
				
				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = {character, goalFolder}
				
				local function cast(ang)
					local rDir = (CFrame.new(Vector3.zero, dir) * CFrame.Angles(0, ang, 0)).LookVector
					local res = workspace:Raycast(pos, rDir * RAY_DIST, rayParams)
					return res and (1 - (res.Distance / RAY_DIST)) or 0
				end
				
				local isDangerous, dangerScore = isDangerousPath(pos, currentGoal.Position)
				
				local clearLeft = cast(math.rad(-45)) < 0.25 and 1 or 0
				local clearRight = cast(math.rad(45)) < 0.25 and 1 or 0
				
				return {
					goalDist = 100 / (dist + 10),
					goalAngle = goalAngle,
					pathAngle = pathAngle,
					successAngle = successAngle,
					goalBehind = goalBehind,
					goalRight = goalRight,
					wallFront = cast(0),
					wallLeft = cast(math.rad(-30)),
					wallRight = cast(math.rad(30)),
					wallFarLeft = cast(math.rad(-60)),
					wallFarRight = cast(math.rad(60)),
					clearLeft = clearLeft,
					clearRight = clearRight,
					dangerPenalty = math.min(dangerScore, 3),
					momentum = avgVelocity / 22
				}
			end
			
			-- Enhanced weights
			local weights = {
				goalDist = 3.8,
				goalAngle = 3.2,
				pathAngle = 3.0,
				successAngle = 2.5,
				goalBehind = -6.0,
				wallFront = -14.0,
				wallLeft = -1.5,
				wallRight = -1.5,
				wallFarLeft = -0.5,
				wallFarRight = -0.5,
				clearLeft = 6.0,
				clearRight = 6.0,
				dangerPenalty = -8.0,
				momentum = 1.5
			}

			local actions = {"forward", "left", "right", "sharp_left", "sharp_right", "slight_left", "slight_right"}
			local bestAction = "forward"
			local maxQ = -math.huge
			
			for _, action in ipairs(actions) do
				local nextDir = root.CFrame.LookVector
				local nextPos = root.Position
				
				if action == "forward" then
					nextPos = nextPos + (nextDir * 6)
				elseif action == "slight_left" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(15), 0)).LookVector
					nextPos = nextPos + (nextDir * 5)
				elseif action == "slight_right" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(-15), 0)).LookVector
					nextPos = nextPos + (nextDir * 5)
				elseif action == "left" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(35), 0)).LookVector
					nextPos = nextPos + (nextDir * 4)
				elseif action == "right" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(-35), 0)).LookVector
					nextPos = nextPos + (nextDir * 4)
				elseif action == "sharp_left" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(80), 0)).LookVector
					nextPos = nextPos + (nextDir * 3)
				elseif action == "sharp_right" then
					nextDir = (CFrame.new(Vector3.zero, nextDir) * CFrame.Angles(0, math.rad(-80), 0)).LookVector
					nextPos = nextPos + (nextDir * 3)
				end
				
				local feat = getFeatures(nextPos, nextDir)
				local q = 0
				
				-- 360 turn logic
				if feat.goalBehind > 0 then
					if action == "sharp_left" and feat.goalRight < 0 then
						q = q + 14
					elseif action == "sharp_right" and feat.goalRight > 0 then
						q = q + 14
					end
				end
				
				-- Wall flow logic
				if feat.wallFront > 0.6 then
					if action == "left" or action == "sharp_left" then
						q = q + (feat.clearLeft * 10)
					end
					if action == "right" or action == "sharp_right" then
						q = q + (feat.clearRight * 10)
					end
				end
				
				for k, v in pairs(feat) do
					q = q + (weights[k] or 0) * v
				end
				
				-- Forward bias when path is clear
				if (action == "forward" or action == "slight_left" or action == "slight_right") and feat.goalBehind < 1 then
					q = q + 2.5
				end
				
				if q > maxQ then
					maxQ = q
					bestAction = action
				end
			end
			
			-- Execute action with smoother turning
			if bestAction == "slight_left" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(12), 0)
			elseif bestAction == "slight_right" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(-12), 0)
			elseif bestAction == "left" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(22), 0)
			elseif bestAction == "right" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(-22), 0)
			elseif bestAction == "sharp_left" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(55), 0)
			elseif bestAction == "sharp_right" then
				root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(-55), 0)
			end
			
			bodyVel.Velocity = root.CFrame.LookVector * MOVE_FORCE
			humanoid:Move(root.CFrame.LookVector, false)
			
			lastPosition = root.Position
		end
	end)
end

player.CharacterAdded:Connect(activateAI)
if player.Character then activateAI(player.Character) end

print("🤖 AI Master Enhanced: Better Learning + Smoother Navigation!")
