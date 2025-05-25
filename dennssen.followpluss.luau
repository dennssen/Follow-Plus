-- Only used for display reasons
local version: string = "1.8.0"
metadata = {
	name = "Follow Pluss",
	description = "A Highly Customisable Multitool for all your Follow Needs, including but not limited to: 5 different Camera Modes, 2 Auto Cameras, Replay Compatability, and More!",
	author = "Dennssen",
	defaultKeybind = "F",
}

local CameraMode = {
	FirstPerson = 1,
	HeadRotation = 2,
	VelocityRotation = 3,
	FaceTheBall = 4,
	HandHeld = 5,
}

-- This is what chatGPT was made for
local function parseBallJSON(str)
	-- Table to store the parsed data
	local result = {}

	-- Parse type
	local typeVal = string.match(str, '"type"%s*:%s*([%d]+)')
	result.type = tonumber(typeVal)

	return result
end

--(A2.Vector){ 0.000000, 0.000000, -180.000000 }
function stringToVec3(string: string): Vec3
	local x, y, z = string.match(string, "%{ ([%d.-]+), ([%d.-]+), ([%d.-]+) %}")
	if not x or not y or not z then
		return Vec3.zeroVector
	end

	x = tonumber(x)
	y = tonumber(y)
	z = tonumber(z)

	local vec = Vec3.new(x, y, z)
	return vec
end

function muteAll(mute: boolean)
	local frame = getGameData()
	for _, player in frame.players do
		Settings.mutePlayerByName(player.playerName, mute)
	end
end

function muteList(mute: boolean, playerNames: { string })
	for _, playerName in playerNames do
		if not Settings.mutePlayerByName(playerName, mute) then
			print(playerName)
		end
	end
end

local function initializeProfiles()
	local saveToConfig = false
	local neededValues = {
		radius = 20,
		distanceLerp = 4,
		readLocation = 0,
		autoBallThreshold = 12,
		ballGoalMode = 1,
		cameraPositionOffset = "(A2.Vector){ 0.000000, 0.000000, 0.000000 }",
		cameraEulerOffset = "(A2.Vector){ 0.000000, 0.000000, 0.000000 }",
		showNameTags = true,
		threshold = 7,
		fieldOfView = 100,
		positionSmoothing = 0.1000000014901161,
		autoGoalCam = false,
		goalMode = 1,
		autoBall = false,
		targetPlayerName = "YourName",
		cameraMode = CameraMode.HeadRotation,
		muteSelf = false,
		gestureControls = false,
		forwardGestureMode = CameraMode.VelocityRotation,
		upGestureMode = CameraMode.FaceTheBall,
		backwardsGestureMode = CameraMode.HeadRotation,
		focusedArena = false,
		isLeftHanded = false,
	}

	-- remove every value in the root of the config that isn't profiles or lastUsedProfile
	for key, value in pairs(config) do
		if tostring(key) ~= "profiles" and tostring(key) ~= "lastUsedProfile" then
			config[key] = nil
			saveToConfig = true
		end
	end

	-- check if profiles and lastUsedProfile values exist
	if config.profiles == nil then
		config.profiles = {}
		saveToConfig = true
	end
	if config.lastUsedProfile == nil then
		config.lastUsedProfile = "default"
		saveToConfig = true
	end

	-- saves new values that are not there from before to all profiles
	for neededKey, neededValue in pairs(neededValues) do
		for profileKey, profileValue in pairs(config.profiles) do
			if profileValue[neededKey] == nil then
				saveToConfig = true
				profileValue[neededKey] = neededValue
			end
		end
	end

	-- removes saved but no longer used values in all profiles
	for profileKey, profileValue in pairs(config.profiles) do
		for key, value in pairs(profileValue) do
			if neededValues[key] == nil then
				saveToConfig = true
				config.profiles[profileKey][key] = nil
			end
		end
	end

	config.profiles["default"] = neededValues
	if saveToConfig then
		saveConfig()
	end
end

initializeProfiles()

local lastUsedProfile = config.lastUsedProfile
local profile = config.profiles[lastUsedProfile]
if profile == nil then
	profile = config.profiles["default"]
end

local deltaTime: number = 0

-- VOIP
local isSelfMuted = false
local muteSelf = profile.muteSelf
local focusedArena = false
local lastFocusedArena = focusedArena

-- goal
local goalCamPositionOffset = Vec3.new(3330, 0, 250)
local goalCamFOV = 120
local bridgeHeightOffset = 245
local haloHeightOffset = 580
local underBridgeRotation = Quat.fromEuler(0, -40, 0)
local overBridgeRotation = Quat.fromEuler(0, -20, 0)
local overHaloRotation = Quat.identity
local enterGoalCamDist = 500
local exitGoalCamDist = 750

local goalPositionOffset = 3165
local goalHeightOffset = Vec3.new(0, 0, -40)
local awayGoalRotationOffset = Vec3.new(0, 0, 180)
local homeGoalRotationOffset = Vec3.new(0, 0, 0)

local autoGoalCam = profile.autoGoalCam
local goalMode: number = profile.goalMode
local goalModes = { "My Goal", "Both Goals" }
local cameraInAwayGoal: boolean = false
local cameraInHomeGoal: boolean = false
local cameraInGoal: boolean = false

local GoalMode = {
	MyGoal = 1,
	BothGoals = 2,
}

local instaRotate = false
local doneOnce = false
local distanceLerp = profile.distanceLerp

-- arena
local arenaFloorOffset = -350
local arenaRoofOffset = 1150

type Arena = {
	name: string,
	position: Vec3,
	rotation: Quat,
	home: {
		goal: {
			position: Vec3,
			rotation: Quat,
		},
		goalCam: {
			position: Vec3,
			rotation: Quat,
		},
	},
	away: {
		goal: {
			position: Vec3,
			rotation: Quat,
		},
		goalCam: {
			position: Vec3,
			rotation: Quat,
		},
	},
}

function createArena(name: string, position: Vec3, rotation: Quat): Arena
	return {
		name = name,
		position = position,
		rotation = rotation,
		home = {
			goal = {
				position = nil,
				rotation = nil,
			},
			goalCam = {
				position = nil,
				rotation = nil,
			},
		},
		away = {
			goal = {
				position = nil,
				rotation = nil,
			},
			goalCam = {
				position = nil,
				rotation = nil,
			},
		},
	}
end

local arenas: { [any]: Arena } = {
	plazaStadium = createArena("Plaza Stadium", Vec3.new(0, 9900, -29650), Quat.fromEuler(0, 0, 0)),
	plazaEast = createArena("Plaza East", Vec3.new(-4425, 18550, -29650), Quat.fromEuler(0, 0, 90)),
	plazaWest = createArena("Plaza West", Vec3.new(4425, 18550, -29650), Quat.fromEuler(0, 0, -90)),
	arenaPrime = createArena("Arena Prime", Vec3.new(0, 27250, -28050), Quat.fromEuler(0, 0, 0)),
	theDungeon = createArena("The Dungeon", Vec3.new(-112.6, 24944.6, -31545), Quat.fromEuler(0, 0, 180)),
	complexEast = createArena("Complex East", Vec3.new(-4500, 27100, -29850), Quat.fromEuler(0, 0, 90)),
	complexWest = createArena("Complex West", Vec3.new(4500, 27100, -29850), Quat.fromEuler(0, 0, -90)),
	driftplex1 = createArena("Driftplex 01", Vec3.new(12799.231, 13600.000, -27568.920), Quat.fromEuler(30, 0, 90)),
	driftplex2 = createArena("Driftplex 02", Vec3.new(17475.770, 13600.000, -24868.920), Quat.fromEuler(-30, 0, -90)),
	driftplex3 = createArena("Driftplex 03", Vec3.new(12799.231, 6400.000, -27568.920), Quat.fromEuler(30, 0, 90)),
	driftplex4 = createArena("Driftplex 04", Vec3.new(17475.770, 6400.000, -24868.920), Quat.fromEuler(-30, 0, -90)),
	driftplex5 = createArena("Driftplex 05", Vec3.new(17475.770, 23200.000, -24868.920), Quat.fromEuler(-30, 0, -90)),
	driftplex6 = createArena("Driftplex 06", Vec3.new(12799.231, 23200.000, -27568.920), Quat.fromEuler(30, 0, 90)),
	driftplexLab = createArena("Driftplex Lab", Vec3.new(15137.500, 29200.000, -26218.920), Quat.fromEuler(0, 30, 0)),
}

for _, arena in pairs(arenas) do
	arena.home.goal = {
		position = arena.position + goalHeightOffset + arena.rotation:getForwardVector() * goalPositionOffset,
		rotation = arena.rotation:euler() + homeGoalRotationOffset,
	}
	arena.away.goal = {
		position = arena.position + goalHeightOffset + arena.rotation:getForwardVector() * -goalPositionOffset,
		rotation = arena.rotation:euler() + awayGoalRotationOffset,
	}

	arena.home.goalCam = {
		position = arena.position + arena.rotation:rotateVector(goalCamPositionOffset),
		rotation = arena.rotation * Quat.fromEuler(0, 0, 180),
	}
	arena.away.goalCam = {
		position = arena.position + (arena.rotation * Quat.fromEuler(0, 0, 180)):rotateVector(goalCamPositionOffset),
		rotation = arena.rotation,
	}
end

type BoxType = {
	__index: BoxType,
	position: Vec3,
	size: Vec3,
	rotation: Quat,
	vertexLocations: { Vec3 },

	__tostring: (self: BoxType) -> string,
	new: (inputPosition: Vec3, inputSize: Vec3, inputRotation: Quat) -> BoxType,
	setPosition: (self: BoxType, inputPosition: Vec3) -> (),
	setSize: (self: BoxType, inputPosition: Vec3) -> (),
	setRotation: (self: BoxType, inputPosition: Quat) -> (),
	getPosition: (self: BoxType) -> Vec3,
	getSize: (self: BoxType) -> Vec3,
	getRotation: (self: BoxType) -> Quat,
	getRotationDeg: (self: BoxType) -> Vec3,
	generatePoints: (self: BoxType) -> (),
	multiplyMatrices: (self: BoxType, matrix1: { { number } }, matrix2: { { number } }) -> { { number } },
	applyRotationMatrix: (self: BoxType, vec: Vec3, matrix: { { number } }) -> Vec3,
	render: (self: BoxType, r: number, g: number, b: number) -> (),
	checkPointIntersect: (self: BoxType, point: Vec3) -> boolean,
	getClosestPoint: (self: BoxType, point: Vec3, surfaceOnly: boolean) -> Vec3,
}

local Box: BoxType = {} :: BoxType
Box.__index = Box

function Box.new(inputPosition: Vec3, inputSize: Vec3, inputRotation: Quat): BoxType
	local self: BoxType = setmetatable({}, Box) :: any

	self.position = inputPosition
	self.size = inputSize
	self.rotation = inputRotation

	self.vertexLocations = {}
	self:generatePoints()
	return self
end

function Box:setPosition(inputPosition: Vec3): ()
	self.position = inputPosition
	self:generatePoints()
end

function Box:setSize(inputSize: Vec3): ()
	self.size = inputSize
	self:generatePoints()
end

function Box:setRotation(inputRotation: Quat): ()
	self.rotation = inputRotation
	self:generatePoints()
end

function Box:getPosition(): Vec3
	return Vec3.new(self.position.x, self.position.y, self.position.z)
end

function Box:getSize(): Vec3
	return Vec3.new(self.size.x, self.size.y, self.size.z)
end

function Box:getRotation(): Quat
	return self.rotation
end

function Box:getRotationDeg(): Vec3
	return self.rotation:euler()
end

function Box:generatePoints(): ()
	local shift = { x = self.size.x / 2, y = self.size.y / 2, z = self.size.z / 2 }
	local newVertexLocations = {
		Vec3.new(shift.x, shift.y, shift.z),
		Vec3.new(shift.x, shift.y, -shift.z),
		Vec3.new(shift.x, -shift.y, shift.z),
		Vec3.new(shift.x, -shift.y, -shift.z),
		Vec3.new(-shift.x, shift.y, shift.z),
		Vec3.new(-shift.x, shift.y, -shift.z),
		Vec3.new(-shift.x, -shift.y, shift.z),
		Vec3.new(-shift.x, -shift.y, -shift.z),
	}

	for i = 1, #newVertexLocations do
		newVertexLocations[i] = self.rotation:rotateVector(newVertexLocations[i])
	end

	-- Translate the vertices by the box position.
	for i = 1, #newVertexLocations do
		newVertexLocations[i].x = newVertexLocations[i].x + self.position.x
		newVertexLocations[i].y = newVertexLocations[i].y + self.position.y
		newVertexLocations[i].z = newVertexLocations[i].z + self.position.z
	end

	self.vertexLocations = newVertexLocations
