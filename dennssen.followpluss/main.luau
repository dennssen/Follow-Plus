--!strict
local _version: string = "1.13.0"

-- Feature:
-- When using Head Rotation (possibly other 3rd person modes) and hold down right click, the player gets full control over the rotation of the 3rd person mode by using their mouse until they let go of right click.
-- Add content props support
-- Add overlay support

-- dependecies
local Util = require("util")

local Emotes = require("emotes")
type Emote = Emotes.Emote
type Emotes = Emotes.Emotes

local Box = require("box")
type BoxType = typeof(Box)

type GoalCamData = {
	goalCam: { position: Vec3, rotation: Quat },
}

local Arena = require("arena")
type Arena<ArenaData, HomeData, AwayData> = Arena.Arena<ArenaData, HomeData, AwayData>
type FollowArena = Arena<{}, GoalCamData, GoalCamData> & {
	checkGoalCam: (self: FollowArena, player: ReplayPlayer) -> boolean,
	goalCam: (self: FollowArena, goalPosition: Vec3, goalRotation: Quat) -> (),
}

local BallSim = require("ballsim")

local frame: ReplayFrame
local hasTickedOnce: boolean = false

local CameraMode = {
	FirstPerson = 1,
	HeadRotation = 2,
	VelocityRotation = 3,
	FaceTheBall = 4,
	HandHeld = 5,
}

local collisions: boolean = true
local cameraAnchor: Vec3 = Vec3.zeroVector
local cameraAnchorOffset: Vec3 = Vec3.zeroVector
local cameraPivotOffset: Vec3 = Vec3.zeroVector
local targetCameraPivotOffset: Vec3 = Vec3.zeroVector
local cameraPosition: Vec3 = Vec3.zeroVector
local cameraRotation: Quat = Quat.identity

function setCameraPosition(anchor: Vec3, anchorOffset: Vec3, pivotOffset: Vec3)
	if pivotOffset == Vec3.zeroVector then
		cameraPivotOffset = pivotOffset
		targetCameraPivotOffset = pivotOffset
	end

	cameraAnchor = anchor
	cameraAnchorOffset = anchorOffset
	targetCameraPivotOffset = pivotOffset
	moveCamera()
end

function setCameraRotation(rotation: Quat)
	cameraRotation = rotation
end

--(A2.Vector){ 0.000000, 0.000000, -180.000000 }
function stringToVec3(string: string): Vec3
	local x: string? | number, y: string? | number, z: string? | number =
		string.match(string, "%{ ([%d.-]+), ([%d.-]+), ([%d.-]+) %}")
	if not x or not y or not z then
		return Vec3.zeroVector
	end

	x = tonumber(x)
	y = tonumber(y)
	z = tonumber(z)

	local vec = Vec3.new(x :: number, y :: number, z :: number)
	return vec
end

function muteAll(mute: boolean, debug: boolean?)
	local frame = getGameData()
	for _, player in frame.players do
		local muted = Settings.mutePlayerByName(player.playerName, mute)

		if debug then
			print(`Tried to mute/unmute {player.playerName} with a success of: {muted}`)
		end
	end
end

function muteList(mute: boolean, players: { ReplayPlayer }, debug: boolean?)
	for _, player: ReplayPlayer in players do
		local muted = Settings.mutePlayerByName(player.playerName, mute)

		if debug then
			print(`Tried to mute/unmute {player.playerName} with a success of: {muted}`)
		end
	end
end

local function initializeProfiles()
	local saveToConfig = false
	local neededValues = {
		radius = 20,
		distanceLerp = 4,
		readLocation = 0,
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
		simResolutionScale = 0.2,
		simTimeLength = 4,
		targetPlayerName = "YourName",
		cameraMode = CameraMode.HeadRotation,
		muteSelf = false,
		gestureControls = false,
		forwardGestureMode = CameraMode.VelocityRotation,
		upGestureMode = CameraMode.FaceTheBall,
		backwardsGestureMode = CameraMode.HeadRotation,
		focusedArena = false,
		isLeftHanded = false,
		showQuests = true,
		autoRecordReplays = false,
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
local readLocation = profile.readLocation -- 0: Live, 1 or above: Replay

-- Replay Recording
local autoRecordReplays: boolean = profile.autoRecordReplays and Settings.getLuauReplayControlAllowed()
local isRecordingReplay: boolean = false
local debugAutoRecord: boolean = false

function startRecording(debugMessage: string?)
	if not autoRecordReplays or not Settings.getLuauReplayControlAllowed() then
		return
	end

	if isRecordingReplay or readLocation ~= 0 then
		return
	end

	if debugAutoRecord then
		print(`start recording | {debugMessage}`)
		isRecordingReplay = true
		return
	end

	if Replay.startRecording() then
		isRecordingReplay = true
	end
end

function stopRecording(debugMessage: string?)
	if not isRecordingReplay then
		return
	end

	if debugAutoRecord then
		print(`stop recording | {debugMessage}`)
		isRecordingReplay = false
		return
	end

	if Replay.stopRecording() then
		isRecordingReplay = false
	end
end

-- VOIP
local isSelfMuted = false
local muteSelf = profile.muteSelf
local focusedArena = false
local lastFocusedArena = focusedArena

-- goal
local goalCamFOV = 120

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

-- ball
local ballPosition: Vec3 = Vec3.zeroVector
local ballRotation: Quat = Quat.identity
local ballVelocity: Vec3 = Vec3.zeroVector
local ballArena: number = nil
local autoBall = profile.autoBall
BallSim.resolutionScale = profile.simResolutionScale
BallSim.pathLengthSeconds = profile.simTimeLength
local doneOnceBall = false
local instaRotateBall = false

local isFollowingBall: boolean = false
local followBallStart: number = 0
local minBallFollowTime: number = 1.3

local ballGoalMode: number = profile.ballGoalMode
local ballGoalModes = { "Enemy Goal", "Both Goals" }
local BallGoalMode = {
	EnemyGoal = 1,
	BothGoals = 2,
}

-- player
local targetPlayer: ReplayPlayer? = nil
local targetPlayerName = profile.targetPlayerName
local previousTargetPlayerId = -1
local hidePlayerHead: boolean = false
local headPosition: Vec3 = Vec3.new(0, 0, 0)
local headRotation: Quat = Quat.identity
local playerVelocity = Vec3.zeroVector
local playerChestRotation: Quat = Quat.identity
local isLocalPlayer = false
local teamIndex = -1

local previousLeftHandPosition: Vec3 = Vec3.zeroVector
local previousRightHandPosition: Vec3 = Vec3.zeroVector
local isLeftHanded: boolean = profile.isLeftHanded
local playerSwitchTime: number = 0
local muteDelay: number = 1

local lastServerPlayerList: { number } = {}
local lastTeammatesList: { ReplayPlayer } = {}
local teammatesList: { ReplayPlayer } = {}

local cachedGamemodeAmount: number = 0

local FollowArena = {} :: FollowArena
FollowArena.__index = FollowArena
setmetatable(FollowArena, { __index = Arena })

function FollowArena:onRoundStartHook()
	if not targetPlayer or targetPlayer.teamIndex == Util.TeamIndex.NoTeam then
		return
	end

	startRecording("round start")
end

function FollowArena:onRoundEndHook(_isRestart: boolean, _homeScore: number, _awayScore: number)
	stopRecording("round end")
end

type Arena3v3 = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
	goalCamPositionOffset: Vec3,
	bridgeHeightOffset: number,
	haloHeightOffset: number,
	underBridgeRotation: Quat,
	overBridgeRotation: Quat,
	overHaloRotation: Quat,
	enterGoalCamDist: number,
	exitGoalCamDist: number,
}

local Arena3v3 = {} :: Arena3v3
Arena3v3.__index = Arena3v3
setmetatable(Arena3v3, { __index = FollowArena })

Arena3v3.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Arena3v3.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Arena3v3.boxSize = Vec3.new(5100, 6750, 1440)
Arena3v3.boxOffset = Vec3.new(0, 0, 650)
Arena3v3.centerBoxOffset = Vec3.new(0, 0, 300)
Arena3v3.goalBoxSize = Vec3.new(100, 500, 225)
Arena3v3.goalPositionOffset = Vec3.new(3285, 0, 175)
Arena3v3.goalCamPositionOffset = Vec3.new(3330, 0, 250)
Arena3v3.bridgeHeightOffset = 245
Arena3v3.haloHeightOffset = 580
Arena3v3.underBridgeRotation = Quat.fromEuler(0, -40, 0)
Arena3v3.overBridgeRotation = Quat.fromEuler(0, -20, 0)
Arena3v3.overHaloRotation = Quat.identity
Arena3v3.enterGoalCamDist = 500
Arena3v3.exitGoalCamDist = 750

function Arena3v3.new(gamemode: ModuleStateSpectatorLuaApi): FollowArena
	local self: FollowArena = setmetatable(FollowArena.new(gamemode, readLocation), Arena3v3) :: any
	self.type = "3v3"
	self.name = self.slotId:gsub("TKB_", "")

	self.home.data = { goalCam = {
		position = Vec3.zeroVector,
		rotation = Quat.identity,
	} }
	self.away.data = { goalCam = {
		position = Vec3.zeroVector,
		rotation = Quat.identity,
	} }

	self:setupDimensions()
	return self :: Arena3v3
end

function Arena3v3:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = (self.transform.rotation * Arena3v3.homeRotationOffset):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	if homeDirection:dot(ballDirection) >= 0 then
		return true
	else
		return false
	end
end

function Arena3v3:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena3v3.boxOffset),
		Arena3v3.boxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Arena3v3.homeRotationOffset):rotateVector(Arena3v3.goalPositionOffset),
		rotation = self.transform.rotation * Arena3v3.homeRotationOffset:inverse(),
		box = Box.empty,
	}

	self.home.goal.box = Box.new(self.home.goal.position, Arena3v3.goalBoxSize, self.home.goal.rotation)

	self.home.data.goalCam = {
		position = self.transform.position
			+ (self.transform.rotation * Arena3v3.homeRotationOffset):rotateVector(Arena3v3.goalCamPositionOffset),
		rotation = self.home.goal.rotation,
	}

	self.away.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Arena3v3.awayRotationOffset):rotateVector(Arena3v3.goalPositionOffset),
		rotation = self.transform.rotation * Arena3v3.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Arena3v3.goalBoxSize, self.away.goal.rotation)

	self.away.data.goalCam = {
		position = self.transform.position
			+ (self.transform.rotation * Arena3v3.awayRotationOffset):rotateVector(Arena3v3.goalCamPositionOffset),
		rotation = self.away.goal.rotation,
	}
end

