--====================================================
-- ULTIMATE AI TRAINING - 100 GOALS (MERGED BEST)
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
local successfulPaths = {}
local currentGoalID = 0
local MAX_DANGER_HISTORY = 50

local function recordDeath(position, goalPosition)
	table.insert(dangerZones, {
		pos = position,
		goal = goalPosition,
		time = tick(),
		severity = 1
	})
	
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
	
	print("ðŸ’€ Death recorded at", position)
end

local function recordSuccess(startPos, goalPos)
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
	
	for i = #dangerZones, math.max(1, #dangerZones - 20), -1 do
		local zone = dangerZones[i]
		local distToZone = (startPos - zone.pos).Magnitude
		
		if distToZone < 12 then
			local ageMultiplier = math.max(0.3, 1 - (tick() - zone.time) / 300)
			dangerScore = dangerScore + (zone.severity or 1) * ageMultiplier
		end
	end
	
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
local PATH_UPDATE_INTERVAL = 1.5
local lastPathPosition = nil

local function getPathHint(startPos, goalPos)
	if not currentPath then return nil, 0 end
	
	local waypoints = currentPath:GetWaypoints()
	if #waypoints < 2 then return nil, 0 end
	
	local bestWaypoint = nil
	local bestDist = math.huge
	
	for i = 2, math.min(#waypoints, 8) do
		local wp = waypoints[i]
		local dist = (wp.Position - startPos).Magnitude
		
		if dist > 5 and dist < 15 and dist < bestDist then
			bestDist = dist
			bestWaypoint = wp.Position
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
				WaypointSpacing = 3,
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
		timeLabel.Text = "ðŸ† FINAL TIME: " .. (math.floor(tick() - stats.startTime)) .. "s"
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
		local distance = math.random(35, 110)
		local searchPos = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {player.Character, goalFolder}
		params.FilterType = Enum.RaycastFilterType.Exclude
		
		rayResult = workspace:Raycast(searchPos + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), params)
		
		if rayResult then
			finalPos = rayResult.Position + Vector3.new(0, 2, 0)
			
			local isDangerous = false
			for _, zone in ipairs(dangerZones) do
				if (finalPos - zone.pos).Magnitude < 15 then
					isDangerous = true
					break
				end
			end
			
			if isDangerous and attempts < maxAttempts then
				rayResult = nil
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
			stats.score += math.max(5, 15 - math.floor(goalTime / 5))
			
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
-- ULTIMATE AI BRAIN: 360Â° LIDAR + Q-LEARNING
--====================================================
local function activateAI(character)
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	
	-- CONFIG
	local DEBUG_RAYS = true
	local MOVE_SPEED = 24
	local SENSOR_RANGE = 22
	local JUMP_COOLDOWN = 0.4
	
	humanoid.WalkSpeed = MOVE_SPEED
	
	-- PHYSICS (Best of both: BodyVelocity + BodyGyro)
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVel.P = 10000
	bodyVel.Parent = root
	
	local bodyGyro = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
	bodyGyro.P = 5000
	bodyGyro.D = 300
	bodyGyro.Parent = root

	-- VISUAL DEBUGGING
	local debugFolder = Instance.new("Folder")
	debugFolder.Name = "DebugRays"
	debugFolder.Parent = workspace
	
	local function drawRay(origin, direction, color)
		if not DEBUG_RAYS then return end
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(0.15, 0.15, direction.Magnitude)
		p.CFrame = CFrame.new(origin + direction/2, origin + direction)
		p.Parent = debugFolder
		Debris:AddItem(p, 0.05)
	end

	--====================================================
	-- 360Â° SENSOR SYSTEM (From Script 1)
	--====================================================
	local function get360SensorData(myPos, myCFrame, targetPos)
		local data = {
			avoidanceForce = Vector3.zero,
			gapDetected = false,
			needJump = false,
			wallInFront = false,
			wallDistances = {},
			clearDirections = {}
		}
		
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character, goalFolder, debugFolder}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		-- 360 DEGREE WALL CHECK (18 rays)
		for angle = 0, 340, 20 do
			local rad = math.rad(angle)
			local rayDir = (myCFrame * CFrame.Angles(0, rad, 0)).LookVector * SENSOR_RANGE
			
			local result = workspace:Raycast(myPos, rayDir, rayParams)
			
			if result then
				drawRay(myPos, result.Position - myPos, Color3.fromRGB(255, 0, 0))
				
				local proximity = 1 - (result.Distance / SENSOR_RANGE)
				local repulsionStrength = proximity * 4.0
				
				data.avoidanceForce = data.avoidanceForce + (result.Normal * repulsionStrength)
				data.wallDistances[angle] = result.Distance
				
				if angle < 20 or angle > 340 then
					data.wallInFront = true
					if result.Distance < 5 then
						data.needJump = true
					end
				end
			else
				drawRay(myPos, rayDir, Color3.fromRGB(0, 255, 0))
				data.clearDirections[angle] = true
			end
		end
		
		-- FLOOR GAP CHECK
		local forwardLook = myCFrame.LookVector * 6
		local floorRay = workspace:Raycast(myPos + forwardLook, Vector3.new(0, -15, 0), rayParams)
		
		if not floorRay then
			data.gapDetected = true
			data.needJump = true
			drawRay(myPos, forwardLook, Color3.fromRGB(255, 0, 255))
		end
		
		-- VERTICAL CHECK
		local yDiff = targetPos.Y - myPos.Y
		if yDiff > 3 and data.wallInFront then
			data.needJump = true
		end

		return data
	end

	--====================================================
	-- Q-LEARNING SYSTEM (From Script 2)
	--====================================================
	local function getQFeatures(pos, dir, sensor360)
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
		
		local isDangerous, dangerScore = isDangerousPath(pos, currentGoal.Position)
		
		-- Use 360 sensor data for wall detection
		local wallFront = sensor360.wallInFront and 1 or 0
		local avoidanceStrength = sensor360.avoidanceForce.Magnitude / 10
		local clearPathScore = 0
		for angle, _ in pairs(sensor360.clearDirections) do
			if angle >= 315 or angle <= 45 then
				clearPathScore = clearPathScore + 1
			end
		end
		
		return {
			goalDist = 100 / (dist + 10),
			goalAngle = goalAngle,
			pathAngle = pathAngle,
			successAngle = successAngle,
			goalBehind = goalBehind,
			goalRight = goalRight,
			wallFront = wallFront,
			avoidanceStrength = avoidanceStrength,
			clearPathScore = clearPathScore / 3,
			gapAhead = sensor360.gapDetected and 1 or 0,
			dangerPenalty = math.min(dangerScore, 3)
		}
	end

	--====================================================
	-- MAIN LOOP
	--====================================================
	local isAlive = true
	local lastJump = 0
	local lastPos = root.Position
	local stuckTimer = 0
	local velocityHistory = {}
	
	humanoid.Died:Connect(function()
		isAlive = false
		debugFolder:Destroy()
		stats.deaths += 1
		deathLabel.Text = "Deaths: " .. stats.deaths
		if currentGoal then
			recordDeath(root.Position, currentGoal.Position)
		end
	end)

	humanoid.Seated:Connect(function(active)
		if active then humanoid.Jump = true end
	end)

	task.spawn(function()
		while isAlive and character.Parent do
			local dt = task.wait(0.03)
			
			if not currentGoal or not currentGoal.Parent then
				bodyVel.Velocity = Vector3.zero
				continue
			end

			-- TIMEOUT LOGIC
			local elapsed = tick() - stats.goalSpawnTime
			timerLabel.Text = "Goal Timer: " .. math.ceil(GOAL_TIMEOUT - elapsed) .. "s"
			if elapsed >= GOAL_TIMEOUT then
				showPopup("UNREACHABLE", 2, Color3.fromRGB(255, 150, 0))
				spawnNextGoal()
				continue
			end
			
			-- Update pathfinding hint
			pathUpdateCooldown = pathUpdateCooldown - dt
			if pathUpdateCooldown <= 0 then
				pathUpdateCooldown = PATH_UPDATE_INTERVAL
				updatePathHint(root.Position, currentGoal.Position)
			end
			
			-- VELOCITY TRACKING (From Script 2)
			table.insert(velocityHistory, root.AssemblyLinearVelocity.Magnitude)
			if #velocityHistory > 10 then
				table.remove(velocityHistory, 1)
			end
			
			local avgVelocity = 0
			for _, v in ipairs(velocityHistory) do
				avgVelocity = avgVelocity + v
			end
			avgVelocity = avgVelocity / math.max(#velocityHistory, 1)
			
			-- Get 360Â° sensor data
			local sensor360 = get360SensorData(root.Position, root.CFrame, currentGoal.Position)
			
			-- ENHANCED STUCK DETECTION
			if (root.Position - lastPos).Magnitude < 0.2 or avgVelocity < 2 then
				stuckTimer = stuckTimer + dt
				
				if stuckTimer > 0.5 and (tick() - lastJump > JUMP_COOLDOWN) then
					humanoid.Jump = true
					lastJump = tick()
				end
				
				if stuckTimer > 1.5 then
					root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(math.random(90, 180)), 0)
					stuckTimer = 0
				end
			else
				stuckTimer = 0
			end
			lastPos = root.Position

			-- Q-LEARNING ACTION SELECTION
			local actions = {"forward", "left", "right", "sharp_left", "sharp_right", "slight_left", "slight_right"}
			local bestAction = "forward"
			local maxQ = -math.huge
			
			-- Enhanced weights combining both systems
			local weights = {
				goalDist = 3.8,
				goalAngle = 3.2,
				pathAngle = 3.0,
				successAngle = 2.5,
				goalBehind = -6.0,
				wallFront = -14.0,
				avoidanceStrength = -8.0,
				clearPathScore = 7.0,
				gapAhead = -15.0,
				dangerPenalty = -8.0
			}
			
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
				
				local feat = getQFeatures(nextPos, nextDir, sensor360)
				local q = 0
				
				-- 360 turn logic
				if feat.goalBehind > 0 then
					if action == "sharp_left" and feat.goalRight < 0 then
						q = q + 14
					elseif action == "sharp_right" and feat.goalRight > 0 then
						q = q + 14
					end
				end
				
				-- Gap avoidance bonus
				if sensor360.gapDetected then
					if action == "sharp_left" or action == "sharp_right" then
						q = q + 10
					end
				end
				
				for k, v in pairs(feat) do
					q = q + (weights[k] or 0) * v
				end
				
				-- Forward bias when path is clear
				if (action == "forward" or action == "slight_left" or action == "slight_right") and feat.goalBehind < 1 and feat.clearPathScore > 0.5 then
					q = q + 2.5
				end
				
				if q > maxQ then
					maxQ = q
					bestAction = action
				end
			end
			
			-- JUMP EXECUTION
			if sensor360.needJump and (tick() - lastJump > JUMP_COOLDOWN) then
				humanoid.Jump = true
				lastJump = tick()
			end
			
-- Execute action with smooth rotation
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
			
			-- HYBRID MOVEMENT: Combine vector forces with Q-learning
			local moveDir = root.CFrame.LookVector
			
			-- Add avoidance force influence
			if sensor360.avoidanceForce.Magnitude > 0.5 then
				local avoidInfluence = sensor360.avoidanceForce.Unit * 0.3
				moveDir = (moveDir + avoidInfluence).Unit
			end
			
			-- Apply physics
			bodyVel.Velocity = moveDir * MOVE_SPEED
			bodyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + moveDir)
			humanoid:Move(moveDir, false)
		end
	end)
end

player.CharacterAdded:Connect(activateAI)
if player.Character then activateAI(player.Character) end

print("ðŸš€ ULTIMATE AI: 360Â° LIDAR + Q-Learning + Advanced Memory!")