end

function Box:multiplyMatrices(matrix1: { { number } }, matrix2: { { number } }): { { number } }
	local result: { { number } } = {}
	for i = 1, 3 do
		result[i] = {}
		for j = 1, 3 do
			result[i][j] = 0
			for k = 1, 3 do
				result[i][j] = result[i][j] + matrix1[i][k] * matrix2[k][j]
			end
		end
	end
	return result
end

function Box:applyRotationMatrix(vec: Vec3, matrix: { { number } }): Vec3
	local x = vec.x * matrix[1][1] + vec.y * matrix[1][2] + vec.z * matrix[1][3]
	local y = vec.x * matrix[2][1] + vec.y * matrix[2][2] + vec.z * matrix[2][3]
	local z = vec.x * matrix[3][1] + vec.y * matrix[3][2] + vec.z * matrix[3][3]
	return Vec3.new(x, y, z)
end

function Box:render(r: number, g: number, b: number): ()
	local lines: { { start: Vec3, finish: Vec3 } } = {
		{ start = self.vertexLocations[1], finish = self.vertexLocations[2] },
		{ start = self.vertexLocations[1], finish = self.vertexLocations[3] },
		{ start = self.vertexLocations[1], finish = self.vertexLocations[5] },
		{ start = self.vertexLocations[4], finish = self.vertexLocations[2] },
		{ start = self.vertexLocations[4], finish = self.vertexLocations[3] },
		{ start = self.vertexLocations[4], finish = self.vertexLocations[8] },
		{ start = self.vertexLocations[7], finish = self.vertexLocations[8] },
		{ start = self.vertexLocations[7], finish = self.vertexLocations[3] },
		{ start = self.vertexLocations[7], finish = self.vertexLocations[5] },
		{ start = self.vertexLocations[6], finish = self.vertexLocations[5] },
		{ start = self.vertexLocations[6], finish = self.vertexLocations[2] },
		{ start = self.vertexLocations[6], finish = self.vertexLocations[8] },
	}

	World.drawPoint(self.position, 0.2, 3, 0.2, 5, 0)
	for i: number, line: { start: Vec3, finish: Vec3 } in lines do
		World.drawLine(line.start, line.finish, r, g, b, 4, 0)
	end

	local minSize = math.max(math.min(self.size.x, self.size.y, self.size.z), 10)

	World.drawLine(self.position, self.position + self.rotation:getForwardVector() * minSize, 1, 0, 0, 2.5, 0)
	World.drawLine(self.position, self.position + self.rotation:getUpVector() * minSize, 0, 1, 0, 2.5, 0)
	World.drawLine(self.position, self.position + self.rotation:getRightVector() * minSize, 0, 0, 1, 2.5, 0)
end

function Box:checkPointIntersect(point: Vec3): boolean
	if point == nil then
		return false
	end

	local zeroPoint: Vec3 = self.vertexLocations[1]
	local fullPoint: Vec3 = self.vertexLocations[8]
	local centerPoint: Vec3 = (zeroPoint + fullPoint) / 2

	local projectionVector: Vec3 = point - centerPoint

	-- Thanks to MrStick, Brick_Rage, and RAD_David
	local xLocal = self.vertexLocations[5] - self.vertexLocations[1]
	local yLocal = self.vertexLocations[3] - self.vertexLocations[1]
	local zLocal = self.vertexLocations[2] - self.vertexLocations[1]

	local pX: number = math.abs(Vec3.dot(projectionVector, xLocal:getSafeNormal()))
	local pY: number = math.abs(Vec3.dot(projectionVector, yLocal:getSafeNormal()))
	local pZ: number = math.abs(Vec3.dot(projectionVector, zLocal:getSafeNormal()))

	if 2 * pX <= xLocal:length() and 2 * pY <= yLocal:length() and 2 * pZ <= zLocal:length() then
		return true
	else
		return false
	end
end

function Box:getClosestPoint(point: Vec3, surfaceOnly: boolean): Vec3
	local pointOffset = point - self.position
	local localPoint = self.rotation:inverse():rotateVector(pointOffset)
	local boxExtents = Vec3.new(self.size.x / 2, self.size.y / 2, self.size.z / 2)

	local clamped = Vec3.new(
		math.clamp(localPoint.x, -boxExtents.x, boxExtents.x),
		math.clamp(localPoint.y, -boxExtents.y, boxExtents.y),
		math.clamp(localPoint.z, -boxExtents.z, boxExtents.z)
	)

	if surfaceOnly and self:checkPointIntersect(localPoint) then
		local dx = math.min(boxExtents.x - localPoint.x, localPoint.x + boxExtents.x)
		local dy = math.min(boxExtents.y - localPoint.y, localPoint.y + boxExtents.y)
		local dz = math.min(boxExtents.z - localPoint.z, localPoint.z + boxExtents.z)

		if dx <= dy and dx <= dz then
			if localPoint.x > 0 then
				clamped.x = boxExtents.x
			else
				clamped.x = -boxExtents.x
			end
		elseif dy <= dz then
			if localPoint.y > 0 then
				clamped.y = boxExtents.y
			else
				clamped.y = -boxExtents.y
			end
		else
			if localPoint.z > 0 then
				clamped.z = boxExtents.z
			else
				clamped.z = -boxExtents.z
			end
		end
	end

	local worldClosest = self.rotation:rotateVector(clamped) + self.position

	return worldClosest
end

local arena = arenas.plazaStadium

-- camera
local wasFollowed: boolean = false
local cameraFOV = profile.fieldOfView
camera.fieldOfView = cameraFOV
local showNameTags = profile.showNameTags
camera.showNameTags = showNameTags
local positionSmoothing = profile.positionSmoothing
camera.positionSmoothing = positionSmoothing
local rotationSmoothing = 0.1
camera.rotationSmoothing = rotationSmoothing
camera.hideNearestHead = false
local previousCameraMode: number = profile.cameraMode
local cameraMode: number = profile.cameraMode
local cameraModes = { "First Person", "Head Rotation", "Velocity Rotation", "Face the Ball", "Hand Held" }
local gestureModes = { "Head Rotation", "Velocity Rotation", "Face the Ball" }

local cameraTransition: boolean = false
local cameraEulerOffset: Vec3 = stringToVec3(profile.cameraEulerOffset)
local cameraPositionOffset: Vec3 = Vec3.zeroVector
local hit: RayHit
local distance = 0
local flipTime: number = 0
local maxFlipTime: number = 0.5
local previousHandHeldRotationOffset: Quat = Quat.identity
local nextHandHeldRotationOffset: Quat = Quat.identity
local handHeldRotationOffset: Quat = Quat.identity

local gravityUpDirection: Vec3 = Vec3.zeroVector

-- gui
local readLocation = profile.readLocation -- 0: Live, 1 or above: Replay
local listActive = false
local currentPercentage = 0
local savingNewProfile = false
local deletingProfile = false
local newProfileName = ""
local confirmationText = ""
local debugBallPrediction = false
local playerNameInfo: string = ""
local playerIdInfo: string = ""

-- labels
local gestureControlsHeaderLabel = "Gesture Controls"
local autoShootingCameraHeaderLabel = "Auto Shooting Camera"
local goalCameraHeaderLabel = "Goal Camera"

local gameDataLabel = "Game Data"
local nametagsLabel = "Nametags"
local isLeftHandedLabel = "Left Handed"
local muteSelfLabel = "Mute Self"
local focusedArenaLabel = "Focused Arenas"
local targetPlayerNameLabel = "Follow Player"
local cameraFOVLabel = "Field Of View"
local positionSmoothingLabel = "Camera Smoothing"
local cameraModeLabel = "Camera Mode"
local radiusLabel = "Radius"
local thresholdLabel = "Smart Switch Distance"
local cameraEulerOffsetLabel = "Camera Rotation Offset"
local cameraPositionOffsetLabel = "Camera Position Offset"
local gestureControlsLabel = "Enabled"
local forwardGestureModeLabel = "Forward Mode"
local upGestureModeLabel = "Up Mode"
local backwardsGestureModeLabel = "Backward Mode"
local autoBallLabel = "Enabled"
local autoBallThresholdLabel = "Toggle Speed (m/s)"
local ballCamGoalModeLabel = "Ball Goal Mode"
local autoGoalCamLabel = "Enabled"
local goalModeLabel = "Mode"
local distanceLerpLabel = "Player/Ball Ratio"

-- player
local targetPlayer = nil
local targetPlayerName = profile.targetPlayerName
local previousTargetPlayerId = -1
local targetPlayerId = -1
local headPosition: Vec3 = Vec3.new(0, 0, 0)
local headRotation: Quat = Quat.identity
local playerVelocity = Vec3.zeroVector
local playerChestRotation: Quat = Quat.identity
local isLocalPlayer = false
local teamIndex = -1
local TeamIndex = {
	NoTeam = -1,
	HomeTeam = 0,
	AwayTeam = 1,
}

local previousLeftHandPosition: Vec3 = Vec3.zeroVector
local previousRightHandPosition: Vec3 = Vec3.zeroVector
local isLeftHanded: boolean = profile.isLeftHanded
local playerSwitchTime: number = 0
local muteDelay: number = 1

local lastServerPlayerList: { number } = {}
local lastTeammatesList: { string } = {}
local teammatesList: { string } = {}

-- grabbing
local gestureControls: boolean = profile.gestureControls

local forwardGestureMode: number = profile.forwardGestureMode
local upGestureMode: number = profile.upGestureMode
local backwardsGestureMode: number = profile.backwardsGestureMode

local leftHandGrabbing: boolean = false
local previousLeftHandGrabbing: boolean = false
local rightHandGrabbing: boolean = false
local previousRightHandGrabbing: boolean = false

local throwBoost: number = 250
local throwVelocity: Vec3 = Vec3.zeroVector
local lastGrabPosition: Vec3 = Vec3.zeroVector

local grabTimers = {
	left = 0,
	right = 0,
}

local releaseTimers = {
	left = 0,
	right = 0,
}

local maxGrabTime: number = 0.25
local maxLetGoTime: number = 1

local HandPose = {
	Neutral = 0, -- Doesn't work
	Flat = 1, -- Hand on ground and not grabbing
	Closed = 2, -- Doesn't work
	GrabBall = 3, -- Hold ball
	Horns = 4, -- Doesn't work
	OK = 5, -- Doesn't work
	Peace = 6, -- Doesn't work
	Point = 7, -- Doesn't work
	Shaka = 8, -- Doesn't work
	ThumbsUp = 9, -- Doesn't work
	FingerGun = 10, -- Doesn't work
	MAX = 11, -- When not Flat or Holding ball
}

-- ball
local ballPosition: Vec3 = Vec3.zeroVector
local ballRotation: Quat = Quat.identity
local ballVelocity: Vec3 = Vec3.zeroVector
local ballArena: number = nil
local autoBall = profile.autoBall
local autoBallThreshold = profile.autoBallThreshold
local ballTarget = false
local doneOnceBall = false
local instaRotateBall = false
local acceleration: Vec3 = Vec3.zeroVector
local nowVelocity: Vec3 = Vec3.zeroVector
local nowPosition: Vec3 = nil
local nextVelocity: Vec3 = Vec3.zeroVector
local nextPosition: Vec3 = nil

local wasInGoal: boolean = false
local timeOutOfGoal = 0
local maxTimeOutOfGoal = 2
local timeInGoal = 0
local maxTimeInGoal = 1

local rollingFriction = 0.98
local dampingFactor = 0.5
local GravityScale = -300
local drag = 0.025

local ballGoalMode: number = profile.ballGoalMode
local ballGoalModes = { "Enemy Goal", "Both Goals" }
local BallGoalMode = {
	EnemyGoal = 1,
	BothGoals = 2,
}

-- radius
local radius = profile.radius
local localRadius = radius
local threshold = profile.threshold
local wallDistance = 5