function Arena3v3:getTeamRotation(teamIndex: number): Quat
	local rotation = Quat.identity
	if teamIndex == Util.TeamIndex.HomeTeam then
		rotation = self.transform.rotation * Arena3v3.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		rotation = self.transform.rotation * Arena3v3.awayRotationOffset
	end

	return rotation
end

function Arena3v3:checkGoalCam(player: ReplayPlayer): boolean
	if
		not cameraInAwayGoal
		and Util.getDist(self.away.goal.position, player.root.position) < Arena3v3.enterGoalCamDist
		and player.teamIndex ~= Util.TeamIndex.NoTeam
	then
		if
			goalMode == GoalMode.MyGoal and player.teamIndex == Util.TeamIndex.AwayTeam
			or goalMode == GoalMode.BothGoals
		then
			if not doneOnce then
				instaRotate = true
			end
			cameraInAwayGoal = true
			cameraInGoal = true
		end
	end

	if
		not cameraInHomeGoal
		and Util.getDist(self.home.goal.position, player.root.position) < Arena3v3.enterGoalCamDist
		and player.teamIndex ~= Util.TeamIndex.NoTeam
	then
		if
			goalMode == GoalMode.MyGoal and player.teamIndex == Util.TeamIndex.HomeTeam
			or goalMode == GoalMode.BothGoals
		then
			if not doneOnce then
				instaRotate = true
			end
			cameraInHomeGoal = true
			cameraInGoal = true
		end
	end

	if cameraInAwayGoal and Util.getDist(self.away.goal.position, player.root.position) > Arena3v3.exitGoalCamDist then
		cameraInAwayGoal = false
		cameraInGoal = false
	end

	if cameraInHomeGoal and Util.getDist(self.home.goal.position, player.root.position) > Arena3v3.exitGoalCamDist then
		cameraInHomeGoal = false
		cameraInGoal = false
	end

	if cameraInAwayGoal then
		self:goalCam(self.away.data.goalCam.position, self.away.data.goalCam.rotation)
		return true
	elseif cameraInHomeGoal then
		self:goalCam(self.home.data.goalCam.position, self.home.data.goalCam.rotation)
		return true
	end

	return false
end

function Arena3v3:goalCam(goalPosition: Vec3, goalRotation: Quat)
	if instaRotate then
		toggleSmoothing(false, false)
		instaRotate = false
		doneOnce = true
	else
		toggleSmoothing(false, true)
	end

	camera.fieldOfView = goalCamFOV

	local rotation = goalRotation

	local ballDirection = Util.getForward(cameraPosition, ballPosition)
	local horizontallyAlignedBallDirection = (ballDirection - ballDirection:projectOnTo(gravity.upDirection)):normalize()
	local ballCameraAlignment = self.transform.rotation:getForwardVector():dot(horizontallyAlignedBallDirection)

	local isBallLeft = math.abs(ballCameraAlignment) < 0.7
		and cameraRotation:getRightVector():dot(horizontallyAlignedBallDirection) < 0
	local isBallRight = math.abs(ballCameraAlignment) < 0.7
		and cameraRotation:getRightVector():dot(horizontallyAlignedBallDirection) > 0

	if isBallLeft then
		rotation *= Quat.fromEuler(0, 0, -25)
	elseif isBallRight then
		rotation *= Quat.fromEuler(0, 0, 25)
	end

	local bridgeLine = self.transform.position + self.transform.rotation:getUpVector() * Arena3v3.bridgeHeightOffset
	local haloLine = self.transform.position + self.transform.rotation:getUpVector() * Arena3v3.haloHeightOffset
	local ballIsOverBridge = self.transform.rotation:getUpVector():dot(Util.getForward(bridgeLine, ballPosition)) > 0
	local ballIsOverHalo = self.transform.rotation:getUpVector():dot(Util.getForward(haloLine, ballPosition)) > 0

	if ballIsOverHalo then
		rotation *= Arena3v3.overHaloRotation
	elseif ballIsOverBridge then
		rotation *= Arena3v3.overBridgeRotation
	else
		rotation *= Arena3v3.underBridgeRotation
	end

	setCameraRotation(rotation)
	setCameraPosition(goalPosition, Vec3.zeroVector, Vec3.zeroVector)
end

function Arena3v3:GUIChangeDimensions()
	Arena3v3.boxSize = Gui.dragFloat3("Arena3v3 Arena Size", Arena3v3.boxSize, 1, -math.huge, math.huge)
	Arena3v3.boxOffset = Gui.dragFloat3("Arena3v3 Position Offset", Arena3v3.boxOffset, 1, -math.huge, math.huge)
	Arena3v3.centerBoxOffset =
		Gui.dragFloat3("Arena3v3 Place Ball Box Position Offset", Arena3v3.centerBoxOffset, 1, -math.huge, math.huge)
	Arena3v3.goalBoxSize = Gui.dragFloat3("Arena3v3 Goal Size", Arena3v3.goalBoxSize, 1, -math.huge, math.huge)
	Arena3v3.goalPositionOffset =
		Gui.dragFloat3("Arena3v3 Goal Position Offset", Arena3v3.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena3v3.boxSize}`)
		print(`boxOffset: {Arena3v3.boxOffset}`)
		print(`centerBoxOffset: {Arena3v3.centerBoxOffset}`)
		print(`goalBoxSize: {Arena3v3.goalBoxSize}`)
		print(`goalPositionOffset: {Arena3v3.goalPositionOffset}`)
	end

	self:setupDimensions()
end

type Arena4v4 = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
}

local Arena4v4 = {} :: Arena4v4
Arena4v4.__index = Arena4v4
setmetatable(Arena4v4, { __index = FollowArena })

Arena4v4.homeRotationOffset = Quat.fromEuler(0, 0, -90)
Arena4v4.awayRotationOffset = Quat.fromEuler(0, 0, 90)
Arena4v4.boxSize = Vec3.new(6110, 8400, 1490)
Arena4v4.boxOffset = Vec3.new(0, 0, 600)
Arena4v4.centerBoxOffset = Vec3.new(0, 0, 250)
Arena4v4.goalBoxSize = Vec3.new(200, 450, 225)
Arena4v4.goalPositionOffset = Vec3.new(4075, 0, 175)

function Arena4v4.new(gamemode: ModuleStateSpectatorLuaApi): FollowArena
	local self: FollowArena = setmetatable(Arena.new(gamemode, readLocation), Arena4v4) :: any
	self.type = "4v4"

	local name: string = ""

	if self.slotId:find("TKB") then
		name = self.slotId:gsub("TKB_", "")
	else
		local nameEnd = self.slotId:find("_") :: number
		name = `{self.slotId:sub(1, nameEnd - 1)} {self.slotId:sub(self.slotId:len() - 2)}`
	end

	self.name = name
	self:setupDimensions()
	return self :: Arena4v4
end

function Arena4v4:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = (self.transform.rotation * Arena4v4.homeRotationOffset):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	if homeDirection:dot(ballDirection) >= 0 then
		return true
	else
		return false
	end
end

function Arena4v4:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Arena4v4.boxOffset),
		Arena4v4.boxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Arena4v4.homeRotationOffset):rotateVector(Arena4v4.goalPositionOffset),
		rotation = self.transform.rotation * Arena4v4.homeRotationOffset:inverse(),
		box = Box.empty,
	}

	self.home.goal.box = Box.new(self.home.goal.position, Arena4v4.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Arena4v4.awayRotationOffset):rotateVector(Arena4v4.goalPositionOffset),
		rotation = self.transform.rotation * Arena4v4.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Arena4v4.goalBoxSize, self.away.goal.rotation)
end

function Arena4v4:getTeamRotation(teamIndex: number): Quat
	local rotation = Quat.identity
	if teamIndex == Util.TeamIndex.HomeTeam then
		rotation = self.transform.rotation * Arena4v4.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		rotation = self.transform.rotation * Arena4v4.awayRotationOffset
	end

	return rotation
end

function Arena4v4:checkGoalCam(player: ReplayPlayer): boolean
	return false
end

function Arena4v4:GUIChangeDimensions()
	Arena4v4.boxSize = Gui.dragFloat3("Arena4v4 Arena Size", Arena4v4.boxSize, 1, -math.huge, math.huge)
	Arena4v4.boxOffset = Gui.dragFloat3("Arena4v4 Position Offset", Arena4v4.boxOffset, 1, -math.huge, math.huge)
	Arena4v4.centerBoxOffset =
		Gui.dragFloat3("Arena4v4 Place Ball Box Position Offset", Arena4v4.centerBoxOffset, 1, -math.huge, math.huge)
	Arena4v4.goalBoxSize = Gui.dragFloat3("Arena4v4 Goal Size", Arena4v4.goalBoxSize, 1, -math.huge, math.huge)
	Arena4v4.goalPositionOffset =
		Gui.dragFloat3("Arena4v4 Goal Position Offset", Arena4v4.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena4v4.boxSize}`)
		print(`boxOffset: {Arena4v4.boxOffset}`)
		print(`centerBoxOffset: {Arena4v4.centerBoxOffset}`)
		print(`goalBoxSize: {Arena4v4.goalBoxSize}`)
		print(`goalPositionOffset: {Arena4v4.goalPositionOffset}`)
	end

	self:setupDimensions()
end

type Driftblitz = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
}

local Driftblitz = {} :: Driftblitz
Driftblitz.__index = Driftblitz
setmetatable(Driftblitz, { __index = FollowArena })

Driftblitz.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Driftblitz.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Driftblitz.boxSize = Vec3.new(7270, 11825, 1440)
Driftblitz.boxOffset = Vec3.new(0, 0, 740)
Driftblitz.centerBoxOffset = Vec3.new(0, 0, 100)
Driftblitz.goalBoxSize = Vec3.new(100, 890, 300)
Driftblitz.goalPositionOffset = Vec3.new(5295, 0, 175)

function Driftblitz.new(gamemode: ModuleStateSpectatorLuaApi): FollowArena
	local self = setmetatable(FollowArena.new(gamemode, readLocation), Driftblitz) :: any
	self.name = self.slotId
	self.type = "driftblitz"
	self:setupDimensions()
	return self :: Driftblitz
end

function Driftblitz:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = (self.transform.rotation * Driftblitz.homeRotationOffset):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	if homeDirection:dot(ballDirection) >= 0 then
		return true
	else
		return false
	end
end

function Driftblitz:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Driftblitz.boxOffset),
		Driftblitz.boxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Driftblitz.homeRotationOffset):rotateVector(Driftblitz.goalPositionOffset),
		rotation = self.transform.rotation * Driftblitz.homeRotationOffset:inverse(),
		box = Box.empty,
	}

	self.home.goal.box = Box.new(self.home.goal.position, Driftblitz.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position
			+ (self.transform.rotation * Driftblitz.awayRotationOffset):rotateVector(Driftblitz.goalPositionOffset),
		rotation = self.transform.rotation * Driftblitz.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, Driftblitz.goalBoxSize, self.away.goal.rotation)