-- no player orbit
local orbitCenter: Vec3 = Vec3.new(0, 0, 0)
local orbitLookAt: Vec3 = Vec3.new(0, 0, 0)
local orbitRadius = 100000
local orbitRotation: Vec3 = Vec3.new(0, -20, 0)
local orbitRotationSpeed = 4

--  Mouse
local rightMouseButton = Input.Key.RightMouseButton
local xMouse = Input.Key.MouseX
local yMouse = Input.Key.MouseY

-- Debug
local debugFaceTheBall: boolean = false

function updateVariables(profileName)
	targetPlayerId = -1
	targetPlayer = nil
	isSelfMuted = false

	profile = config.profiles[profileName]
	radius = profile.radius
	distanceLerp = profile.distanceLerp
	readLocation = profile.readLocation
	cameraMode = profile.cameraMode
	cameraFOV = profile.fieldOfView
	goalMode = profile.goalMode
	showNameTags = profile.showNameTags
	muteSelf = profile.muteSelf
	threshold = profile.threshold
	positionSmoothing = profile.positionSmoothing
	autoGoalCam = profile.autoGoalCam
	autoBall = profile.autoBall
	targetPlayerName = profile.targetPlayerName
	autoBallThreshold = profile.autoBallThreshold
	ballGoalMode = profile.ballGoalMode
	cameraEulerOffset = stringToVec3(profile.cameraEulerOffset)
	cameraPositionOffset = stringToVec3(profile.cameraPositionOffset)
end

function onTransitionBegin()
	alwaysTick = true
	World.clear()
	if wasFollowed then
		wasFollowed = false
		updateVariables(lastUsedProfile)

		-- transition to orbit
		local fromEuler = Quat.fromEuler(orbitRotation.x, orbitRotation.y, orbitRotation.z)
		local direction = fromEuler:getForwardVector()
		camera.position = orbitCenter + -direction * orbitRadius

		camera:lookAt(orbitLookAt, Vec3.upVector)
	end
end

function generateAsterisk(guiLabel: string, isEdited: boolean): string
	if isEdited then
		return `{guiLabel}(*)`
	else
		return guiLabel
	end
end

function getKey(value, table): string
	local key = ""
	for k, v in pairs(table) do
		if v == value then
			key = k
		end
	end
	return key
end

-- clamps every axis in the vector to be between max and min
function Vec3Clamp(vec: Vec3, min: number, max: number): Vec3
	local axises = { x = vec.x, y = vec.y, z = vec.z }

	for axis, value in pairs(axises) do
		if value < min then
			axises[axis] = min
		elseif value > max then
			axises[axis] = max
		end
	end

	vec.x = axises.x
	vec.y = axises.y
	vec.z = axises.z

	return vec
end

function Vec3ClampLength(vec: Vec3, maxLength: number): Vec3
	if vec:length() > maxLength then
		vec = vec:normalize() * maxLength
	end

	return vec
end

function QuatFromVec3(vec: Vec3): Quat
	return Quat.fromEuler(vec.x, vec.y, vec.z)
end

function getReplayFrameFromIndex(replayIndex)
	replayIndex = math.clamp(replayIndex, 0, #Replay.listLoaded())
	if replayIndex > 0 and Replay.getByIndex(replayIndex) then
		return Replay.getByIndex(replayIndex):getCurrentFrame(true)
	else
		-- 0 = live game
		return getGameData()
	end
end

function onGui()
	local readLocationString = ""
	if readLocation > 0 then
		readLocationString = "Replay " .. readLocation
	else
		readLocationString = "Live Game"
	end
	if Gui.beginCombo(gameDataLabel, readLocationString) then
		if Gui.selectable("Live Game", readLocation == 0) then
			readLocation = 0
		end
		for i = 1, #Replay.listLoaded() do
			if Gui.selectable("Replay " .. i, i == readLocation) then
				readLocation = i
			end
		end
		Gui.endCombo()
	end
	Gui.setItemTooltip("Where the camera gets the game data from.")

	local frame = getReplayFrameFromIndex(readLocation)

	if Gui.beginCombo("Profile", lastUsedProfile) then
		local defaultKey = getKey(config.profiles["default"], config.profiles)
		if Gui.selectable("default", defaultKey == lastUsedProfile) then
			lastUsedProfile = defaultKey
			updateVariables(lastUsedProfile)
			muteAll(false)
			profile = config.profiles[lastUsedProfile]
			config.lastUsedProfile = lastUsedProfile
			saveConfig()
		end
		for key, _ in pairs(config.profiles) do
			if key == "default" then
				continue
			end
			if Gui.selectable(key, key == lastUsedProfile) then
				lastUsedProfile = key
				updateVariables(lastUsedProfile)
				muteAll(false)
				profile = config.profiles[lastUsedProfile]
				config.lastUsedProfile = lastUsedProfile
				saveConfig()
			end
		end
		Gui.endCombo()
	end
	Gui.setItemTooltip("The currently selected profile")

	Gui.newLine()

	showNameTags = Gui.checkbox(nametagsLabel, showNameTags)
	if not Gui.isItemActive() then
		nametagsLabel = generateAsterisk("Nametags", showNameTags ~= profile.showNameTags)
	end
	Gui.setItemTooltip("Enable or disable nametags for all players")

	isLeftHanded = Gui.checkbox(isLeftHandedLabel, isLeftHanded)
	if not Gui.isItemActive() then
		isLeftHandedLabel = generateAsterisk("Left Handed", isLeftHanded ~= profile.isLeftHanded)
	end
	Gui.setItemTooltip("Makes you left handed | Used for Hand Held mode")

	muteSelf = Gui.checkbox(muteSelfLabel, muteSelf)
	if not Gui.isItemActive() then
		muteSelfLabel = generateAsterisk("Mute Self", muteSelf ~= profile.muteSelf)
	end
	Gui.setItemTooltip("Enable or disable muting yourself or the player you are currently following")

	--[[focusedArena = Gui.checkbox(focusedArenaLabel, focusedArena)
	if not Gui.isItemActive() then
		focusedArenaLabel = generateAsterisk("Focused Arena", focusedArena ~= profile.focusedArena)
	end
	Gui.setItemTooltip("Mutes all Players OUTSIDE of the Arena the Followed Player is currently in")]]

	targetPlayerName = Gui.inputText(targetPlayerNameLabel, targetPlayerName)
	if not Gui.isItemActive() then
		targetPlayerNameLabel = generateAsterisk("Follow Player", targetPlayerName ~= profile.targetPlayerName)
	end
	Gui.setItemTooltip("The player to follow")

	if Gui.isItemActive() and #frame.players > 0 then
		listActive = true
	end

	if listActive then
		Gui.indent()
		if Gui.beginListBox("Player List") then
			for i = 1, #frame.players do
				local player = frame.players[i]
				local isSelected = false

				if player.playerName == targetPlayerName then
					isSelected = true
				end

				if targetPlayer then
					if
						targetPlayer.playerName ~= targetPlayerName
						and not string.find(string.lower(player.playerName), string.lower(targetPlayerName))
					then
						continue
					end
				else
					if
						not string.find(string.lower(player.playerName), string.lower(targetPlayerName))
						and targetPlayerName ~= "YourName"
					then
						continue
					end
				end

				if
					Gui.selectable(tostring(player.playerName) .. "[" .. tostring(player.playerId) .. "]", isSelected)
				then
					Settings.mutePlayerByName(targetPlayerName, false) -- unmute followed player before switch
					isSelfMuted = not muteSelf
					playerSwitchTime = os.clock()
					teammatesList = {}
					lastTeammatesList = {}
					targetPlayerName = player.playerName
					targetPlayerId = player.playerId
					teamIndex = TeamIndex.NoTeam
				end
			end
			Gui.endListBox()
		end

		if Gui.button(Icon.ArrowLeft) then
			listActive = false
		end

		Gui.unindent()
	end

	cameraFOV = Gui.sliderInt(cameraFOVLabel, cameraFOV, 40, 179)
	if not Gui.isItemActive() then
		cameraFOVLabel = generateAsterisk("Field Of View", cameraFOV ~= profile.fieldOfView)
	end
	Gui.setItemTooltip("The cameras field of view (FOV)")
	cameraFOV = math.clamp(cameraFOV, 40, 179)

	positionSmoothing = Gui.sliderFloat(positionSmoothingLabel, positionSmoothing, 0, 1)
	if not Gui.isItemActive() then
		positionSmoothingLabel = generateAsterisk("Camera Smoothing", positionSmoothing ~= profile.positionSmoothing)
	end
	positionSmoothing = math.clamp(positionSmoothing, 0, 1)
	Gui.setItemTooltip("The time it takes for the Camera to move from A to B")
	Gui.newLine()

	Gui.indent()
	Gui.separatorText("Settings")

	if Gui.beginCombo(cameraModeLabel, cameraModes[cameraMode]) then
		for i = 1, #cameraModes do
			if Gui.selectable(cameraModes[i], i == cameraMode) then
				cameraMode = i
			end
		end
		Gui.endCombo()
	end
	if not Gui.isItemActive() then
		cameraModeLabel = generateAsterisk("Camera Mode", cameraMode ~= profile.cameraMode)
	end
	cameraMode = math.clamp(cameraMode, 1, #cameraModes)
	Gui.setItemTooltip("Changes how the Camera behaves")

	Gui.newLine()

	if cameraMode == CameraMode.FirstPerson then
		Gui.beginDisabled()
	end

	radius = Gui.dragFloat(radiusLabel, radius, 0.5, 0, 100)
	if not Gui.isItemActive() then
		radiusLabel = generateAsterisk("Radius", radius ~= profile.radius)
	end

	if
		Gui.isItemActivated()
		and cameraMode ~= CameraMode.VelocityRotation
		and radius ~= 0
		and cameraMode ~= CameraMode.FirstPerson
	then
		currentPercentage = threshold / radius * 100
	end
	if Gui.isItemActive() and cameraMode ~= CameraMode.VelocityRotation then
		threshold = radius * (currentPercentage / 100)
	end

	radius = math.clamp(radius, 0, 100)
	Gui.setItemTooltip("The radius of the Camera when in 3rd person")

	if cameraMode == CameraMode.VelocityRotation or cameraMode == CameraMode.FaceTheBall then
		Gui.beginDisabled()
	end

	threshold = Gui.sliderFloat(thresholdLabel, threshold, 0, radius)
	if not Gui.isItemActive() then
		thresholdLabel = generateAsterisk("Smart Switch Distance", threshold ~= profile.threshold)
	end
	Gui.setItemTooltip(
		"The distance at which the camera will automatically switch between 1st and 3rd Person (Only works when using Head Rotation)"
	)
	if cameraMode ~= CameraMode.VelocityRotation then
		threshold = math.clamp(threshold, 0, radius)
	end
	if
		cameraMode == CameraMode.VelocityRotation
		or cameraMode == CameraMode.FaceTheBall
		or cameraMode == CameraMode.FirstPerson
	then
		Gui.endDisabled()
	end
	Gui.newLine()
	if cameraMode == CameraMode.VelocityRotation or cameraMode == CameraMode.FaceTheBall then
		Gui.beginDisabled()
	end

	cameraPositionOffset = Gui.dragFloat3(cameraPositionOffsetLabel, cameraPositionOffset, 1, -1000, 1000)
	if not Gui.isItemActive() then
		cameraPositionOffsetLabel = generateAsterisk(
			"Camera Position Offset",
			cameraPositionOffset ~= stringToVec3(profile.cameraPositionOffset)
		)
	end

	cameraPositionOffset = Vec3Clamp(cameraPositionOffset, -1000, 1000)
	Gui.setItemTooltip("The Cameras positional offset. Only applied in mode 'Head Rotation' and 'First Person'")

	cameraEulerOffset = Gui.dragFloat3(cameraEulerOffsetLabel, cameraEulerOffset, 1, -math.huge, math.huge)
	if not Gui.isItemActive() then
		cameraEulerOffsetLabel =
			generateAsterisk("Camera Rotation Offset", cameraEulerOffset ~= stringToVec3(profile.cameraEulerOffset))
	end
	Gui.setItemTooltip("The Cameras rotational offset. Only applied in mode 'Head Rotation'")

	if cameraMode == CameraMode.VelocityRotation or cameraMode == CameraMode.FaceTheBall then
		Gui.endDisabled()
	end

	Gui.newLine()
	local gestureHeaderAsterisk = false
	if Gui.collapsingHeader(gestureControlsHeaderLabel .. "###gesturecontrols") then
		Gui.indent()
		gestureControls = Gui.checkbox(gestureControlsLabel .. "##3", gestureControls)
		if not Gui.isItemActive() then
			gestureControlsLabel = generateAsterisk("Enabled", gestureControls ~= profile.gestureControls)
		end
		Gui.setItemTooltip([[
Be able to grab the camera and throw it to change modes
	- Grab the camera with grip and trigger behind your head
	- Let go without throwing for First Person]])
		if gestureControls then
			if Gui.beginCombo(forwardGestureModeLabel, gestureModes[forwardGestureMode - 1]) then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == forwardGestureMode - 1) then
						forwardGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			if not Gui.isItemActive() then
				forwardGestureModeLabel =
					generateAsterisk("Forward Mode", forwardGestureMode ~= profile.forwardGestureMode)
			end
			forwardGestureMode = math.clamp(forwardGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera forward")

			if Gui.beginCombo(upGestureModeLabel, gestureModes[upGestureMode - 1]) then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == upGestureMode - 1) then
						upGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			if not Gui.isItemActive() then
				upGestureModeLabel = generateAsterisk("Up Mode", upGestureMode ~= profile.upGestureMode)
			end
			upGestureMode = math.clamp(upGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera up")

			if Gui.beginCombo(backwardsGestureModeLabel, gestureModes[backwardsGestureMode - 1]) then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == backwardsGestureMode - 1) then
						backwardsGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			if not Gui.isItemActive() then
				backwardsGestureModeLabel =
					generateAsterisk("Backward Mode", backwardsGestureMode ~= profile.backwardsGestureMode)
			end
			backwardsGestureMode = math.clamp(backwardsGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera backward")
		end
		Gui.unindent()
	end

	-- check for changes in the collapsing header
	if
		backwardsGestureMode ~= profile.backwardsGestureMode
		or upGestureMode ~= profile.upGestureMode
		or forwardGestureMode ~= profile.forwardGestureMode
		or gestureControls ~= profile.gestureControls
	then
		gestureHeaderAsterisk = true
	end
	gestureControlsHeaderLabel = generateAsterisk("Gesture Controls", gestureHeaderAsterisk)

	Gui.newLine()
	Gui.separatorText("Auto Cameras")

	local autoShootingCameraAsterisk = false
	if Gui.collapsingHeader(autoShootingCameraHeaderLabel .. "###autoshootingcamera") then
		Gui.indent()

		autoBall = Gui.checkbox(autoBallLabel, autoBall)
		if not Gui.isItemActive() then
			autoBallLabel = generateAsterisk("Enabled", autoBall ~= profile.autoBall)
		end
		Gui.setItemTooltip(
			"The camera will start Orbiting the Ball for a shot capture when the it detects a possible Shot"
		)

		if autoBall then
			if Gui.beginCombo(ballCamGoalModeLabel, ballGoalModes[ballGoalMode]) then
				for i = 1, #ballGoalModes do
					if Gui.selectable(ballGoalModes[i], i == ballGoalMode) then
						ballGoalMode = i
					end
				end
				Gui.endCombo()
			end
			if not Gui.isItemActive() then
				ballCamGoalModeLabel = generateAsterisk("Ball Goal Mode", ballGoalMode ~= profile.ballGoalMode)
			end
			Gui.setItemTooltip(
				"If the ball camera should only activate when being shot on the enemy goal, or if it should activate on both goals"
			)

			autoBallThreshold = Gui.sliderInt(autoBallThresholdLabel, autoBallThreshold, 10, 15)
			if not Gui.isItemActive() then
				autoBallThresholdLabel =
					generateAsterisk("Toggle Speed (m/s)", autoBallThreshold ~= profile.autoBallThreshold)
			end
			autoBallThreshold = math.clamp(autoBallThreshold, 10, 15)
			Gui.setItemTooltip("The speed of the ball at which the camera switches to a shot capture.")
		end
		Gui.unindent()
	end

	if
		autoBall ~= profile.autoBall
		or ballGoalMode ~= profile.ballGoalMode
		or autoBallThreshold ~= profile.autoBallThreshold
	then
		autoShootingCameraAsterisk = true
	end
	autoShootingCameraHeaderLabel = generateAsterisk("Auto Shooting Camera", autoShootingCameraAsterisk)

	Gui.newLine()

	local goalCameraAsterisk = false
	if Gui.collapsingHeader(goalCameraHeaderLabel .. "###goalcamera") then
		Gui.indent()

		autoGoalCam = Gui.checkbox(autoGoalCamLabel .. "##2", autoGoalCam)
		if not Gui.isItemActive() then
			autoGoalCamLabel = generateAsterisk("Enabled", autoGoalCam ~= profile.autoGoalCam)
		end
		Gui.setItemTooltip("Automatically positions the Camera inside the Goal when Targeted Player is close to Goal")

		if autoGoalCam then
			if Gui.beginCombo(goalModeLabel, goalModes[goalMode]) then
				for i = 1, #goalModes do
					if Gui.selectable(goalModes[i], i == goalMode) then
						goalMode = i
					end
				end
				Gui.endCombo()
			end
			if not Gui.isItemActive() then
				goalModeLabel = generateAsterisk("Mode", goalMode ~= profile.goalMode)
			end
			Gui.setItemTooltip("Determens which Goals to Activate at")

			distanceLerp = Gui.sliderFloat(distanceLerpLabel, distanceLerp, 1, 10)
			if not Gui.isItemActive() then
				distanceLerpLabel = generateAsterisk("Player/Ball Ratio", distanceLerp ~= profile.distanceLerp)
			end
			Gui.setItemTooltip("The Look Ratio between the Player and the Ball. 0 is full Player, 10 is full Ball.")
		end

		Gui.unindent()
	end

	if autoGoalCam ~= profile.autoGoalCam or goalMode ~= profile.goalMode or distanceLerp ~= profile.distanceLerp then
		goalCameraAsterisk = true
	end
	goalCameraHeaderLabel = generateAsterisk("Goal Camera", goalCameraAsterisk)

	Gui.unindent()
	Gui.newLine()

	if confirmationText ~= "" then
		Gui.text(confirmationText)
	end

	if savingNewProfile then
		if Gui.button(`{Icon.ArrowLeft}##New Profile`) then
			savingNewProfile = false
		end
		Gui.sameLine()
		if Gui.button(`{Icon.Check}##New Profile`) then
			if newProfileName == "" or newProfileName == nil then
				confirmationText = "Profile name cannot be empty"
			elseif string.match(newProfileName, "^[%a]+$") == nil then
				confirmationText = "Profile can only contain upper or lowercase letters (a-Z)"
			elseif config.profiles[newProfileName] or newProfileName == "" or newProfileName == nil then
				confirmationText = `Profile {newProfileName} already exists`
				newProfileName = ""
			else
				confirmationText = `Successfully created: "{newProfileName}"`

				config.profiles[newProfileName] = {
					fieldOfView = cameraFOV,
					targetPlayerName = targetPlayerName,
					radius = radius,
					positionSmoothing = positionSmoothing,
					threshold = threshold,
					autoGoalCam = autoGoalCam,
					goalMode = goalMode,
					distanceLerp = distanceLerp,
					cameraMode = cameraMode,
					showNameTags = showNameTags,
					muteSelf = muteSelf,
					gestureControls = gestureControls,
					forwardGestureMode = forwardGestureMode,
					upGestureMode = upGestureMode,
					backwardsGestureMode = backwardsGestureMode,
					readLocation = readLocation,
					autoBall = autoBall,
					autoBallThreshold = autoBallThreshold,
					ballGoalMode = ballGoalMode,
					cameraEulerOffset = tostring(cameraEulerOffset),
					cameraPositionOffset = tostring(cameraPositionOffset),
					isLeftHanded = isLeftHanded,
				}
				lastUsedProfile = newProfileName
				config.lastUsedProfile = lastUsedProfile
				saveConfig()

				profile = config.profiles[newProfileName]

				newProfileName = ""
				savingNewProfile = false
			end
		end
		Gui.sameLine()
		newProfileName = Gui.inputText("Profile Name", newProfileName)
	end

	if deletingProfile then
		confirmationText = `Are you sure you want to DELETE: {lastUsedProfile}?`
		if Gui.button(`Yes DELETE {lastUsedProfile}`) then
			confirmationText = `Successfully Deleted {lastUsedProfile}`
			deletingProfile = false
			config.profiles[lastUsedProfile] = nil
			lastUsedProfile = "default"
			config.lastUsedProfile = lastUsedProfile
			updateVariables(lastUsedProfile)
			saveConfig()
		end
		Gui.sameLine()
		if Gui.button("NO GO BACK") then
			confirmationText = ""
			deletingProfile = false
		end
	end

	if not savingNewProfile and not deletingProfile then
		if Gui.button("Save As Profile " .. Icon.Plus) then
			savingNewProfile = true
		end
		Gui.sameLine()

		if lastUsedProfile == "default" then
			Gui.beginDisabled()
		end

		if Gui.button("Save To Profile " .. Icon.Save) then
			confirmationText = `Saved changes to profile: {lastUsedProfile}`
			config.profiles[lastUsedProfile] = {
				fieldOfView = cameraFOV,
				targetPlayerName = targetPlayerName,
				radius = radius,
				positionSmoothing = positionSmoothing,
				threshold = threshold,
				autoGoalCam = autoGoalCam,
				goalMode = goalMode,
				distanceLerp = distanceLerp,
				cameraMode = cameraMode,
				showNameTags = showNameTags,
				muteSelf = muteSelf,
				gestureControls = gestureControls,
				forwardGestureMode = forwardGestureMode,
				upGestureMode = upGestureMode,
				backwardsGestureMode = backwardsGestureMode,
				readLocation = readLocation,
				autoBall = autoBall,
				autoBallThreshold = autoBallThreshold,
				ballGoalMode = ballGoalMode,
				cameraEulerOffset = tostring(cameraEulerOffset),
				cameraPositionOffset = tostring(cameraPositionOffset),
				isLeftHanded = isLeftHanded,
			}
			profile = config.profiles[lastUsedProfile]
			saveConfig()
		end

		Gui.sameLine()

		if Gui.button("Delete Current Profile " .. Icon.Trash) then
			deletingProfile = true
		end

		if lastUsedProfile == "default" then
			Gui.endDisabled()
		end
	end

	Gui.newLine()
	Gui.separator()

	if Gui.treeNode("Debug") then
		Gui.indent()
		Gui.separatorText("Debug Settings")
		debugBallPrediction = Gui.checkbox("Debug Ball Prediction", debugBallPrediction)
		GravityScale = Gui.dragInt("Gravity", GravityScale, 1, -1000, 0)
		drag = Gui.sliderFloat("Drag", drag, 0, 10)

		Gui.newLine()

		debugFaceTheBall = Gui.checkbox("Debug Face The Ball", debugFaceTheBall)
		Gui.unindent()
		Gui.indent()
		Gui.separatorText("Info")
		Gui.indent()
		if Gui.treeNode("Camera") then
			Gui.text("Camera Position (pre-smoothed): " .. tostring(camera.position))
			Gui.text("Camera Position (post-smoothed): " .. tostring(camera:getSmoothedPosition()))
			Gui.text("Camera Rotation: " .. tostring(camera.rotation:euler()))
			Gui.treePop()
		end
		if Gui.treeNode("Player") then
			Gui.text("Player Name: " .. tostring(playerNameInfo))
			Gui.text("Player ID: " .. tostring(playerIdInfo))
			Gui.text("Head Position: " .. tostring(headPosition))
			Gui.text("Head Rotation: " .. tostring(headRotation:euler()))
			Gui.text("Player Velocity: " .. tostring(playerVelocity))
			Gui.text("Is Local Player: " .. tostring(isLocalPlayer))
			Gui.text("Team Index: " .. tostring(teamIndex))
			Gui.treePop()
		end
		if Gui.treeNode("Ball") then
			Gui.text("Ball Position: " .. tostring(ballPosition))
			Gui.text("Ball Rotation: " .. tostring(ballRotation:euler()))
			Gui.text("Ball Velocity: " .. tostring(ballVelocity))
			Gui.text("Ball Velocity Length: " .. tostring(ballVelocity:length()))
			Gui.text("Ball Arena: " .. tostring(ballArena))
			Gui.treePop()
		end
		if Gui.treeNode("Arena") then
			Gui.text("Arena Name: " .. arena.name)
			Gui.text("Arena Position: " .. tostring(arena.position))
			Gui.text("Arena Rotation: " .. tostring(arena.rotation:euler()))
			Gui.treePop()
		end
		if Gui.treeNode("Other") then
			Gui.text("Temporary Radius: " .. tostring(localRadius))
			Gui.text("Distance: " .. tostring(distance))
			Gui.text("Ball Distance: " .. tostring(getDist(headPosition, ballPosition)))
			Gui.treePop()
		end
		Gui.text("Version: " .. version)

		Gui.newLine()
		Gui.unindent()
		Gui.treePop()
	end
end

function toggleSmoothing(position: boolean, rotation: boolean)
	if position then
		camera.positionSmoothing = positionSmoothing
	else
		camera.positionSmoothing = 0
	end
	if rotation then
		camera.rotationSmoothing = rotationSmoothing
	else
		camera.rotationSmoothing = 0
	end
end

function isBetweenVector(n: Vec3, min: Vec3, max: Vec3, up: Vec3): boolean
	local nHeight = n:dot(up)
	local minHeight = min:dot(up)
	local maxHeight = max:dot(up)

	return nHeight >= minHeight and nHeight <= maxHeight
end

function isBetween(n: number, min: number, max: number): boolean
	if n > min and n < max then
		return true
	else
		return false
	end
end

function getForward(positionA: Vec3, positionB: Vec3): Vec3
	local forward: Vec3 = Vec3.new((positionB.x - positionA.x), (positionB.y - positionA.y), positionB.z - positionA.z)
		:normalize()
	return forward
end

function updateRay(startPosition: Vec3, endPosition: Vec3): RayHit
	local forward: Vec3 = getForward(endPosition, startPosition)
	local backwards: Vec3 = Vec3.new(-forward.x, -forward.y, -forward.z)
	local hit: RayHit = camera:castRay(startPosition, endPosition + (backwards * 10))
	return hit
end

function getDist(point1: Vec3, point2: Vec3): number
	local x: number = math.abs(point1.x - point2.x) ^ 2
	local y: number = math.abs(point1.y - point2.y) ^ 2
	local z: number = (point1.z - point2.z) ^ 2
	return math.sqrt(x + y + z)
end

function decodePoseBits(poseBits)
	return {
		ThumbDown = bit32.band(poseBits, 1) ~= 0, -- True if thumb on face of controller (Touch sensor)
		TriggerDown = bit32.band(poseBits, bit32.lshift(1, 1)) ~= 0, -- True if Trigger is pressed down
		TriggerPoint = bit32.band(poseBits, bit32.lshift(1, 2)) ~= 0, -- True if finger is not on trigger (Touch sensor)
		GripDown = bit32.band(poseBits, bit32.lshift(1, 3)) ~= 0, -- True if Grip is pressed down
		FullHandPoseOverride = bit32.rshift(poseBits, 4) % 16,
	}
end

function getClosestArena(targetPosition: Vec3): Arena -- Remove this function when/if we get the arena from the player
	local closestArenaDistance = math.huge
	local closestArena = nil
	for _, arena in pairs(arenas) do
		local distance = getDist(targetPosition, arena.position)
		-- because some arenas are directly above others
		-- we limit the arenas to those where the player is between the arenas floor and roof position
		if
			not isBetweenVector(
				targetPosition,
				arena.position + (arena.rotation:getUpVector() * arenaFloorOffset),
				arena.position + (arena.rotation:getUpVector() * arenaRoofOffset),
				arena.rotation:getUpVector()
			)
		then
			continue
		end
		if distance < closestArenaDistance then
			closestArenaDistance = distance
			closestArena = arena
		end
	end

	-- if the camera is placed in such a way that it is not leveled with any arena we loop again without limiting height
	if closestArena == nil then
		for _, arena in pairs(arenas) do
			local distance = getDist(targetPosition, arena.position)
			if distance < closestArenaDistance then
				closestArenaDistance = distance
				closestArena = arena
			end
		end
	end

	return closestArena
end

function getClosestArenaBall(targetPosition: Vec3, frameData: ReplayFrame)
	local balls = frameData.balls
	local closestBallDistance = math.huge
	local closestBall: ReplayBall = nil
	for _, ball in balls do
		local ballType = parseBallJSON(ball:toJson()).type
		if ballType == 2 then
			continue -- ball is not arena ball
		end
		if
			not isBetweenVector(
				ball.transform.position,
				arena.position + (arena.rotation:getUpVector() * arenaFloorOffset),
				arena.position + (arena.rotation:getUpVector() * arenaRoofOffset),
				arena.rotation:getUpVector()
			)
		then
			continue -- ball is not in the correct arena
		end

		local ballDistance = getDist(targetPosition, ball.transform.position)
		if ballDistance < closestBallDistance then
			closestBallDistance = ballDistance
			closestBall = ball
		end
	end

	return closestBall
end

function getClosestBall(targetPosition: Vec3, frameData: ReplayFrame)
	local balls = frameData.balls
	local closestBallDistance = math.huge
	local clostestBall: ReplayBall = nil
	for i in balls do
		local ball = balls[i]
		local distance = getDist(targetPosition, ball.transform.position)
		if distance < closestBallDistance then
			closestBallDistance = distance
			clostestBall = ball
		end
	end
	return clostestBall
end

function registeredHit(position: Vec3, rotation: Quat, hitPosition: Vec3, smartSwitch: boolean): number?
	local distance = getDist(position, hitPosition) / 10
	if distance < threshold and smartSwitch then
		firstPerson(position, nil, rotation)
		return
	else
		distance -= wallDistance

		if distance < 0 then
			distance += wallDistance
		end

		distance = math.clamp(distance, 0, radius)
		return distance
	end
end

-- more like just offsetHit, this should run before normal hit detection, and change the offset accordingly
function registeredOffsetHit(position: Vec3, offset: Vec3): Vec3
	local startPosition = headPosition
	local endPosition = position + (offset + offset:normalize() * 20)

	local hit = camera:castRay(startPosition, endPosition)

	if hit.successful then
		local distance = startPosition - hit.position - (getForward(startPosition, endPosition) * -20)

		offset = Vec3ClampLength(offset, distance:length())
	end

	return offset
end

function updatePlayerData(player: ReplayPlayer, frame: ReplayFrame)
	playerVelocity = player.velocity
	isLocalPlayer = player.isLocalPlayer
	playerNameInfo = player.playerName
	playerIdInfo = tostring(player.playerId)

	if teamIndex ~= player.teamIndex then
		teamIndex = player.teamIndex
		arena = getClosestArena(player.root.position)
	end

	--teamLists(frame)
end

function mouseRotationOffset()
	cameraEulerOffset += Vec3.new(0, Input.getAnalog(yMouse), Input.getAnalog(xMouse))
end

function rotationPivotPosition(position: Vec3, rotation: Quat, radius: number): Vec3
	local pivotPosition = Vec3.zeroVector
	local rotationQuat = rotation * Quat.fromEuler(cameraEulerOffset.x, cameraEulerOffset.y, cameraEulerOffset.z)
	radius *= 10
	local cameraDirection = rotationQuat:getForwardVector()

	pivotPosition = position + -cameraDirection * radius

	return pivotPosition
end

function velocityPivotPosition(position: Vec3, velocity: Vec3, radius: number, ball: boolean): Vec3
	local velocityPivot = Vec3.zeroVector
	radius *= 10

	local cameraDirection = velocity:getSafeNormal()
	if not ball then
		cameraDirection = -cameraDirection
	end

	velocityPivot = position + cameraDirection * radius

	return velocityPivot
end

function twoPointPivotPosition(point1: Vec3, point2: Vec3, radius: number): Vec3
	local pivotPosition = Vec3.zeroVector
	local direction = getForward(point1, point2)
	direction.z = math.clamp(direction.z, -0.8, 0.8)
	radius *= 10
	pivotPosition = point1 + -direction * radius

	return pivotPosition
end

function faceTheBallPivotPosition(position: Vec3, playerBox: BoxType, ballPosition: Vec3, radius: number): Vec3
	local faceTheBallPosition = Vec3.zeroVector

	local closestPointToBall = playerBox:getClosestPoint(ballPosition, false)

	local direction = getForward(closestPointToBall, ballPosition)
	radius *= 10

	if debugFaceTheBall then
		World.drawLine(closestPointToBall, closestPointToBall + (direction * 50), 0, 1, 0, 10, 0)
	end

	faceTheBallPosition = position + -direction * radius

	return faceTheBallPosition
end

function updateBallData(ball: ReplayBall, seconds: number)
	ballPosition = ball.transform.position
	ballRotation = ball.transform.rotation
	ballArena = ball.arena
	ballVelocity = ball.velocity
end

function teamLists(frame: ReplayFrame)
	local tempTeamList: { string } = {}
	if teamIndex == TeamIndex.NoTeam then
		lastTeammatesList = teammatesList
		teammatesList = {}
		return
	end

	for _, player in frame.players do
		if player.teamIndex == TeamIndex.NoTeam then
			continue
		end
		local closestArena = getClosestArena(player.root.position)

		if closestArena.name ~= arena.name then
			continue
		end

		table.insert(tempTeamList, player.playerName)
	end

	lastTeammatesList = teammatesList
	teammatesList = tempTeamList
end

function isGrabbingCamera(player: ReplayPlayer): Transform?
	local leftHandPosition = player.root.position + player.root.rotation:rotateVector(player.leftHand.position)
	local leftPoseFlags = decodePoseBits(player.leftHandPosebits)
	local rightHandPosition = player.root.position + player.root.rotation:rotateVector(player.rightHand.position)
	local rightPoseFlags = decodePoseBits(player.rightHandPosebits)

	-- Left hand grab logic
	if
		not leftHandGrabbing
		and leftPoseFlags.GripDown
		and leftPoseFlags.TriggerDown
		and leftPoseFlags.FullHandPoseOverride ~= HandPose.GrabBall
	then
		if
			(cameraMode == CameraMode.HandHeld and isLeftHanded and not wasInGoal and not cameraInGoal)
			or player.head.rotation:getForwardVector():dot(getForward(player.head.position, leftHandPosition))
				< -0.2
		then
			grabTimers.left += deltaTime
			if grabTimers.left >= 0.2 then
				leftHandGrabbing = true
				releaseTimers.left = 0
			end
		end
	else
		grabTimers.left = 0
	end

	if leftHandGrabbing and (not leftPoseFlags.GripDown or not leftPoseFlags.TriggerDown) then
		leftHandGrabbing = false
	end

	if previousLeftHandGrabbing and leftHandGrabbing then
		local leftHandRotation: Quat = player.root.rotation * player.leftHand.rotation
		local leftHandTransform = Transform.identity
		leftHandTransform.position = leftHandPosition
		leftHandTransform.rotation = leftHandRotation

		throwVelocity = player.root.rotation:rotateVector(player.leftHand.position) - lastGrabPosition

		lastGrabPosition = player.root.rotation:rotateVector(player.leftHand.position)

		return leftHandTransform
	elseif previousLeftHandGrabbing and not leftHandGrabbing then
		if releaseTimers.left < maxLetGoTime then
			if throwVelocity:length() < 0.1 then
				throwVelocity = Vec3.zeroVector
				releaseTimers.left = maxLetGoTime + deltaTime -- No throw, end instantly
			end
			local leftHandTransform = Transform.identity
			leftHandTransform.position = Vec3.lerp(
				leftHandPosition,
				leftHandPosition + Vec3ClampLength((throwVelocity * throwBoost), 500),
				releaseTimers.left / maxLetGoTime
			)
			if throwVelocity ~= Vec3.zeroVector then
				leftHandTransform.rotation = Quat.fromXZ(throwVelocity:normalize(), player.head.rotation:getUpVector())
			else
				local leftHandRotation: Quat = player.root.rotation * player.leftHand.rotation
				leftHandTransform.rotation = leftHandRotation
			end

			releaseTimers.left += deltaTime

			return leftHandTransform
		end
	end

	-- Right hand grab logic
	if
		not rightHandGrabbing
		and rightPoseFlags.GripDown
		and rightPoseFlags.TriggerDown
		and rightPoseFlags.FullHandPoseOverride ~= HandPose.GrabBall
	then
		if
			(cameraMode == CameraMode.HandHeld and not isLeftHanded and not wasInGoal and not cameraInGoal)
			or player.head.rotation:getForwardVector():dot(getForward(player.head.position, rightHandPosition))
				< -0.2
		then
			grabTimers.right += deltaTime
			if grabTimers.right >= maxGrabTime then
				rightHandGrabbing = true
				releaseTimers.right = 0
			end
		end
	else
		grabTimers.right = 0
	end

	if rightHandGrabbing and (not rightPoseFlags.GripDown or not rightPoseFlags.TriggerDown) then
		rightHandGrabbing = false
	end

	if previousRightHandGrabbing and rightHandGrabbing then
		local rightHandRotation: Quat = player.root.rotation * player.rightHand.rotation
		local rightHandTransform = Transform.identity
		rightHandTransform.position = rightHandPosition
		rightHandTransform.rotation = rightHandRotation

		throwVelocity = player.root.rotation:rotateVector(player.rightHand.position) - lastGrabPosition

		lastGrabPosition = player.root.rotation:rotateVector(player.rightHand.position)

		return rightHandTransform
	elseif previousRightHandGrabbing and not rightHandGrabbing then
		if releaseTimers.right < maxLetGoTime then
			local rightHandTransform = Transform.identity
			if throwVelocity:length() < 0.1 then
				throwVelocity = Vec3.zeroVector
				releaseTimers.right = maxLetGoTime + deltaTime -- No throw, end instantly
			end
			rightHandTransform.position = Vec3.lerp(
				rightHandPosition,
				rightHandPosition + Vec3ClampLength((throwVelocity * throwBoost), 500),
				releaseTimers.right / maxLetGoTime
			)
			if throwVelocity ~= Vec3.zeroVector then
				local forwardLook = throwVelocity:normalize()
				rightHandTransform.rotation = Quat.fromXZ(-forwardLook, player.head.rotation:getUpVector())
			else
				local rightHandRotation: Quat = player.root.rotation * player.rightHand.rotation
				rightHandTransform.rotation = rightHandRotation
			end

			releaseTimers.right += deltaTime

			return rightHandTransform
		end
	end

	previousLeftHandGrabbing = leftHandGrabbing
	previousRightHandGrabbing = rightHandGrabbing

	return nil
end

function grabbingCamera(player: ReplayPlayer, grabHand: Transform)
	toggleSmoothing(true, true)
	camera.hideNearestHead = false

	camera.position = grabHand.position
	camera.rotation = grabHand.rotation

	if rightHandGrabbing or leftHandGrabbing then
		return
	end

	if (throwVelocity:length() * 100) < 2.5 then
		local headDistance = getDist(camera.position, player.head.position)
		local leftHandDistance =
			getDist(camera.position, player.root.position + player.root.rotation:rotateVector(player.leftHand.position))
		local rightHandDistance = getDist(
			camera.position,
			player.root.position + player.root.rotation:rotateVector(player.rightHand.position)
		)

		if headDistance <= 20 then
			cameraMode = CameraMode.FirstPerson
		elseif leftHandDistance <= 10 then
			if leftHandDistance <= 0.1 and rightHandDistance <= 1.5 then
				isLeftHanded = false
			else
				isLeftHanded = true
			end
			cameraMode = CameraMode.HandHeld
		elseif rightHandDistance <= 10 then
			if rightHandDistance <= 0.1 and leftHandDistance <= 1.5 then
				isLeftHanded = true
			else
				isLeftHanded = false
			end
			cameraMode = CameraMode.HandHeld
		end

		return
	end

	local playerForward = player.root.rotation:getForwardVector()
	local playerUp = player.root.rotation:getUpVector()
	local playerBackwards = -playerForward

	local forwardDot = playerForward:dot(throwVelocity:normalize())
	local upDot = playerUp:dot(throwVelocity:normalize())
	local backwardsDot = playerBackwards:dot(throwVelocity:normalize())

	local dotProducts = {
		{ name = "forward", value = forwardDot },
		{ name = "up", value = upDot },
		{ name = "backwards", value = backwardsDot },
	}

	local biggestDotValue = -1
	local biggestDotName = "up"

	for _, dot in dotProducts do
		if dot.value > biggestDotValue then
			biggestDotValue = dot.value
			biggestDotName = dot.name
		end
	end

	if biggestDotName == "forward" then
		cameraMode = CameraMode.VelocityRotation
	elseif biggestDotName == "up" then
		cameraMode = CameraMode.FaceTheBall
	elseif biggestDotName == "backwards" then
		cameraMode = CameraMode.HeadRotation
	end
end

function calculateAcceleration(currentVelocity, dt)
	local dragForce = currentVelocity * -drag
	local dragLoss = dragForce / 0.21
	local gravityAcceleration = Vec3.new(0, 0, GravityScale)

	local acceleration = dragLoss + gravityAcceleration
	return acceleration
end
function NextVelocity(currentVelocity: Vec3, acceleration: Vec3, dt): Vec3
	local realDrag = drag * dt
	local calculatedNextVelocity = currentVelocity + acceleration * dt
	local linDamping = calculatedNextVelocity * -realDrag
	linDamping.z = 0
	calculatedNextVelocity += linDamping
	return calculatedNextVelocity
end

function NextPosition(position: Vec3, velocity: Vec3, acceleration: Vec3, dt: number)
	local accelerationTerm = acceleration * (0.5 * (dt * dt))
	return position + velocity * dt + accelerationTerm
end

-- Function to calculate the velocity after a bounce
function calculateBounce(velocity: Vec3, surfaceNormal: Vec3)
	-- Reflect the velocity vector based on the surface normal
	local dotProduct: number = velocity:dot(surfaceNormal)

	local reflectedVelocity = velocity - (surfaceNormal * (2 * dotProduct))

	if math.abs(reflectedVelocity.z) < 50 then
		reflectedVelocity.z = 0
	else
		reflectedVelocity = reflectedVelocity * dampingFactor
	end

	return reflectedVelocity
end

function applyRollingFriction(velocity)
	if velocity.z == 0 then
		-- Apply friction to the horizontal components (x and y)
		velocity.x = velocity.x * rollingFriction
		velocity.y = velocity.y * rollingFriction
	end

	return velocity
end

function calculatePrediction(dt: number)
	acceleration = calculateAcceleration(nowVelocity, dt)
	nextVelocity = NextVelocity(nowVelocity, acceleration, dt)
	nextPosition = NextPosition(nowPosition, nextVelocity, acceleration, dt)

	local hit: RayHit = camera:castRay(nowPosition, nextPosition)

	if hit.successful then
		local ballRadiusOffset = hit.normal * 40

		-- draw normals
		if debugBallPrediction then
			World.drawLine(
				hit.position + ballRadiusOffset,
				hit.position + ballRadiusOffset + (hit.normal * 100),
				1,
				0,
				0,
				10,
				0
			)
		end

		nextPosition = hit.position + ballRadiusOffset

		nextVelocity = calculateBounce(nextVelocity, hit.normal)
	end
end

function isInGoal(): boolean
	local homeBox: BoxType = Box.new(
		arena.home.goal.position + (arena.rotation:getForwardVector() * 135),
		Vec3.new(100, 500, 225),
		arena.rotation
	)
	local awayBox: BoxType = Box.new(
		arena.away.goal.position - (arena.rotation:getForwardVector() * 135),
		Vec3.new(100, 500, 225),
		arena.rotation
	)

	if debugBallPrediction then
		homeBox:render(1, 0, 0)
		awayBox:render(0, 0, 1)
	end

	if homeBox:checkPointIntersect(ballPosition) or awayBox:checkPointIntersect(ballPosition) then
		return false
	end

	if homeBox:checkPointIntersect(nowPosition) then
		if
			ballGoalMode == BallGoalMode.BothGoals
			or teamIndex == TeamIndex.AwayTeam and ballGoalMode == BallGoalMode.EnemyGoal
		then
			return true
		end
	end

	if awayBox:checkPointIntersect(nowPosition) then
		if
			ballGoalMode == BallGoalMode.BothGoals
			or teamIndex == TeamIndex.HomeTeam and ballGoalMode == BallGoalMode.EnemyGoal
		then
			return true
		end
	end

	return false
end

function predictBall()
	local dt = 0.1

	if debugBallPrediction and true then
		World.clear()
	end

	nowPosition = ballPosition
	nowVelocity = ballVelocity

	acceleration = calculateAcceleration(nowVelocity, dt)

	local wasInGoalThisLoop = false

	if isInGoal() then
		wasInGoalThisLoop = true
		timeOutOfGoal = 0
	end

	calculatePrediction(dt)

	if debugBallPrediction and true then
		--World.drawPoint(nextPosition, 1, 0, 0, 50, 0)
		World.drawLine(ballPosition, nextPosition, 1, 0, 0, 10, 0)
	end

	for i = 1, 50, 1 do
		nowPosition = nextPosition
		nowVelocity = nextVelocity

		if isInGoal() then
			wasInGoalThisLoop = true
			timeOutOfGoal = 0
		end

		calculatePrediction(dt)

		if debugBallPrediction and true then
			--World.drawPoint(nextPosition, 0, 1, 0, 50, 0)
			World.drawLine(nowPosition, nextPosition, 0, 1, 0, 10, 0)
		end
	end

	if wasInGoalThisLoop then
		timeInGoal += deltaTime
	else
		timeOutOfGoal += deltaTime
	end

	if timeInGoal >= maxTimeInGoal then
		wasInGoal = true
	end

	if timeOutOfGoal >= maxTimeOutOfGoal then
		timeInGoal = 0
		wasInGoal = false
	end
end

function ballCam(radius: number, rotation: Quat)
	if instaRotateBall then
		toggleSmoothing(false, false)
		instaRotateBall = false
		doneOnceBall = true
	else
		toggleSmoothing(true, true)
	end

	if radius < 10 then
		radius = 10
	end

	local hitEnd = velocityPivotPosition(ballPosition, ballVelocity, radius, false)
	hit = updateRay(ballPosition, hitEnd)

	if hit.successful then
		if registeredHit(ballPosition, rotation, hit.position, false) == nil then
			return
		end
		localRadius = registeredHit(ballPosition, rotation, hit.position, false)
	else
		localRadius = radius
	end

	camera.position = velocityPivotPosition(ballPosition, ballVelocity, localRadius, false)
	camera.hideNearestHead = false
	camera:lookAt(ballPosition, gravityUpDirection)
end

function goalCam(targetPosition: Vec3, defaultRotation: Quat)
	if instaRotate then
		toggleSmoothing(false, false)
		instaRotate = false
		doneOnce = true
	else
		toggleSmoothing(false, true)
	end

	camera.position = targetPosition
	camera.fieldOfView = goalCamFOV

	local cameraRotation = defaultRotation

	local ballDirection = getForward(camera.position, ballPosition)
	local horizontallyAlignedBallDirection = (ballDirection - ballDirection:projectOnTo(gravity.upDirection)):normalize()
	local ballCameraAlignment = arena.rotation:getForwardVector():dot(horizontallyAlignedBallDirection)

	local isBallLeft = math.abs(ballCameraAlignment) < 0.7
		and camera.rotation:getRightVector():dot(horizontallyAlignedBallDirection) < 0
	local isBallRight = math.abs(ballCameraAlignment) < 0.7
		and camera.rotation:getRightVector():dot(horizontallyAlignedBallDirection) > 0

	if isBallLeft then
		cameraRotation *= Quat.fromEuler(0, 0, -25)
	elseif isBallRight then
		cameraRotation *= Quat.fromEuler(0, 0, 25)
	end

	local bridgeLine = arena.position + arena.rotation:getUpVector() * bridgeHeightOffset
	local haloLine = arena.position + arena.rotation:getUpVector() * haloHeightOffset
	local ballIsOverBridge = arena.rotation:getUpVector():dot(getForward(bridgeLine, ballPosition)) > 0
	local ballIsOverHalo = arena.rotation:getUpVector():dot(getForward(haloLine, ballPosition)) > 0

	if ballIsOverHalo then
		cameraRotation *= overHaloRotation
	elseif ballIsOverBridge then
		cameraRotation *= overBridgeRotation
	else
		cameraRotation *= underBridgeRotation
	end

	camera.rotation = cameraRotation
end

function firstPerson(position: Vec3, offsetPosition: Vec3?, rotation: Quat)
	if not cameraTransition then
		toggleSmoothing(false, true)
	end

	if offsetPosition ~= nil then
		offsetPosition = rotation:rotateVector(offsetPosition)
		offsetPosition = registeredOffsetHit(position, offsetPosition)
		position += offsetPosition
	end

	if offsetPosition == nil or offsetPosition == Vec3.zeroVector then
		local offsetForMicFix = rotation:rotateVector(Vec3.new(0.01, 0, 0))
		position += offsetForMicFix
	end

	local offsetDistance = getDist(headPosition, position)
	if offsetDistance >= 50 then
		camera.hideNearestHead = false
	else
		camera.hideNearestHead = true
	end
	camera.position = position
	camera.rotation = rotation
end

function thirdPerson(position: Vec3, offsetPosition: Vec3?, rotation: Quat, smartSwitch: boolean)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	if offsetPosition ~= nil then
		offsetPosition = rotation:rotateVector(offsetPosition)
		offsetPosition = registeredOffsetHit(position, offsetPosition)
		position += offsetPosition
	end

	local hitEnd = rotationPivotPosition(position, rotation, radius)
	hit = updateRay(position, hitEnd)

	if Input.getKey(rightMouseButton) then
		smartSwitch = false
		mouseRotationOffset()
	end

	if hit.successful then
		if registeredHit(position, rotation, hit.position, smartSwitch) == nil then
			return
		end
		localRadius = registeredHit(position, rotation, hit.position, smartSwitch)
	else
		localRadius = radius
	end

	camera.position = rotationPivotPosition(position, rotation, localRadius)
	camera.hideNearestHead = false
	camera:lookAt(position, gravityUpDirection)
end

function thirdPersonVelocity(position: Vec3, velocity: Vec3, rotation: Quat)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	local hitEnd = velocityPivotPosition(position, velocity, radius, false)
	hit = updateRay(position, hitEnd)

	if velocity:length() < 600 then
		thirdPerson(position, nil, rotation, true)
		return
	end

	if hit.successful then
		if registeredHit(position, rotation, hit.position, false) == nil then
			return
		end
		localRadius = registeredHit(position, rotation, hit.position, false)
	else
		localRadius = radius
	end

	camera.position = velocityPivotPosition(position, velocity, localRadius, false)
	camera.hideNearestHead = false
	camera:lookAt(position, gravityUpDirection)
end

function thirdPersonFacingBall(player: ReplayPlayer, offsetPosition: Vec3)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	local offset = player.head.rotation:rotateVector(Vec3.new(0, 0, 50))
	local position = player.head.position + offset

	local horizontalVelocity = player.velocity - player.velocity:projectOnTo(gravity.upDirection)

	local headForward = player.head.rotation:getForwardVector()
	local alignedHeadDirection = headForward - gravity.upDirection * headForward:dot(gravity.upDirection)
	alignedHeadDirection = alignedHeadDirection:normalize()

	local directionAlignment = playerChestRotation:getForwardVector():dot(alignedHeadDirection)

	if directionAlignment >= -0.9 or directionAlignment <= 0.9 then
		playerChestRotation = Quat.fromXZ(alignedHeadDirection, gravity.upDirection)
	end

	local verticalOffset = player.root.rotation:rotateVector(Vec3.new(0, 0, -50))
	local horizontalOffset = playerChestRotation:getForwardVector()
		* -math.clamp(
			player.velocity:length() * math.sign(playerChestRotation:getForwardVector():dot(horizontalVelocity)),
			10,
			40
		)

	local playerBox: BoxType =
		Box.new(player.root.position + verticalOffset + horizontalOffset, Vec3.new(5, 50, 100), playerChestRotation)

	if debugFaceTheBall then
		World.clear()
		playerBox:render(0.7, 0.15, 0.15)
	end

	if offsetPosition ~= nil then
		offsetPosition = registeredOffsetHit(position, offsetPosition)
		position += offsetPosition
	end

	local hitEnd = faceTheBallPivotPosition(position, playerBox, ballPosition, radius)
	hit = updateRay(position, hitEnd)

	if hit.successful then
		if registeredHit(position, player.head.rotation, hit.position, false) == nil then
			return
		end
		localRadius = registeredHit(position, player.head.rotation, hit.position, false)
	else
		localRadius = radius
	end

	camera.position = faceTheBallPivotPosition(position, playerBox, ballPosition, localRadius)
	camera.hideNearestHead = false
	camera:lookAt(position, gravityUpDirection)
end

function checkFlip(rightHandTransform: Transform, rightHandPosebits, leftHandTransform: Transform, leftHandPosebits)
	if flipTime < maxFlipTime then
		handHeldRotationOffset =
			Quat.slerp(previousHandHeldRotationOffset, nextHandHeldRotationOffset, flipTime / maxFlipTime)
		flipTime += deltaTime
		return
	end

	local leftHandPose = decodePoseBits(leftHandPosebits)
	local rightHandPose = decodePoseBits(rightHandPosebits)

	local leftHandVelocity = leftHandTransform.position - previousLeftHandPosition
	local rightHandVelocity = rightHandTransform.position - previousRightHandPosition

	local rightDot = leftHandTransform.rotation:getRightVector():dot(rightHandVelocity:normalize())
	local leftDot = rightHandTransform.rotation:getRightVector():dot(leftHandVelocity:normalize())

	if isLeftHanded then
		local handForward = leftHandTransform.rotation:getForwardVector()
		local otherHandDirection = getForward(leftHandTransform.position, rightHandTransform.position)
		local handDistance = getDist(leftHandTransform.position, rightHandTransform.position)

		if
			rightHandPose.GripDown
			and rightHandPose.TriggerDown
			and rightHandVelocity:length() >= 1
			and otherHandDirection:dot(-handForward) > 0.75
			and handDistance <= 30
		then
			if rightDot > 0.8 or rightDot < -0.8 then
				flipTime = 0
				previousHandHeldRotationOffset = handHeldRotationOffset
				nextHandHeldRotationOffset = handHeldRotationOffset * Quat.fromEuler(0, 0, 180 * -math.sign(rightDot))
			end
		end
	else
		local handForward = rightHandTransform.rotation:getForwardVector()
		local otherHandDirection = getForward(rightHandTransform.position, leftHandTransform.position)
		local handDistance = getDist(leftHandTransform.position, rightHandTransform.position)

		if
			leftHandPose.GripDown
			and leftHandPose.TriggerDown
			and leftHandVelocity:length() >= 1
			and otherHandDirection:dot(-handForward) > 0.75
			and handDistance <= 30
		then
			if leftDot > 0.8 or leftDot < -0.8 then
				flipTime = 0
				previousHandHeldRotationOffset = handHeldRotationOffset
				nextHandHeldRotationOffset = handHeldRotationOffset * Quat.fromEuler(0, 0, 180 * -math.sign(leftDot))
			end
		end
	end
end

function handHeld(player: ReplayPlayer)
	if not cameraTransition then
		toggleSmoothing(false, true)
	end

	local positionOffset = Vec3.new(5, 0, 10)

	local rightHandPosition = player.root.position + player.root.rotation:rotateVector(player.rightHand.position)
	local rightHandRotation = player.root.rotation * player.rightHand.rotation
	local leftHandPosition = player.root.position + player.root.rotation:rotateVector(player.leftHand.position)
	local leftHandRotation = player.root.rotation * player.leftHand.rotation

	local leftTransform = Transform.identity
	leftTransform.position = leftHandPosition
	leftTransform.rotation = leftHandRotation
	local rightTransform = Transform.identity
	rightTransform.position = rightHandPosition
	rightTransform.rotation = rightHandRotation
	checkFlip(rightTransform, player.rightHandPosebits, leftTransform, player.leftHandPosebits)

	-- check if leftHanded
	if isLeftHanded then
		camera.position = leftHandPosition + leftHandRotation:rotateVector(positionOffset)
		camera.rotation = leftHandRotation * handHeldRotationOffset
	else
		camera.position = rightHandPosition + rightHandRotation:rotateVector(positionOffset)
		camera.rotation = rightHandRotation * handHeldRotationOffset
	end

	previousLeftHandPosition = leftHandPosition
	previousRightHandPosition = rightHandPosition
end

function withPlayer(player: ReplayPlayer)
	camera.showNameTags = showNameTags
	local homeGoal = arena.home.goal
	local awayGoal = arena.away.goal

	-- check for gesture controls
	if gestureControls then
		-- Check for camera grab
		local grabHand: Transform? = isGrabbingCamera(player)
		if grabHand ~= nil then
			grabbingCamera(player, grabHand)
			return
		end
	end

	if autoGoalCam and not ballTarget then
		if
			not cameraInAwayGoal
			and getDist(awayGoal.position, player.root.position) < enterGoalCamDist
			and teamIndex ~= TeamIndex.NoTeam
		then
			if goalMode == GoalMode.MyGoal and teamIndex == TeamIndex.AwayTeam or goalMode == GoalMode.BothGoals then
				if not doneOnce then
					instaRotate = true
				end
				cameraInAwayGoal = true
				cameraInGoal = true
			end
		end

		if
			not cameraInHomeGoal
			and getDist(homeGoal.position, player.root.position) < enterGoalCamDist
			and teamIndex ~= TeamIndex.NoTeam
		then
			if goalMode == GoalMode.MyGoal and teamIndex == TeamIndex.HomeTeam or goalMode == GoalMode.BothGoals then
				if not doneOnce then
					instaRotate = true
				end
				cameraInHomeGoal = true
				cameraInGoal = true
			end
		end

		if cameraInAwayGoal and getDist(awayGoal.position, player.root.position) > exitGoalCamDist then
			cameraInAwayGoal = false
			cameraInGoal = false
		end

		if cameraInHomeGoal and getDist(homeGoal.position, player.root.position) > exitGoalCamDist then
			cameraInHomeGoal = false
			cameraInGoal = false
		end

		if cameraInAwayGoal then
			goalCam(arena.away.goalCam.position, arena.away.goalCam.rotation)
			return
		elseif cameraInHomeGoal then
			goalCam(arena.home.goalCam.position, arena.home.goalCam.rotation)
			return
		end
	end

	if cameraInGoal and not autoGoalCam then
		cameraInAwayGoal = false
		cameraInHomeGoal = false
		cameraInGoal = false
	end

	if doneOnce then
		doneOnce = false
	end

	if autoBall then
		if ballVelocity:length() > 100 * autoBallThreshold and not ballTarget and teamIndex ~= TeamIndex.NoTeam then
			ballTarget = true
		end

		if ballVelocity:length() < 500 and ballTarget or teamIndex == TeamIndex.NoTeam then
			timeInGoal = 0
			ballTarget = false
			wasInGoal = false
		end

		ballTarget = true

		if ballTarget then
			predictBall()

			if wasInGoal then
				if not doneOnceBall then
					instaRotateBall = true
				end
				ballCam(30, Quat.identity)
				return
			end
		end
	else
		ballTarget = false
	end

	if doneOnceBall then
		doneOnceBall = false
	end

	headRotation = player.head.rotation
	headPosition = player.head.position

	if previousCameraMode ~= cameraMode or previousTargetPlayerId ~= targetPlayerId then
		toggleSmoothing(false, false)
		cameraTransition = true
	elseif cameraTransition then
		cameraTransition = false
	end

	camera.fieldOfView = cameraFOV
	if radius == 0 and cameraMode ~= CameraMode.HandHeld then
		firstPerson(headPosition, cameraPositionOffset, headRotation * QuatFromVec3(cameraEulerOffset))
	elseif cameraMode == CameraMode.HeadRotation then
		thirdPerson(headPosition, cameraPositionOffset, headRotation, true)
	elseif cameraMode == CameraMode.VelocityRotation then
		thirdPersonVelocity(headPosition, player.velocity, headRotation)
	elseif cameraMode == CameraMode.FaceTheBall then
		if teamIndex ~= TeamIndex.NoTeam then
			thirdPersonFacingBall(player, Vec3.zeroVector)
		else
			thirdPerson(headPosition, cameraPositionOffset, headRotation, false)
		end
	elseif cameraMode == CameraMode.HandHeld then
		handHeld(player)
	else
		firstPerson(headPosition, cameraPositionOffset, headRotation * QuatFromVec3(cameraEulerOffset))
	end
end

function noPlayerOrbit(dt: number)
	local fromEuler = Quat.fromEuler(orbitRotation.x, orbitRotation.y, orbitRotation.z)
	local direction = fromEuler:getForwardVector()

	camera.position = orbitCenter + -direction * orbitRadius
	gravityUpDirection = gravity.upDirection

	camera:lookAtBasic(Vec3.zeroVector)
	orbitRotation.z -= dt * orbitRotationSpeed
end

function configureVOIP()
	local frame = getGameData() -- always do VOIP on live data | Replays don't have VOIP

	if not focusedArena and lastFocusedArena then
		-- focused arena got turned off
		print("focused arena off")
		if muteSelf then
			local toMuteList = frame.players
			table.remove(toMuteList, table.find(toMuteList, targetPlayer.playerName))
			muteList(false, toMuteList)
		else
			muteAll(false)
		end
	end

	if not muteSelf and isSelfMuted then
		if os.clock() >= playerSwitchTime + muteDelay then -- need this delay for muting to work when switching between players for some reason
			isSelfMuted = not Settings.mutePlayerByName(targetPlayer.playerName, muteSelf)
		end
	end

	if focusedArena and (#lastTeammatesList == 0 and #teammatesList > 0) then
		-- entered arena
		print("entered arena")
		local toMuteList: { string } = frame.players
		for _, playerName in teammatesList do
			table.remove(toMuteList, table.find(toMuteList, playerName))
		end

		if muteSelf then
			table.remove(teammatesList, table.find(teammatesList, targetPlayer.playerName))
			table.insert(toMuteList, targetPlayer.playerName)
		end

		muteList(true, toMuteList)
		muteList(false, teammatesList)
	end

	if focusedArena and (#teammatesList == 0 and #lastTeammatesList > 0) then
		-- left arena
		print("left arena")
		if muteSelf then
			local toMuteList = frame.players
			table.remove(toMuteList, table.find(toMuteList, targetPlayer.playerName))
			muteList(false, toMuteList)
		else
			muteAll(false)
		end
	end

	if focusedArena and teamIndex ~= TeamIndex.NoTeam and #lastServerPlayerList > 0 then
		for _, currentPlayer in frame.players do
			local tryFindPlayer = table.find(lastServerPlayerList, currentPlayer.playerId)

			if tryFindPlayer == nil and currentPlayer.playerName ~= tostring(currentPlayer.playerId) then
				-- this is spamming try string lists with playernames instead of ReplayPlayer lists
				print(`new server player: {currentPlayer.playerName}`)
				-- new player joined server
				-- possibly won't work while the new players name is their playerID
				Settings.mutePlayerByName(currentPlayer.playerName, true)
			end
		end
	end

	if muteSelf and not isSelfMuted then
		if os.clock() >= playerSwitchTime + muteDelay then
			isSelfMuted = Settings.mutePlayerByName(targetPlayer.playerName, muteSelf)
		end
	end

	for _, teammateName in teammatesList do
		local tryFindTeammate = table.find(lastTeammatesList, teammateName)

		if focusedArena and tryFindTeammate == nil then
			-- new player joined arena
			print(`arena join`)
			Settings.mutePlayerByName(teammateName, false)
		end
	end

	for _, teammateName in lastTeammatesList do
		local tryFindLastTeammate = table.find(teammatesList, teammateName)

		if focusedArena and tryFindLastTeammate == nil then
			-- player left the arena
			print(`arena leave`)
			Settings.mutePlayerByName(teammateName, true)
		end
	end

	lastServerPlayerList = {}
	for _, player in frame.players do
		-- ignore newely joined players that don't have their name yet as they can't be muted (maybe, better safe than sorry)
		if player.playerName == tostring(player.playerId) then
			continue
		end

		table.insert(lastServerPlayerList, player.playerId)
	end
	lastFocusedArena = focusedArena
end

function tick(dt)
	if not camera.isActive and not camera.isFollowed then
		alwaysTick = false
		onExit()
		return
	end

	deltaTime = dt
	local frame = getReplayFrameFromIndex(readLocation)

	if #frame.players == 0 or (targetPlayerId == -1 and (targetPlayerName == nil or targetPlayerName == "")) then
		noPlayerOrbit(dt)
		return
	end

	if targetPlayerId > -1 then
		targetPlayer = frame:getPlayerById(targetPlayerId)
	end

	if targetPlayer == nil then
		targetPlayer = frame:getPlayerByName(targetPlayerName)
		if targetPlayer then
			targetPlayerId = targetPlayer.playerId
		end
	end

	if targetPlayer == nil then
		noPlayerOrbit(dt)
		return
	end

	updatePlayerData(targetPlayer, frame)

	local ball = nil
	if arena == nil or targetPlayer.teamIndex == TeamIndex.NoTeam then
		ball = getClosestBall(targetPlayer.root.position, frame)
	else
		ball = getClosestArenaBall(arena.position, frame)
	end

	gravityUpDirection = targetPlayer.root.rotation:getUpVector()
	updateBallData(ball, dt)
	withPlayer(targetPlayer)
	configureVOIP()
	previousCameraMode = cameraMode
	previousTargetPlayerId = targetPlayerId
end

function onExit()
	camera.showNameTags = true
	camera.hideNearestHead = false
	camera.nearClippingPlane = 0.001
	muteAll(false)
end

function onMessageReceived(messageTable)
	-- only accept tables
	if type(messageTable) ~= "table" then
		return
	end

	-- receiving a msg will be interperated as the camera being followed
	wasFollowed = true

	-- callback is a function that takes this cameras GUI as a parameter to receive for the messenger. This is usefull for displaying the same GUI in multiple cameras.
	if messageTable.callback ~= nil then
		messageTable.callback(onGui())
	end
	-- readLocation is a number representing where to retrive data from, anything above 0 is a replay file. Trying to access a replay file that doesn't exist does nothing.
	if messageTable.readLocation then
		readLocation = messageTable.readLocation
	end
	-- showNameTags is a boolean that decides whether or not to show name tags above players heads
	if messageTable.showNameTags ~= nil then
		showNameTags = messageTable.showNameTags
	end
	-- isLeftHanded is a boolean that helps decide whether or not to put the camera on the left hand when using Hand Held camera mode. This value might change dynamically if gesture controlls are on.
	if messageTable.isLeftHanded ~= nil then
		isLeftHanded = messageTable.isLeftHanded
	end
	-- muteSelf is a boolean that when set to true makes the camera unable to hear the followed player talk in game.
	if messageTable.muteSelf ~= nil then
		muteSelf = messageTable.muteSelf
	end
	-- targetPlayerName is a string used for getting the player you want to follow. if this is empty or unable to find the name typed in it follows noone.
	if messageTable.targetPlayerName then
		if messageTable.targetPlayerName ~= targetPlayerName then
			targetPlayerId = -1
			targetPlayer = nil
		end
		targetPlayerName = messageTable.targetPlayerName
	end
	-- targetPlayerId is a number used for getting the player you want to follow. If anything bigger than -1 this will be used instead of targetPlayerName if it finds a player with the corresponding ID.
	if messageTable.targetPlayerId then
		targetPlayerId = messageTable.targetPlayerId
	end
	-- cameraFOV is a number that sets the camera FOV, the number can be set between 40 and 179
	if messageTable.cameraFOV then
		cameraFOV = messageTable.cameraFOV
		cameraFOV = math.clamp(cameraFOV, 40, 179)
	end
	-- positionSmoothing is a number that sets the cameras positions smoothing, the number can be set between 0.000 and 1.000
	if messageTable.positionSmoothing then
		positionSmoothing = messageTable.positionSmoothing
	end
	-- cameraMode is a number that sets the cameras follow mode. There are currently 4 modes, and the first one starts at 1.
	if messageTable.cameraMode then
		cameraMode = messageTable.cameraMode
	end
	-- radius is a number that sets the distance of the camera when in any 3rd person camera mode. You are still able to change the value if you are not in a 3rd person camera mode.
	if messageTable.radius then
		radius = messageTable.radius
	end
	-- threshold is a number that determens wether the head rotation camera mode should switch to the first person camera mode based on the cameras distance from the players head. This only works in camera mode head rotation.
	if messageTable.threshold then
		threshold = messageTable.threshold
	end
	-- cameraPositionOffset is a Vec3 that adds a positional offset to the First Person and Head Rotation camera modes. The positional offset only takes affect when in First Person or Head Rotation mode.
	if messageTable.cameraPositionOffset then
		cameraPositionOffset = stringToVec3(messageTable.cameraPositionOffset)
	end
	-- cameraEulerOffset is a Vec3 that adds a rotational offset to the First Person and Head Rotation camera modes. The rotational offset only takes affect when in First Person or Head Rotation mode.
	if messageTable.cameraEulerOffset then
		cameraEulerOffset = stringToVec3(messageTable.cameraEulerOffset)
	end
	-- gestureControls is a boolean that enables/disables gesture controlls which allow the player being followed to grab their camera and switch camera modes in game.
	if messageTable.gestureControls ~= nil then
		gestureControls = messageTable.gestureControls
	end
	-- forwardGestureMode is a number that sets the cameras mode when the forwards gesture is used. Gesture modes can only be between numbers 2 and 4.
	if messageTable.forwardGestureMode then
		if messageTable.forwardGestureMode == 1 or messageTable.forwardGestureMode == 5 then
			return -- Don't accept firstPerson or handheld as a gesture mode
		end
		forwardGestureMode = messageTable.forwardGestureMode
	end
	-- upGestureMode is a number that sets the cameras mode when the upwards gesture is used. Gesture modes can only be between numbers 2 and 4.
	if messageTable.upGestureMode then
		if messageTable.upGestureMode == 1 or messageTable.upGestureMode == 5 then
			return -- Don't accept firstPerson or handheld as a gesture mode
		end
		upGestureMode = messageTable.upGestureMode
	end
	-- backwardsGestureMode is a number that sets the cameras mode when the backwards gesture is used. Gesture modes can only be between numbers 2 and 4.
	if messageTable.backwardsGestureMode then
		if messageTable.backwardsGestureMode == 1 or messageTable.backwardsGestureMode == 5 then
			return -- Don't accept firstPerson or handheld as a gesture mode
		end
		backwardsGestureMode = messageTable.backwardsGestureMode
	end
	-- autoBall is a boolean that determens wether the auto shooting camera is enabled or not. You are still able to change values assotiated with the auto shooting camera even if the auto shooting camera is disabled.
	if messageTable.autoBall ~= nil then
		autoBall = messageTable.autoBall
	end
	-- autoBallThreshold is a number that determens when the auto shooting camera should activate based on the currently tracked balls speed in m/s. Value can be set between 10 and 20.
	if messageTable.autoBallThreshold then
		autoBallThreshold = messageTable.autoBallThreshold
	end
	-- ballGoalMode is a number that determens whether the auto shooting camera should activate based on what goal is being shot at. (1 = Enemy Goal, 2 = Both Goals)
	if messageTable.ballGoalMode then
		ballGoalMode = messageTable.ballGoalMode
	end
	-- autoGoalCam is a boolean that determens wether the auto goal camera is enabled or not.  You are still able to change values assotiated with the auto goal camera even if the auto goal camera is disabled.
	if messageTable.autoGoalCam ~= nil then
		autoGoalCam = messageTable.autoGoalCam
	end
	-- goalMode is a number that determens which goals the auto goal camera should activate on. There are two modes, and the first one starts at 1.
	if messageTable.goalMode then
		goalMode = messageTable.goalMode
	end
	if messageTable.hideNearestHead then
		camera.hideNearestHead = messageTable.hideNearestHead
	end
end

-- Optimizations:
--[[
	fps needs more testing. Previous assumptions of 40fps lower than freecam has not been replicated.
	current utilization testing has not found any hickups in the code.
]]

-- Mute self fixes:
--[[
	Supposedly cracks in the code where muting still won't work.
	Needs fixing.
]]

-- Auto Record Replay:
--[[
	When the ball is placed in the middle, start replay recording.
	When the ball is placed in the middle again, stop and start a new replay recording.
	If the follow player leaves the arena, stop replay recording.
	If you exit the camera, stop replay recording.
]]