end

function Driftblitz:getTeamRotation(teamIndex: number): Quat
	local rotation = Quat.identity
	if teamIndex == Util.TeamIndex.HomeTeam then
		rotation = self.transform.rotation * Driftblitz.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		rotation = self.transform.rotation * Driftblitz.awayRotationOffset
	end

	return rotation
end

function Driftblitz:checkGoalCam(player: ReplayPlayer): boolean
	return false
end

function Driftblitz:GUIChangeDimensions()
	Driftblitz.boxSize = Gui.dragFloat3("Driftblitz Arena Size", Driftblitz.boxSize, 1, -math.huge, math.huge)
	Driftblitz.boxOffset = Gui.dragFloat3("Driftblitz Position Offset", Driftblitz.boxOffset, 1, -math.huge, math.huge)
	Driftblitz.centerBoxOffset = Gui.dragFloat3(
		"Driftblitz Place Ball Box Position Offset",
		Driftblitz.centerBoxOffset,
		1,
		-math.huge,
		math.huge
	)
	Driftblitz.goalBoxSize = Gui.dragFloat3("Driftblitz Goal Size", Driftblitz.goalBoxSize, 1, -math.huge, math.huge)
	Driftblitz.goalPositionOffset =
		Gui.dragFloat3("Driftblitz Goal Position Offset", Driftblitz.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Driftblitz.boxSize}`)
		print(`boxOffset: {Driftblitz.boxOffset}`)
		print(`centerBoxOffset: {Driftblitz.centerBoxOffset}`)
		print(`goalBoxSize: {Driftblitz.goalBoxSize}`)
		print(`goalPositionOffset: {Driftblitz.goalPositionOffset}`)
	end

	self:setupDimensions()
end

type ZDrift = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	centerBoxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
}

local ZDrift = {} :: ZDrift
ZDrift.__index = ZDrift
setmetatable(ZDrift, { __index = FollowArena })

ZDrift.homeRotationOffset = Quat.fromEuler(0, 0, 90)
ZDrift.awayRotationOffset = Quat.fromEuler(0, 0, -90)
ZDrift.boxSize = Vec3.new(7180, 17800, 1710)
ZDrift.boxOffset = Vec3.new(0, 0, 880)
ZDrift.centerBoxOffset = Vec3.new(0, 0, 500)
ZDrift.goalBoxSize = Vec3.new(600, 600, 600)
ZDrift.goalPositionOffset = Vec3.new(8200, 0, 585)

function ZDrift.new(gamemode: ModuleStateSpectatorLuaApi): FollowArena
	local self = setmetatable(FollowArena.new(gamemode, readLocation), ZDrift) :: any
	self.name = self.slotId
	self.type = "zdrift"
	self:setupDimensions()
	return self :: ZDrift
end

function ZDrift:isPointOnHomeSide(point: Vec3): boolean
	local homeDirection = (self.transform.rotation * ZDrift.homeRotationOffset):getForwardVector()
	local ballDirection = Util.getForward(self.transform.position, point)
	if homeDirection:dot(ballDirection) >= 0 then
		return true
	else
		return false
	end
end

function ZDrift:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(ZDrift.boxOffset),
		ZDrift.boxSize,
		self.transform.rotation
	)

	self.home.goal = {
		position = self.transform.position
			+ (self.transform.rotation * ZDrift.homeRotationOffset):rotateVector(ZDrift.goalPositionOffset),
		rotation = self.transform.rotation * ZDrift.homeRotationOffset:inverse(),
		box = Box.empty,
	}

	self.home.goal.box = Box.new(self.home.goal.position, ZDrift.goalBoxSize, self.home.goal.rotation)

	self.away.goal = {
		position = self.transform.position
			+ (self.transform.rotation * ZDrift.awayRotationOffset):rotateVector(ZDrift.goalPositionOffset),
		rotation = self.transform.rotation * ZDrift.awayRotationOffset:inverse(),
		box = Box.empty,
	}
	self.away.goal.box = Box.new(self.away.goal.position, ZDrift.goalBoxSize, self.away.goal.rotation)
end

function ZDrift:getTeamRotation(teamIndex: number): Quat
	local rotation = Quat.identity
	if teamIndex == Util.TeamIndex.HomeTeam then
		rotation = self.transform.rotation * ZDrift.homeRotationOffset
	elseif teamIndex == Util.TeamIndex.AwayTeam then
		rotation = self.transform.rotation * ZDrift.awayRotationOffset
	end

	return rotation
end

function ZDrift:checkGoalCam(player: ReplayPlayer): boolean
	return false
end

function ZDrift:GUIChangeDimensions()
	ZDrift.boxSize = Gui.dragFloat3("ZDrift Arena Size", ZDrift.boxSize, 1, -math.huge, math.huge)
	ZDrift.boxOffset = Gui.dragFloat3("ZDrift Position Offset", ZDrift.boxOffset, 1, -math.huge, math.huge)
	ZDrift.centerBoxOffset =
		Gui.dragFloat3("ZDrift Place Ball Box Position Offset", ZDrift.centerBoxOffset, 1, -math.huge, math.huge)
	ZDrift.goalBoxSize = Gui.dragFloat3("ZDrift Goal Size", ZDrift.goalBoxSize, 1, -math.huge, math.huge)
	ZDrift.goalPositionOffset =
		Gui.dragFloat3("ZDrift Goal Position Offset", ZDrift.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {ZDrift.boxSize}`)
		print(`boxOffset: {ZDrift.boxOffset}`)
		print(`centerBoxOffset: {ZDrift.centerBoxOffset}`)
		print(`goalBoxSize: {ZDrift.goalBoxSize}`)
		print(`goalPositionOffset: {ZDrift.goalPositionOffset}`)
	end

	self:setupDimensions()
end

function getArenas(): { [any]: FollowArena }
	local arenas: { [any]: FollowArena } = {}
	local gamemodes = SpectatorGamemodes.listGamemodes()
	for _, gamemode in gamemodes do
		local slotId = gamemode:getSlotId()
		if slotId:find("TKB") and not slotId:find("Driftplex") and not slotId:find("Full") then
			local arena: FollowArena = Arena3v3.new(gamemode, readLocation) :: Arena3v3
			arenas[arena.name] = arena
		elseif slotId:find("Soccer") then
			local arena: FollowArena = Driftblitz.new(gamemode, readLocation) :: Driftblitz
			arenas[arena.name] = arena
		elseif
			(slotId:find("Jakeball") or slotId:find("Driftball"))
			or (slotId:find("TKB") and slotId:find("Driftplex") and not slotId:find("Full"))
		then
			local arena: FollowArena = Arena4v4.new(gamemode, readLocation) :: Arena4v4
			arenas[arena.name] = arena
		elseif slotId:find("ZDrift") then
			local arena: FollowArena = ZDrift.new(gamemode, readLocation) :: ZDrift
			arenas[arena.name] = arena
		end
	end

	return arenas
end

-- arena
local arenas: { [any]: FollowArena }

function tryGetArenas()
	if cachedGamemodeAmount ~= #SpectatorGamemodes.listGamemodeIds() then
		arenas = getArenas()
		if Util.getDictSize(arenas) > 0 then
			setArena(Util.getDictIndex(arenas, 1))
		end
		cachedGamemodeAmount = #SpectatorGamemodes.listGamemodeIds()
	end
end

local arena: FollowArena = nil

-- camera
local wasFollowed: boolean = false
local cameraFOV = profile.fieldOfView
camera.fieldOfView = cameraFOV
local showNameTags = profile.showNameTags
camera.showNameTags = showNameTags
local positionSmoothing = profile.positionSmoothing
local cameraPositionSmoothing = positionSmoothing
local rotationSmoothing = 0.5
local cameraRotationSmoothing = rotationSmoothing
camera.hideNearestHead = false
local showQuests: boolean = profile.showQuests
local cameraMode: number = profile.cameraMode
local previousCameraMode: number = cameraMode
local activeCameraMode: number = cameraMode
local cameraModes = { "First Person", "Head Rotation", "Velocity Rotation", "Face the Ball", "Hand Held" }
local gestureModes = { "Head Rotation", "Velocity Rotation", "Face the Ball" }

local cameraTransition: boolean = false
local THIRD_PERSON_OFFSET: Vec3 = Vec3.new(0, 0, 50)
local cameraEulerOffset: Vec3 = stringToVec3(profile.cameraEulerOffset)
local cameraPositionOffset: Vec3 = Vec3.zeroVector
local distance = 0
local flipTime: number = 0
local maxFlipTime: number = 0.5
local previousHandHeldRotationOffset: Quat = Quat.identity
local nextHandHeldRotationOffset: Quat = Quat.identity
local handHeldRotationOffset: Quat = Quat.identity

local gravityUpDirection: Vec3 = Vec3.zeroVector

-- gui
local listActive = false
local currentPercentage = 0
local savingNewProfile = false
local deletingProfile = false
local newProfileName = ""
local confirmationText = ""
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
local showQuestsLabel = "Show Quests"
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
local simResolutionLable = "Prediction Resolution Scale"
local simTimeLengthLable = "Prediction Length Seconds"
local ballCamGoalModeLabel = "Ball Goal Mode"
local autoGoalCamLabel = "Enabled"
local goalModeLabel = "Mode"
local distanceLerpLabel = "Player/Ball Ratio"

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

-- radius
local radius = profile.radius
local threshold = profile.threshold

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
local followFreecam: boolean = false

function updateVariables(profileName)
	isSelfMuted = false
	profile = config.profiles[profileName]
	radius = profile.radius
	distanceLerp = profile.distanceLerp
	readLocation = profile.readLocation
	cameraMode = profile.cameraMode
	activeCameraMode = cameraMode
	cameraFOV = profile.fieldOfView
	goalMode = profile.goalMode
	showNameTags = profile.showNameTags
	muteSelf = profile.muteSelf
	threshold = profile.threshold
	positionSmoothing = profile.positionSmoothing
	autoGoalCam = profile.autoGoalCam
	autoBall = profile.autoBall
	targetPlayerName = profile.targetPlayerName
	ballGoalMode = profile.ballGoalMode
	cameraEulerOffset = stringToVec3(profile.cameraEulerOffset)
	cameraPositionOffset = stringToVec3(profile.cameraPositionOffset)

	setTargetPlayer(Util.getReplayFrameFromIndex(readLocation):getPlayerByName(targetPlayerName))
end

function main()
	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0
	arenas = getArenas()
end

function onTransitionBegin()
	if camera.isFollowed then
		toggleSmoothing(false, false)
	end

	alwaysTick = true
	WorldDraw.clear()

	if not targetPlayer then
		setTargetPlayer(Util.getReplayFrameFromIndex(readLocation):getPlayerByName(targetPlayerName))
	end

	if wasFollowed then
		wasFollowed = false
		updateVariables(lastUsedProfile)

		-- transition to orbit
		local fromEuler = Quat.fromEuler(orbitRotation.x, orbitRotation.y, orbitRotation.z)
		local direction = fromEuler:getForwardVector()
		setCameraRotation(Util.lookAt(cameraPosition, orbitLookAt, Vec3.upVector))
		setCameraPosition(orbitCenter, Vec3.zeroVector, Util.negateVec3(direction) * orbitRadius)
	end
end

function generateAsterisk(guiLable: string, isEdited: boolean): string
	if isEdited then
		return `{guiLable}(*)###{guiLable}`
	else
		return `{guiLable}###{guiLable}`
	end
end

function setTargetPlayer(player: ReplayPlayer?)
	if not player then
		return
	end

	if targetPlayer and targetPlayer.playerId == player.playerId then
		return
	end

	if targetPlayer then
		Settings.mutePlayerByName(targetPlayer.playerName, false)
		if showQuests then
			camera:showQuestsForPlayerById(targetPlayer.playerId, false)
		end
		isSelfMuted = not muteSelf
		playerSwitchTime = os.clock()
		teammatesList = {}
		lastTeammatesList = {}
	end

	if player.teamIndex == Util.TeamIndex.NoTeam then
		stopRecording("new player - no team")
	end

	if showQuests then -- show quests
		camera:showQuestsForPlayerById(player.playerId, true)
	end

	targetPlayer = player
	targetPlayerName = player.playerName
	teamIndex = player.teamIndex
	setArena(getClosestArena(player.root.position))
end

function clearTargetPlayer()
	if targetPlayer then
		Settings.mutePlayerByName(targetPlayer.playerName, false)
		if showQuests then
			camera:showQuestsForPlayerById(targetPlayer.playerId, false)
		end
		isSelfMuted = not muteSelf

		stopRecording("clear target player")
		targetPlayerName = ""
		targetPlayer = nil
	end
end

function setArena(_arena: FollowArena)
	if not _arena then
		return
	end

	local sameArena = arena and arena.name == _arena.name
	if sameArena then
		if arena.isGameActive and teamIndex ~= Util.TeamIndex.NoTeam then -- Different player in a different arena that they are playing in and the game is on going
			startRecording("join active game")
		end
		return
	end

	stopRecording("new player - different arena")

	arena = _arena
	arena.frameIndex = readLocation
	arena.instantUpdate = true
	arena:tick()

	BallSim.arena = arena :: any

	if arena.isGameActive and teamIndex ~= Util.TeamIndex.NoTeam then
		startRecording("join active game")
	end
end

-- GUI

function topSettings()
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

	if Gui.beginCombo("Profile", lastUsedProfile) then
		local defaultKey = Util.getDictKey(config.profiles["default"], config.profiles)
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

	Emotes:selectEmoteGUI("Emote")

	Gui.newLine()
end

function checkboxSettings()
	showNameTags = Gui.checkbox(generateAsterisk(nametagsLabel, showNameTags ~= profile.showNameTags), showNameTags)
	Gui.setItemTooltip("Enable or disable nametags for all players")

	Gui.sameLine()
	showQuests = Gui.checkbox(generateAsterisk(showQuestsLabel, showQuests ~= profile.showQuests), showQuests)
	Gui.setItemTooltip("Will show the quest for the followed player when they activate a quest")

	Gui.sameLine()
	if not Settings.getLuauReplayControlAllowed() then
		Gui.beginDisabled()
	end
	autoRecordReplays = Gui.checkbox(
		generateAsterisk("Auto Rec Replays", autoRecordReplays ~= profile.autoRecordReplays),
		autoRecordReplays
	)
	if not Settings.getLuauReplayControlAllowed() then
		Gui.setItemTooltip(
			"DISABLED! To enable this setting go to Spectator -> Settings -> Allow Camera Scripts to Start/Stop Replay File Recording"
		)
		Gui.endDisabled()
	else
		Gui.setItemTooltip("Automatically records replays of your Driftball rounds")
	end

	muteSelf = Gui.checkbox(generateAsterisk(muteSelfLabel, muteSelf ~= profile.muteSelf), muteSelf)
	Gui.setItemTooltip("Enable or disable muting yourself or the player you are currently following")

	Gui.sameLine()
	isLeftHanded = Gui.checkbox(generateAsterisk(isLeftHandedLabel, isLeftHanded ~= profile.isLeftHanded), isLeftHanded)
	Gui.setItemTooltip("Makes you left handed | Used for Hand Held mode")

	--[[Gui.sameLine()
	focusedArena = Gui.checkbox(generateAsterisk(focusedArenaLabel, focusedArena ~= profile.focusedArena), focusedArena)
	Gui.setItemTooltip("Mutes all Players OUTSIDE of the Arena the Followed Player is currently in")]]
end

function playerSettings()
	targetPlayerName = Gui.inputText(
		generateAsterisk(targetPlayerNameLabel, targetPlayerName ~= profile.targetPlayerName),
		targetPlayerName
	)
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
					setTargetPlayer(player)
				end

				if
					(targetPlayer and targetPlayerName ~= targetPlayer.playerName)
					and targetPlayerName ~= "YourName"
					and not string.find(string.lower(player.playerName), string.lower(targetPlayerName))
				then
					continue
				end

				if
					Gui.selectable(tostring(player.playerName) .. "[" .. tostring(player.playerId) .. "]", isSelected)
				then
					setTargetPlayer(player)
				end
			end
			Gui.endListBox()
		end

		if Gui.button(Icon.Check) then
			listActive = false
		end
		Gui.sameLine()
		if Gui.button(Icon.Trash) then
			clearTargetPlayer()
		end
		Gui.setItemTooltip("Clear Follow Player")

		Gui.unindent()
	end
end

function cameraSettings()
	cameraFOV = Gui.sliderInt(generateAsterisk(cameraFOVLabel, cameraFOV ~= profile.fieldOfView), cameraFOV, 40, 179)
	Gui.setItemTooltip("The cameras field of view (FOV)")
	cameraFOV = math.clamp(cameraFOV, 40, 179)

	positionSmoothing = Gui.sliderFloat(
		generateAsterisk(positionSmoothingLabel, positionSmoothing ~= profile.positionSmoothing),
		positionSmoothing,
		0,
		1
	)
	positionSmoothing = math.clamp(positionSmoothing, 0, 1)
	Gui.setItemTooltip("The time it takes for the Camera to move from A to B")
	Gui.newLine()
end

function gestureSettings()
	local gestureHeaderAsterisk = false
	if
		backwardsGestureMode ~= profile.backwardsGestureMode
		or upGestureMode ~= profile.upGestureMode
		or forwardGestureMode ~= profile.forwardGestureMode
		or gestureControls ~= profile.gestureControls
	then
		gestureHeaderAsterisk = true
	end
	if Gui.collapsingHeader(generateAsterisk(gestureControlsHeaderLabel, gestureHeaderAsterisk)) then
		Gui.indent()
		gestureControls = Gui.checkbox(
			generateAsterisk(gestureControlsLabel, gestureControls ~= profile.gestureControls) .. "##3",
			gestureControls
		)
		Gui.setItemTooltip([[
Be able to grab the camera and throw it to change modes
	- Grab the camera with grip and trigger behind your head
	- Let go without throwing for First Person]])
		if gestureControls then
			if
				Gui.beginCombo(
					generateAsterisk(forwardGestureModeLabel, forwardGestureMode ~= profile.forwardGestureMode),
					gestureModes[forwardGestureMode - 1]
				)
			then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == forwardGestureMode - 1) then
						forwardGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			forwardGestureMode = math.clamp(forwardGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera forward")

			if
				Gui.beginCombo(
					generateAsterisk(upGestureModeLabel, upGestureMode ~= profile.upGestureMode),
					gestureModes[upGestureMode - 1]
				)
			then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == upGestureMode - 1) then
						upGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			upGestureMode = math.clamp(upGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera up")

			if
				Gui.beginCombo(
					generateAsterisk(backwardsGestureModeLabel, backwardsGestureMode ~= profile.backwardsGestureMode),
					gestureModes[backwardsGestureMode - 1]
				)
			then
				for i = 1, #gestureModes do
					if Gui.selectable(gestureModes[i], i == backwardsGestureMode - 1) then
						backwardsGestureMode = i + 1
					end
				end
				Gui.endCombo()
			end
			backwardsGestureMode = math.clamp(backwardsGestureMode, 1, #cameraModes)
			Gui.setItemTooltip("What Mode to change to when Throwing the Camera backward")
		end
		Gui.unindent()
	end
end

function followSettings()
	Gui.indent()
	Gui.separatorText("Settings")

	if Gui.beginCombo(generateAsterisk(cameraModeLabel, cameraMode ~= profile.cameraMode), cameraModes[cameraMode]) then
		for i = 1, #cameraModes do
			if Gui.selectable(cameraModes[i], i == cameraMode) then
				cameraMode = i
			end
		end
		Gui.endCombo()
	end
	cameraMode = math.clamp(cameraMode, 1, #cameraModes)
	activeCameraMode = cameraMode
	Gui.setItemTooltip("Changes how the Camera behaves")

	Gui.newLine()

	if cameraMode == CameraMode.FirstPerson then
		Gui.beginDisabled()
	end

	radius = Gui.dragFloat(generateAsterisk(radiusLabel, radius ~= profile.radius), radius, 0.5, 0, 100)

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

	threshold = Gui.sliderFloat(generateAsterisk(thresholdLabel, threshold ~= profile.threshold), threshold, 0, radius)
	Gui.setItemTooltip("The distance at which the camera will automatically switch between 1st and 3rd Person")
	if cameraMode ~= CameraMode.VelocityRotation then
		threshold = math.clamp(threshold, 0, radius)
	end
	if cameraMode == CameraMode.FirstPerson then
		Gui.endDisabled()
	end
	Gui.newLine()
	if cameraMode == CameraMode.VelocityRotation or cameraMode == CameraMode.FaceTheBall then
		Gui.beginDisabled()
	end

	cameraPositionOffset = Gui.dragFloat3(
		generateAsterisk(cameraPositionOffsetLabel, cameraPositionOffset ~= stringToVec3(profile.cameraPositionOffset)),
		cameraPositionOffset,
		1,
		-1000,
		1000
	)

	cameraPositionOffset = Util.vec3ClampAxis(cameraPositionOffset, -1000, 1000)
	Gui.setItemTooltip("The Cameras positional offset. Only applied in mode 'Head Rotation' and 'First Person'")

	cameraEulerOffset = Gui.dragFloat3(
		generateAsterisk(cameraEulerOffsetLabel, cameraEulerOffset ~= stringToVec3(profile.cameraEulerOffset)),
		cameraEulerOffset,
		1,
		-math.huge,
		math.huge
	)
	Gui.setItemTooltip("The Cameras rotational offset. Only applied in mode 'Head Rotation'")

	if cameraMode == CameraMode.VelocityRotation or cameraMode == CameraMode.FaceTheBall then
		Gui.endDisabled()
	end
end

function mainSettings()
	followSettings()

	Gui.newLine()
	gestureSettings()

	Gui.unindent()
end

function autoShootingSettings()
	local autoShootingCameraAsterisk = false
	if autoBall ~= profile.autoBall or ballGoalMode ~= profile.ballGoalMode then
		autoShootingCameraAsterisk = true
	end
	if Gui.collapsingHeader(generateAsterisk(autoShootingCameraHeaderLabel, autoShootingCameraAsterisk)) then
		Gui.indent()

		autoBall = Gui.checkbox(generateAsterisk(autoBallLabel, autoBall ~= profile.autoBall), autoBall)
		Gui.setItemTooltip(
			"The camera will start prediction where the ball is going to go and follow the ball if it thinks it's going in the goal"
		)

		if autoBall then
			if
				Gui.beginCombo(
					generateAsterisk(ballCamGoalModeLabel, ballGoalMode ~= profile.ballGoalMode),
					ballGoalModes[ballGoalMode]
				)
			then
				for i = 1, #ballGoalModes do
					if Gui.selectable(ballGoalModes[i], i == ballGoalMode) then
						ballGoalMode = i
					end
				end
				Gui.endCombo()
			end
			Gui.setItemTooltip(
				"If the ball camera should only activate when being shot on the enemy goal, or if it should activate on both goals"
			)

			BallSim.pathLengthSeconds = Gui.sliderFloat(
				generateAsterisk(simTimeLengthLable, BallSim.pathLengthSeconds ~= profile.simTimeLength),
				BallSim.pathLengthSeconds,
				0,
				6
			)
			BallSim.pathLengthSeconds = math.clamp(BallSim.pathLengthSeconds, 0, 6)
			Gui.setItemTooltip("The amount of seconds into the future the prediction should predict")

			BallSim.resolutionScale = Gui.sliderFloat(
				generateAsterisk(simResolutionLable, BallSim.resolutionScale ~= profile.simResolutionScale),
				BallSim.resolutionScale,
				0.1,
				1
			)
			BallSim.resolutionScale = math.clamp(BallSim.resolutionScale, 0.1, 1)
			Gui.setItemTooltip("The prediction quality. Higher quality SEVERELY impacts performance.")
		end
		Gui.unindent()
	end
end

function goalCamSettings()
	local goalCameraAsterisk = false
	if autoGoalCam ~= profile.autoGoalCam or goalMode ~= profile.goalMode or distanceLerp ~= profile.distanceLerp then
		goalCameraAsterisk = true
	end
	if Gui.collapsingHeader(generateAsterisk(goalCameraHeaderLabel, goalCameraAsterisk)) then
		Gui.indent()

		autoGoalCam =
			Gui.checkbox(generateAsterisk(autoGoalCamLabel, autoGoalCam ~= profile.autoGoalCam) .. "##2", autoGoalCam)
		Gui.setItemTooltip("Automatically positions the Camera inside the Goal when Targeted Player is close to Goal")

		if autoGoalCam then
			if Gui.beginCombo(generateAsterisk(goalModeLabel, goalMode ~= profile.goalMode), goalModes[goalMode]) then
				for i = 1, #goalModes do
					if Gui.selectable(goalModes[i], i == goalMode) then
						goalMode = i
					end
				end
				Gui.endCombo()
			end
			Gui.setItemTooltip("Determens which Goals to Activate at")

			distanceLerp = Gui.sliderFloat(
				generateAsterisk(distanceLerpLabel, distanceLerp ~= profile.distanceLerp),
				distanceLerp,
				1,
				10
			)
			Gui.setItemTooltip("The Look Ratio between the Player and the Ball. 0 is full Player, 10 is full Ball.")
		end

		Gui.unindent()
	end
end

function autoCameraSettings()
	Gui.newLine()
	Gui.indent()
	Gui.separatorText("Auto Cameras")

	autoShootingSettings()

	Gui.newLine()

	goalCamSettings()

	Gui.unindent()
	Gui.newLine()
end

function savingSettings()
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
					simResolution = BallSim.resolutionScale,
					simTimeLength = BallSim.pathLengthSeconds,
					ballGoalMode = ballGoalMode,
					cameraEulerOffset = tostring(cameraEulerOffset),
					cameraPositionOffset = tostring(cameraPositionOffset),
					isLeftHanded = isLeftHanded,
					showQuests = showQuests,
					autoRecordReplays = autoRecordReplays,
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
				simResolution = BallSim.resolutionScale,
				simTimeLength = BallSim.pathLengthSeconds,
				ballGoalMode = ballGoalMode,
				cameraEulerOffset = tostring(cameraEulerOffset),
				cameraPositionOffset = tostring(cameraPositionOffset),
				isLeftHanded = isLeftHanded,
				showQuests = showQuests,
				autoRecordReplays = autoRecordReplays,
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
end

function debugSettings()
	Gui.separator()
	if Gui.treeNode("Debug") then
		Gui.indent()
		Gui.separatorText("Info")
		Gui.indent()
		if Gui.treeNode("Camera") then
			Gui.text("Camera Position (smoothed): " .. tostring(camera.position))
			Gui.text("Camera Position (real): " .. tostring(cameraPosition))
			Gui.text("Camera Rotation (smoothed): " .. tostring(camera.rotation:euler()))
			Gui.text("Camera Rotation (real): " .. tostring(cameraRotation:euler()))
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
			if targetPlayer and Gui.treeNode("Left Hand Poses") then
				local leftHandPoses = Util.decodePoseBits(targetPlayer.leftHandPosebits)

				Gui.text(`Thumb Down: {leftHandPoses.ThumbDown}`)
				Gui.text(`Trigger Down: {leftHandPoses.TriggerDown}`)
				Gui.text(`Trigger Point: {leftHandPoses.TriggerPoint}`)
				Gui.text(`Grip Down: {leftHandPoses.GripDown}`)
				Gui.text(`Full Hand Pose Override: {Util.fullHandPoseToString(leftHandPoses.FullHandPoseOverride)}`)
				Gui.treePop()
			end
			if targetPlayer and Gui.treeNode("Right Hand Poses") then
				local rightHandPoses = Util.decodePoseBits(targetPlayer.rightHandPosebits)

				Gui.text(`Thumb Down: {rightHandPoses.ThumbDown}`)
				Gui.text(`Trigger Down: {rightHandPoses.TriggerDown}`)
				Gui.text(`Trigger Point: {rightHandPoses.TriggerPoint}`)
				Gui.text(`Grip Down: {rightHandPoses.GripDown}`)
				Gui.text(`Full Hand Pose Override: {Util.fullHandPoseToString(rightHandPoses.FullHandPoseOverride)}`)
				Gui.treePop()
			end
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
		if arena and Gui.treeNode("Arena") then
			Gui.text("Arena Name: " .. arena.name)
			Gui.text("Arena Position: " .. tostring(arena.transform.position))
			Gui.text("Arena Rotation: " .. tostring(arena.transform.rotation:euler()))
			Gui.treePop()
		end
		if Gui.treeNode("VOIP") then
			if Gui.button("Mute everyone") then
				muteAll(true, true)
			end
			Gui.sameLine()
			if Gui.button("Unmute everyone") then
				muteAll(false, true)
			end
			if arena then
				if Gui.button("Mute arena") then
					muteList(true, arena.players, true)
				end
				if Gui.button("Mute outside") then
					local mutePlayers = frame.players
					for _, player in arena.players do
						local arenaPlayer = Util.findPlayerInTable(mutePlayers, player)

						if arenaPlayer then
							table.remove(mutePlayers, arenaPlayer)
						end
					end

					muteList(true, mutePlayers, true)
				end
			end
			Gui.treePop()
		end
		if Gui.treeNode("Settings") then
			BallSim.debug = Gui.checkbox("Debug Ball Prediction", BallSim.debug)
			BallSim.gravityScale = Gui.sliderFloat("Gravity", BallSim.gravityScale, 0, 1)
			BallSim.drag = Gui.sliderFloat("Drag", BallSim.drag, 0, 1)

			Gui.newLine()

			debugFaceTheBall = Gui.checkbox("Debug Face The Ball", debugFaceTheBall)
			debugAutoRecord = Gui.checkbox("Debug Auto Record", debugAutoRecord)

			Gui.newLine()

			if followFreecam and Gui.button("stop follow freecam") then
				followFreecam = false
				camera:followCamera(nil)
			end
			if not followFreecam and Gui.button("follow freecam") then
				followFreecam = true
				sendMessage(getCameraById("anotheraxiom.freecam"), {
					messageType = "setTransform",
					rotation = camera.rotation,
					position = camera.position,
					fieldOfView = camera.fieldOfView,
				})
				camera:followCamera(getCameraById("anotheraxiom.freecam"))
			end
			Gui.treePop()
		end
		if Gui.treeNode("Other") then
			Gui.text("Distance: " .. tostring(distance))
			Gui.text("Ball Distance: " .. tostring(Util.getDist(headPosition, ballPosition)))
			Gui.text("Is Recording Replay: " .. tostring(isRecordingReplay))
			Gui.treePop()
		end

		Gui.newLine()
		Gui.unindent()
		Gui.treePop()
	end
end

function onGui()
	Gui.text("Version: " .. _version)
	topSettings()

	checkboxSettings()

	playerSettings()

	cameraSettings()

	mainSettings()

	autoCameraSettings()

	savingSettings()

	debugSettings()
end

function toggleSmoothing(position: boolean, rotation: boolean)
	if position then
		cameraPositionSmoothing = positionSmoothing
	else
		cameraPositionSmoothing = 0
	end
	if rotation then
		cameraRotationSmoothing = rotationSmoothing
	else
		cameraRotationSmoothing = 0
	end
end

function getClosestArena(
	targetPosition: Vec3
): FollowArena -- Remove this function when/if we get the arena from the player
	local closestArenaDistance = math.huge
	local closestArena = nil

	for _, arena: FollowArena in pairs(arenas) do
		local distance = Util.getDist(targetPosition, arena.transform.position)
		-- because some arenas are directly above others
		-- we limit the arenas to those where the player is between the arenas floor and roof position
		if not arena.box:checkPointIntersect(targetPosition) then
			continue
		end
		if distance < closestArenaDistance then
			closestArenaDistance = distance
			closestArena = arena
		end
	end

	-- if the camera is placed in such a way that it is not leveled with any arena we loop again without limiting height
	if closestArena == nil then
		for _, arena: FollowArena in pairs(arenas) do
			local distance = Util.getDist(targetPosition, arena.transform.position)
			if distance < closestArenaDistance then
				closestArenaDistance = distance
				closestArena = arena
			end
		end
	end

	return closestArena
end

function getClosestBall(targetPosition: Vec3, frameData: ReplayFrame)
	local balls = frameData.balls
	local closestBallDistance = math.huge
	local clostestBall: ReplayBall = nil
	for i in balls do
		local ball = balls[i]
		local distance = Util.getDist(targetPosition, ball.transform.position)
		if distance < closestBallDistance then
			closestBallDistance = distance
			clostestBall = ball
		end
	end
	return clostestBall
end

function updatePlayerData(player: ReplayPlayer, frame: ReplayFrame)
	targetPlayer = frame:getPlayerById(player.playerId)
	playerVelocity = player.velocity
	isLocalPlayer = player.isLocalPlayer
	playerNameInfo = player.playerName
	playerIdInfo = tostring(player.playerId)

	if teamIndex ~= player.teamIndex then
		teamIndex = player.teamIndex

		if teamIndex == Util.TeamIndex.NoTeam then
			stopRecording("player leave arena")
		end

		setArena(getClosestArena(player.root.position))
	end
end

function mouseRotationOffset()
	cameraEulerOffset += Vec3.new(0, Input.getAnalog(yMouse), Input.getAnalog(xMouse))
end

function rotationPivotPosition(anchor: Vec3, anchorOffset: Vec3, rotation: Quat, radius: number)
	local rotationQuat = rotation * Quat.fromEuler(cameraEulerOffset.x, cameraEulerOffset.y, cameraEulerOffset.z)
	radius *= 10
	local cameraDirection = rotationQuat:getForwardVector()

	setCameraPosition(anchor, anchorOffset, Util.negateVec3(cameraDirection) * radius)
end

function velocityPivotPosition(anchor: Vec3, anchorOffset: Vec3, velocity: Vec3, radius: number, ball: boolean)
	radius *= 10

	local cameraDirection = velocity:getSafeNormal()
	if not ball then
		cameraDirection = Util.negateVec3(cameraDirection)
	end

	setCameraPosition(anchor, anchorOffset, cameraDirection * radius)
end

function faceTheBallPivotPosition(
	anchor: Vec3,
	anchorOffset: Vec3,
	playerBox: BoxType,
	ballPosition: Vec3,
	radius: number
)
	local closestPointToBall = playerBox:clampPointToBox(ballPosition, false)

	local direction = Util.getForward(closestPointToBall, ballPosition)
	radius *= 10

	if debugFaceTheBall then
		WorldDraw.drawLine(closestPointToBall, closestPointToBall + (direction * 50), 0, 1, 0, 10, 0)
	end

	setCameraPosition(anchor, anchorOffset, Util.negateVec3(direction) * radius)
end

function updateBallData(ball: ReplayBall, seconds: number)
	ballPosition = ball.transform.position
	ballRotation = ball.transform.rotation
	ballArena = ball.arena
	ballVelocity = ball.velocity
end

function isGrabbingCamera(player: ReplayPlayer): Transform?
	local leftHandPosition = player.root.position + player.root.rotation:rotateVector(player.leftHand.position)
	local leftPoseFlags = Util.decodePoseBits(player.leftHandPosebits)
	local rightHandPosition = player.root.position + player.root.rotation:rotateVector(player.rightHand.position)
	local rightPoseFlags = Util.decodePoseBits(player.rightHandPosebits)

	-- Left hand grab logic
	if
		not leftHandGrabbing
		and leftPoseFlags.GripDown
		and leftPoseFlags.TriggerDown
		and leftPoseFlags.FullHandPoseOverride ~= Util.HandPose.GrabBall
	then
		if
			(cameraMode == CameraMode.HandHeld and isLeftHanded and not isFollowingBall and not cameraInGoal)
			or player.head.rotation:getForwardVector():dot(Util.getForward(player.head.position, leftHandPosition))
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
				leftHandPosition + Util.clampLength3((throwVelocity * throwBoost), 0, 500),
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
		and rightPoseFlags.FullHandPoseOverride ~= Util.HandPose.GrabBall
	then
		if
			(cameraMode == CameraMode.HandHeld and not isLeftHanded and not isFollowingBall and not cameraInGoal)
			or player.head.rotation:getForwardVector():dot(Util.getForward(player.head.position, rightHandPosition))
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
				rightHandPosition + Util.clampLength3((throwVelocity * throwBoost), 0, 500),
				releaseTimers.right / maxLetGoTime
			)
			if throwVelocity ~= Vec3.zeroVector then
				local forwardLook = throwVelocity:normalize()
				rightHandTransform.rotation =
					Quat.fromXZ(Util.negateVec3(forwardLook), player.head.rotation:getUpVector())
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
	hidePlayerHead = false

	setCameraPosition(grabHand.position, Vec3.zeroVector, Vec3.zeroVector)

	if rightHandGrabbing or leftHandGrabbing then
		return
	end

	if (throwVelocity:length() * 100) < 2.5 then
		local headDistance = Util.getDist(cameraPosition, player.head.position)
		local leftHandDistance = Util.getDist(
			cameraPosition,
			player.root.position + player.root.rotation:rotateVector(player.leftHand.position)
		)
		local rightHandDistance = Util.getDist(
			cameraPosition,
			player.root.position + player.root.rotation:rotateVector(player.rightHand.position)
		)

		if headDistance <= 20 then
			cameraMode = CameraMode.FirstPerson
			activeCameraMode = cameraMode
		elseif leftHandDistance <= 10 then
			if leftHandDistance <= 0.1 and rightHandDistance <= 1.5 then
				isLeftHanded = false
			else
				isLeftHanded = true
			end
			cameraMode = CameraMode.HandHeld
			activeCameraMode = cameraMode
		elseif rightHandDistance <= 10 then
			if rightHandDistance <= 0.1 and leftHandDistance <= 1.5 then
				isLeftHanded = true
			else
				isLeftHanded = false
			end
			cameraMode = CameraMode.HandHeld
			activeCameraMode = cameraMode
		end

		return
	end

	local playerForward = player.root.rotation:getForwardVector()
	local playerUp = player.root.rotation:getUpVector()
	local playerBackwards = Util.negateVec3(playerForward)

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
		activeCameraMode = cameraMode
	elseif biggestDotName == "up" then
		cameraMode = CameraMode.FaceTheBall
		activeCameraMode = cameraMode
	elseif biggestDotName == "backwards" then
		cameraMode = CameraMode.HeadRotation
		activeCameraMode = cameraMode
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

	local ballCamRadius: number = radius
	if ballCamRadius < 10 then
		ballCamRadius = 10
	end

	setCameraRotation(Util.lookAt(cameraPosition, ballPosition, gravityUpDirection))
	hidePlayerHead = false
	velocityPivotPosition(ballPosition, Vec3.zeroVector, ballVelocity, ballCamRadius, false)
end

function firstPerson()
	if not cameraTransition then
		toggleSmoothing(false, true)
	end

	local position = headPosition
	local offsetPosition = cameraPositionOffset
	local rotation = headRotation * Util.quatFromVec3(cameraEulerOffset)

	offsetPosition = rotation:rotateVector(offsetPosition)

	if offsetPosition == Vec3.zeroVector then
		local offsetForMicFix = rotation:rotateVector(Vec3.new(0.01, 0, 0))
		offsetPosition += offsetForMicFix
	end

	if offsetPosition:length() > 50 then
		hidePlayerHead = false
	elseif offsetPosition:length() < 49 then
		hidePlayerHead = true
	end

	setCameraRotation(rotation)
	setCameraPosition(position, offsetPosition, Vec3.zeroVector)
end

function firstPersonOverride()
	if not cameraTransition then
		toggleSmoothing(false, true)
	end

	local position = headPosition
	local offsetPosition = cameraPositionOffset
	local rotation = headRotation * Util.quatFromVec3(cameraEulerOffset)

	offsetPosition = rotation:rotateVector(offsetPosition)

	if offsetPosition == Vec3.zeroVector then
		local offsetForMicFix = rotation:rotateVector(Vec3.new(0.01, 0, 0))
		offsetPosition += offsetForMicFix
	end

	if offsetPosition:length() > 50 then
		hidePlayerHead = false
	elseif offsetPosition:length() < 49 then
		hidePlayerHead = true
	end

	setCameraRotation(rotation)
	cameraPosition = anchorCollision(position, offsetPosition)
end

function thirdPerson(position: Vec3, offsetPosition: Vec3?, rotation: Quat, smartSwitch: boolean)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	local anchorOffset: Vec3 = Vec3.zeroVector
	if offsetPosition ~= nil then
		offsetPosition = rotation:rotateVector(offsetPosition)
		anchorOffset = offsetPosition
	end

	if Input.getKey(rightMouseButton) then
		smartSwitch = false
		mouseRotationOffset()
	end

	setCameraRotation(Util.lookAt(cameraPosition, position, gravityUpDirection))
	hidePlayerHead = false
	rotationPivotPosition(position, anchorOffset, rotation, radius)
end

function thirdPersonVelocity(position: Vec3, velocity: Vec3, rotation: Quat)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	local offsetPosition: Vec3 = rotation:rotateVector(THIRD_PERSON_OFFSET)

	if velocity:length() < 600 then
		thirdPerson(position, offsetPosition + cameraPositionOffset, rotation, true)
		return
	end

	setCameraRotation(Util.lookAt(cameraPosition, position, gravityUpDirection))
	hidePlayerHead = false
	velocityPivotPosition(position, offsetPosition, velocity, radius, false)
end

function thirdPersonFacingBall(player: ReplayPlayer, offsetPosition: Vec3)
	if not cameraTransition then
		toggleSmoothing(true, true)
	end

	local offset = player.head.rotation:rotateVector(offsetPosition)
	local position = player.head.position

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
		playerBox:render(0.7, 0.15, 0.15)
	end

	setCameraRotation(Util.lookAt(cameraPosition, position, gravityUpDirection))
	hidePlayerHead = false
	faceTheBallPivotPosition(position, offset, playerBox, ballPosition, radius)
end

function checkFlip(rightHandTransform: Transform, rightHandPosebits, leftHandTransform: Transform, leftHandPosebits)
	if flipTime < maxFlipTime then
		handHeldRotationOffset =
			Quat.slerp(previousHandHeldRotationOffset, nextHandHeldRotationOffset, flipTime / maxFlipTime)
		flipTime += deltaTime
		return
	end

	local leftHandPose = Util.decodePoseBits(leftHandPosebits)
	local rightHandPose = Util.decodePoseBits(rightHandPosebits)

	local leftHandVelocity = leftHandTransform.position - previousLeftHandPosition
	local rightHandVelocity = rightHandTransform.position - previousRightHandPosition

	local rightDot = leftHandTransform.rotation:getRightVector():dot(rightHandVelocity:normalize())
	local leftDot = rightHandTransform.rotation:getRightVector():dot(leftHandVelocity:normalize())

	if isLeftHanded then
		local handForward = leftHandTransform.rotation:getForwardVector()
		local otherHandDirection = Util.getForward(leftHandTransform.position, rightHandTransform.position)
		local handDistance = Util.getDist(leftHandTransform.position, rightHandTransform.position)

		if
			rightHandPose.GripDown
			and rightHandPose.TriggerDown
			and rightHandVelocity:length() >= 1
			and otherHandDirection:dot(Util.negateVec3(handForward)) > 0.75
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
		local otherHandDirection = Util.getForward(rightHandTransform.position, leftHandTransform.position)
		local handDistance = Util.getDist(leftHandTransform.position, rightHandTransform.position)

		if
			leftHandPose.GripDown
			and leftHandPose.TriggerDown
			and leftHandVelocity:length() >= 1
			and otherHandDirection:dot(Util.negateVec3(handForward)) > 0.75
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
		setCameraRotation(leftHandRotation * handHeldRotationOffset)
		setCameraPosition(leftHandPosition, Vec3.zeroVector, leftHandRotation:rotateVector(positionOffset))
	else
		setCameraRotation(rightHandRotation * handHeldRotationOffset)
		setCameraPosition(rightHandPosition, Vec3.zeroVector, rightHandRotation:rotateVector(positionOffset))
	end

	previousLeftHandPosition = leftHandPosition
	previousRightHandPosition = rightHandPosition
end

function checkForBallFollow(player: ReplayPlayer)
	BallSim:tick()
	local isInGoalInfo = BallSim:isInGoal()

	if isFollowingBall then
		local hasScored = arena.home.goal.box:checkPointIntersect(arena.ball.transform.position)
			or arena.away.goal.box:checkPointIntersect(arena.ball.transform.position)
		local isHeld = Util.isDriftballHeld(arena.ball, BallSim.radius, arena.players)
		local notInGoal = not isInGoalInfo.home and not isInGoalInfo.away
		local stopFollow = (notInGoal or hasScored or isHeld) and os.clock() > followBallStart + minBallFollowTime

		if stopFollow then
			isFollowingBall = false
			return
		end
	end

	if not isInGoalInfo.home and not isInGoalInfo.away then
		return
	end

	local shotGoal = nil
	if isInGoalInfo.home then
		shotGoal = arena.home.goal
	else
		shotGoal = arena.away.goal
	end

	local oppositeGoal = (isInGoalInfo.home and player.teamIndex == Util.TeamIndex.AwayTeam)
		or (isInGoalInfo.away and player.teamIndex == Util.TeamIndex.HomeTeam)
	local isCorrectGoal = (
		(ballGoalMode == BallGoalMode.EnemyGoal and oppositeGoal) or (ballGoalMode == BallGoalMode.BothGoals)
	)
	local isGoodShotDistance = Util.getDist(shotGoal.position, arena.ball.transform.position) > 1000
	local isInAir = not Util.isDriftballHeld(arena.ball, BallSim.radius, arena.players)
	local isGoal = (isInGoalInfo.home or isInGoalInfo.away) and isCorrectGoal and isGoodShotDistance and isInAir

	if isGoal then
		isFollowingBall = true
	end
end

function withPlayer(player: ReplayPlayer)
	camera.showNameTags = showNameTags

	if not collisions then
		collisions = true
	end

	-- check for gesture controls
	if gestureControls then
		-- Check for camera grab
		local grabHand: Transform? = isGrabbingCamera(player)
		if grabHand ~= nil then
			grabbingCamera(player, grabHand)
			return
		end
	end

	if autoGoalCam and not isFollowingBall then
		if arena:checkGoalCam(player) then
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
		checkForBallFollow(player)
		if isFollowingBall then
			ballCam(30, Quat.identity)
			return
		end
	elseif isFollowingBall then
		isFollowingBall = false
	end

	if doneOnceBall then
		doneOnceBall = false
	end

	headRotation = player.head.rotation
	headPosition = player.head.position

	if previousCameraMode ~= activeCameraMode or previousTargetPlayerId ~= player.playerId then
		toggleSmoothing(false, false)
		cameraTransition = true
	elseif cameraTransition then
		cameraTransition = false
	end

	camera.fieldOfView = cameraFOV
	if radius == 0 and cameraMode ~= CameraMode.HandHeld then
		firstPerson()
	elseif cameraMode == CameraMode.HeadRotation then
		thirdPerson(headPosition, THIRD_PERSON_OFFSET + cameraPositionOffset, headRotation, true)
	elseif cameraMode == CameraMode.VelocityRotation then
		thirdPersonVelocity(headPosition, player.velocity, headRotation)
	elseif cameraMode == CameraMode.FaceTheBall then
		if player.teamIndex ~= Util.TeamIndex.NoTeam then
			thirdPersonFacingBall(player, THIRD_PERSON_OFFSET)
		else
			thirdPerson(headPosition, THIRD_PERSON_OFFSET + cameraPositionOffset, headRotation, false)
		end
	elseif cameraMode == CameraMode.HandHeld then
		handHeld(player)
	else
		firstPerson()
	end
end

function noPlayerOrbit(dt: number)
	if collisions then
		collisions = false
	end
	local fromEuler = Quat.fromEuler(orbitRotation.x, orbitRotation.y, orbitRotation.z)
	local direction = fromEuler:getForwardVector()

	setCameraRotation(Util.lookAt(cameraPosition, Vec3.zeroVector, Vec3.upVector))
	orbitRotation.z -= dt * orbitRotationSpeed

	setCameraPosition(orbitCenter, Vec3.zeroVector, Util.negateVec3(direction) * orbitRadius)
	gravityUpDirection = gravity.upDirection

	rotateCamera()
end

function configureVOIP()
	local frame = getGameData() -- always do VOIP on live data | Replays don't have VOIP

	if not targetPlayer then
		return
	end

	if not focusedArena and lastFocusedArena then
		-- focused arena got turned off
		print("focused arena off")
		if muteSelf then
			local toMuteList = frame.players
			table.remove(toMuteList, table.find(toMuteList, targetPlayer))
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
		local toMuteList: { ReplayPlayer } = frame.players
		for _, player: ReplayPlayer in teammatesList do
			table.remove(toMuteList, table.find(toMuteList, player))
		end

		if muteSelf then
			table.remove(teammatesList, table.find(teammatesList, targetPlayer))
			table.insert(toMuteList, targetPlayer)
		end

		muteList(true, toMuteList)
		muteList(false, teammatesList)
	end

	if focusedArena and (#teammatesList == 0 and #lastTeammatesList > 0) then
		-- left arena
		print("left arena")
		if muteSelf then
			local toMuteList = frame.players
			table.remove(toMuteList, table.find(toMuteList, targetPlayer))
			muteList(false, toMuteList)
		else
			muteAll(false)
		end
	end

	if focusedArena and teamIndex ~= Util.TeamIndex.NoTeam and #lastServerPlayerList > 0 then
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

	for _, teammate in teammatesList do
		local tryFindTeammate = table.find(lastTeammatesList, teammate)

		if focusedArena and tryFindTeammate == nil then
			-- new player joined arena
			print(`arena join`)
			Settings.mutePlayerByName(teammate.playerName, false)
		end
	end

	for _, teammate in lastTeammatesList do
		local tryFindLastTeammate = table.find(teammatesList, teammate)

		if focusedArena and tryFindLastTeammate == nil then
			-- player left the arena
			print(`arena leave`)
			Settings.mutePlayerByName(teammate.playerName, true)
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

function anchorCollision(anchorPosition: Vec3, anchorOffsetPosition: Vec3): Vec3
	local anchor = anchorPosition + anchorOffsetPosition

	if collisions and anchorOffsetPosition ~= Vec3.zeroVector then
		local offsetForwards: Vec3 = Util.getForward(anchorPosition, anchorPosition + anchorOffsetPosition)
		local rayEnd: Vec3 = anchorPosition + (offsetForwards * (anchorOffsetPosition:length() + 10))
		local hit: RayHit = camera:castRay(anchorPosition, rayEnd)

		if hit.successful then
			local hitDistance: number = Util.getDist(rayEnd, hit.position)
			anchor += (offsetForwards * -hitDistance)
		end
	end

	return anchor
end

function moveCamera()
	cameraPivotOffset =
		Vec3.lerp(cameraPivotOffset, targetCameraPivotOffset, deltaTime / (cameraPositionSmoothing + deltaTime))

	local anchor = anchorCollision(cameraAnchor, cameraAnchorOffset)

	cameraPosition = anchor + cameraPivotOffset

	-- Collision
	if collisions and cameraPivotOffset ~= Vec3.zeroVector then
		local cameraForwards = Util.getForward(anchor, cameraPosition)
		local rayEnd: Vec3 = cameraPosition + (cameraForwards * 10)
		local hit: RayHit = camera:castRay(anchor, rayEnd)
		if hit.successful then
			local hitDistance: number = Util.getDist(rayEnd, hit.position)
			local radiusCm = radius * 10
			local thresholdCm = threshold * 10
			if radiusCm - hitDistance < thresholdCm then
				activeCameraMode = CameraMode.FirstPerson
				firstPersonOverride()
			else
				cameraPosition += Util.negateVec3(cameraForwards) * hitDistance
				activeCameraMode = cameraMode
			end
		else
			activeCameraMode = cameraMode
		end
	end

	camera.position = cameraPosition
end

function rotateCamera()
	local adjustedLookSmoothness = 1 - (1 - math.min(cameraRotationSmoothing, 0.99)) ^ 3
	camera.rotation = Quat.slerp(camera.rotation, cameraRotation, math.min(adjustedLookSmoothness * deltaTime * 60, 1))
end

function tick(dt)
	if not hasTickedOnce then
		hasTickedOnce = true
	end

	if not camera.isActive and not camera.isFollowed then
		alwaysTick = nil
		onExit()
		return
	end

	if not camera.isFollowed then
		WorldDraw.clear()
	end

	deltaTime = dt
	frame = Util.getReplayFrameFromIndex(readLocation)

	Emotes:tick()

	tryGetArenas()

	if #frame.players == 0 then
		noPlayerOrbit(dt)
		return
	end

	if not targetPlayer then
		setTargetPlayer(frame:getPlayerByName(targetPlayerName))
	end

	if not targetPlayer then -- double if statement to please the type checker
		noPlayerOrbit(dt)
		return
	end

	if arena == nil then
		noPlayerOrbit(dt)
		return
	end

	arena:tick()
	updatePlayerData(targetPlayer, frame)

	local ball = nil
	if targetPlayer.teamIndex ~= Util.TeamIndex.NoTeam and arena.ball then
		ball = arena.ball
	else
		ball = getClosestBall(targetPlayer.root.position, frame)
	end

	gravityUpDirection = targetPlayer.root.rotation:getUpVector()
	updateBallData(ball, dt)
	withPlayer(targetPlayer)
	configureVOIP()
	previousCameraMode = activeCameraMode
	previousTargetPlayerId = targetPlayer.playerId

	camera.hideNearestHead = hidePlayerHead

	rotateCamera()
end

function onExit()
	camera.showNameTags = true
	camera.hideNearestHead = false
	camera.nearClippingPlane = 0.001

	if targetPlayer and showQuests then -- show quests
		camera:showQuestsForPlayerById(targetPlayer.playerId, false)
	end

	stopRecording("exit camera")

	muteAll(false)
end

type MessageValues = {
	versionCallback: (string) -> ()?,
	guiCallback: (() -> ()) -> ()?,
	topSettingsCallback: (() -> ()) -> ()?,
	checkboxSettingsCallback: (() -> ()) -> ()?,
	playerSettingsCallback: (() -> ()) -> ()?,
	cameraSettingsCallback: (() -> ()) -> ()?,
	followSettingsCallback: (() -> ()) -> ()?,
	mainSettingsCallback: (() -> ()) -> ()?,
	autoCameraSettingsCallback: (() -> ()) -> ()?,
	savingSettingsCallback: (() -> ()) -> ()?,
	debugSettingsCallback: (() -> ()) -> ()?,
	gestureSettingsCallback: (() -> ()) -> ()?,
	autoShootingSettingsCallback: (() -> ()) -> ()?,
	goalCamSettingsCallback: (() -> ()) -> ()?,
	getTargetPlayerCallback: (() -> ReplayPlayer?) -> ()?,
	getFollowValuesCallback: (() -> FollowValues) -> ()?,
	readLocation: number?,
	showNameTags: boolean?,
	isLeftHanded: boolean?,
	muteSelf: boolean?,
	targetPlayer: ReplayPlayer?,
	targetPlayerName: string?,
	positionSmoothing: number?,
	rotationSmoothing: number?,
	cameraFOV: number?,
	cameraMode: number?,
	radius: number?,
	threshold: number?,
	cameraPositionOffset: string?,
	cameraEulerOffset: string?,
	gestureControls: boolean?,
	forwardGestureMode: number?,
	upGestureMode: number?,
	backwardsGestureMode: number?,
	autoBall: boolean?,
	simResolutionScale: number?,
	simTimeLength: number?,
	autoGoalCam: boolean?,
	ballGoalMode: number?,
	goalMode: number?,
	hideNearestHead: boolean?,
	showQuests: boolean?,
	autoRecordReplays: boolean?,
}

type FollowValues = {
	readLocation: number,
	showNameTags: boolean,
	isLeftHanded: boolean,
	muteSelf: boolean,
	targetPlayerName: string,
	positionSmoothing: number,
	rotationSmoothing: number,
	cameraFOV: number,
	cameraMode: number,
	radius: number,
	threshold: number,
	cameraPositionOffset: Vec3,
	cameraEulerOffset: Vec3,
	gestureControls: boolean,
	forwardGestureMode: number,
	upGestureMode: number,
	backwardsGestureMode: number,
	autoBall: boolean,
	simResolutionScale: number,
	simTimeLength: number,
	autoGoalCam: boolean,
	ballGoalMode: number,
	goalMode: number,
	hideNearestHead: boolean,
	showQuests: boolean,
	autoRecordReplays: boolean,
}

function getTargetPlayer(): ReplayPlayer?
	return targetPlayer
end

function getFollowValues(): FollowValues
	local values: FollowValues = {
		readLocation = readLocation,
		showNameTags = showNameTags,
		isLeftHanded = isLeftHanded,
		muteSelf = muteSelf,
		targetPlayerName = targetPlayerName,
		positionSmoothing = positionSmoothing,
		rotationSmoothing = rotationSmoothing,
		cameraFOV = cameraFOV,
		cameraMode = cameraMode,
		radius = radius,
		threshold = threshold,
		cameraPositionOffset = cameraPositionOffset,
		cameraEulerOffset = cameraEulerOffset,
		gestureControls = gestureControls,
		forwardGestureMode = forwardGestureMode,
		upGestureMode = upGestureMode,
		backwardsGestureMode = backwardsGestureMode,
		autoBall = autoBall,
		simResolutionScale = BallSim.resolutionScale,
		simTimeLength = BallSim.pathLengthSeconds,
		autoGoalCam = autoGoalCam,
		ballGoalMode = ballGoalMode,
		goalMode = goalMode,
		hideNearestHead = camera.hideNearestHead,
		showQuests = showQuests,
		autoRecordReplays = autoRecordReplays,
	}

	return values
end

function onMessageReceived(messageTable: MessageValues)
	-- only accept tables
	if type(messageTable) ~= "table" then
		return
	end

	if not hasTickedOnce then
		tick(0)
	end

	-- I set wasFollowed to true if a message was recieved to make sure the variables get reset once the camera is used standalone again
	wasFollowed = true

	-- showQuests is a boolean that shows quests for the followed player
	if messageTable.showQuests ~= nil then
		showQuests = messageTable.showQuests
	end
	if messageTable.versionCallback ~= nil then
		messageTable.versionCallback(_version)
	end
	-- callback is a function that takes some part of this cameras GUI as a parameter to receive for the messenger. This is usefull for displaying the same GUI in multiple cameras.
	-- some gui functions are inside others, like for instance the gestureSettings and followSettings being a part of mainSettings. They are seperated to make it easier to only display 1 of them.
	-- if you only wanted 1 or some of the Gui elements inside a function you can then reacreate the Gui yourself and overwrite the values through messaging.
	if messageTable.guiCallback ~= nil then
		messageTable.guiCallback(onGui)
	end
	if messageTable.topSettingsCallback ~= nil then
		messageTable.topSettingsCallback(topSettings)
	end
	if messageTable.checkboxSettingsCallback ~= nil then
		messageTable.checkboxSettingsCallback(checkboxSettings)
	end
	if messageTable.playerSettingsCallback ~= nil then
		messageTable.playerSettingsCallback(playerSettings)
	end
	if messageTable.cameraSettingsCallback ~= nil then
		messageTable.cameraSettingsCallback(cameraSettings)
	end
	if messageTable.mainSettingsCallback ~= nil then
		messageTable.mainSettingsCallback(mainSettings)
	end
	if messageTable.autoCameraSettingsCallback ~= nil then
		messageTable.autoCameraSettingsCallback(autoCameraSettings)
	end
	if messageTable.savingSettingsCallback ~= nil then
		messageTable.savingSettingsCallback(savingSettings)
	end
	if messageTable.debugSettingsCallback ~= nil then
		messageTable.debugSettingsCallback(debugSettings)
	end
	if messageTable.gestureSettingsCallback ~= nil then
		messageTable.gestureSettingsCallback(gestureSettings)
	end
	if messageTable.followSettingsCallback ~= nil then
		messageTable.followSettingsCallback(followSettings)
	end
	if messageTable.autoShootingSettingsCallback ~= nil then
		messageTable.autoShootingSettingsCallback(autoShootingSettings)
	end
	if messageTable.goalCamSettingsCallback ~= nil then
		messageTable.goalCamSettingsCallback(goalCamSettings)
	end

	-- getTargetPlayerCallback is a callback that accepts the getTargetPlayer function as a parameter. This allows addon scripts to access the targeted player obtained by follow+.
	if messageTable.getTargetPlayerCallback ~= nil then
		messageTable.getTargetPlayerCallback(getTargetPlayer)
	end
	if messageTable.getFollowValuesCallback ~= nil then
		messageTable.getFollowValuesCallback(getFollowValues)
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
	-- autoRecordReplays is a boolean that enables follow pluss to auto record your driftball rounds in replays.
	if messageTable.autoRecordReplays ~= nil then
		if Settings.getLuauReplayControlAllowed() then
			autoRecordReplays = messageTable.autoRecordReplays
		end
	end
	-- targetPlayer is a ReplayPlayer of the player the camera will follow. By setting targetPlayer it will attempt to switch to that player. If the player doesn't exist it will keep the current player as the targetPlayer.
	if messageTable.targetPlayer then
		setTargetPlayer(messageTable.targetPlayer)
	end
	-- targetPlayerName is a string used for getting the player you want to follow. if this is empty or unable to find the name typed in it follows noone.
	if messageTable.targetPlayerName then
		targetPlayerName = messageTable.targetPlayerName
		setTargetPlayer(Util.getReplayFrameFromIndex(readLocation):getPlayerByName(messageTable.targetPlayerName))
	end
	-- cameraFOV is a number that sets the camera FOV, the number can be set between 40 and 179
	if messageTable.cameraFOV then
		cameraFOV = messageTable.cameraFOV
		cameraFOV = math.clamp(cameraFOV, 40, 179)
	end
	-- positionSmoothing is a number that sets the cameras positions smoothing, the number can be set between 0.000 and 1.000
	if messageTable.positionSmoothing then
		positionSmoothing = messageTable.positionSmoothing
		cameraPositionSmoothing = positionSmoothing
	end
	-- positionSmoothing is a number that sets the cameras rotation smoothing, the number can be set between 0.000 and 1.000
	if messageTable.rotationSmoothing then
		rotationSmoothing = messageTable.rotationSmoothing
		cameraRotationSmoothing = rotationSmoothing
	end
	-- cameraMode is a number that sets the cameras follow mode. There are currently 4 modes, and the first one starts at 1.
	if messageTable.cameraMode then
		cameraMode = messageTable.cameraMode
		activeCameraMode = cameraMode
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
	-- simResolutionScale is a number that sets the scale of the resolution of the ball prediciton. A resolution scale of 1 means the prediction is running at 90 fps, this is horrible for performance so it is recommended to have a resolution scale of around 0.3 when predicting far into the future.
	if messageTable.simResolutionScale then
		BallSim.resolutionScale = math.clamp(messageTable.simResolutionScale, 0.1, 1)
	end
	-- simTimeLength is a number that sets the amount of seconds into the future the ball predicition should predict.
	if messageTable.simTimeLength then
		BallSim.pathLengthSeconds = math.clamp(messageTable.simTimeLength, 0, 6)
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
	if messageTable.hideNearestHead ~= nil then
		hidePlayerHead = messageTable.hideNearestHead
		camera.hideNearestHead = hidePlayerHead
	end
end
