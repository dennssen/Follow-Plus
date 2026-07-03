local Util = require("util")

local Box = require("box")
type BoxType = typeof(Box)

type GoalCamData = {
	goalCam: { position: Vec3, rotation: Quat },
}

local Arena = require("arena")
export type Arena<ArenaData, HomeData, AwayData> = Arena.Arena<ArenaData, HomeData, AwayData>
export type ArenaGoal = Arena.ArenaGoal
export type FollowArena = Arena<{}, GoalCamData, GoalCamData> & {
	checkGoalCam: (self: FollowArena, player: ReplayPlayer, goalMode: number, transition: boolean) -> boolean,
	goalCam: (self: FollowArena, goalPosition: Vec3, goalRotation: Quat, goalCamFOV: number, transition: boolean) -> (),
	getClosestGoalTransform: (self: FollowArena, position: Vec3) -> ArenaGoal,
}

local goalCamFOV = 120
local cameraInAwayGoal: boolean = false
local cameraInHomeGoal: boolean = false
local GoalMode = {
	MyGoal = 1,
	BothGoals = 2,
}

local FollowArena = {} :: FollowArena
FollowArena.__index = FollowArena
setmetatable(FollowArena, { __index = Arena })

function FollowArena:getClosestGoalTransform(position: Vec3): ArenaGoal
	local homeGoalDist: number = Vec3.distance(self.home.goal.position, position)
	local awayGoalDist: number = Vec3.distance(self.away.goal.position, position)

	if homeGoalDist < awayGoalDist then
		return self.home.goal
	else
		return self.away.goal
	end
end

export type Arena3v3 = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
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

function Arena3v3.new(gamemode: ModuleStateSpectatorLuaApi, readLocation: number): FollowArena
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

function Arena3v3:checkGoalCam(player: ReplayPlayer, goalMode: number, transition: boolean): boolean
	if
		not cameraInAwayGoal
		and Util.getDist(self.away.goal.position, player.root.position) < Arena3v3.enterGoalCamDist
		and player.teamIndex ~= Util.TeamIndex.NoTeam
	then
		if
			goalMode == GoalMode.MyGoal and player.teamIndex == Util.TeamIndex.AwayTeam
			or goalMode == GoalMode.BothGoals
		then
			cameraInAwayGoal = true
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
			cameraInHomeGoal = true
		end
	end

	if cameraInAwayGoal and Util.getDist(self.away.goal.position, player.root.position) > Arena3v3.exitGoalCamDist then
		cameraInAwayGoal = false
	end

	if cameraInHomeGoal and Util.getDist(self.home.goal.position, player.root.position) > Arena3v3.exitGoalCamDist then
		cameraInHomeGoal = false
	end

	if cameraInAwayGoal then
		self:goalCam(self.away.data.goalCam.position, self.away.data.goalCam.rotation, goalCamFOV, transition)
		return true
	elseif cameraInHomeGoal then
		self:goalCam(self.home.data.goalCam.position, self.home.data.goalCam.rotation, goalCamFOV, transition)
		return true
	end

	return false
end

function Arena3v3:GUIChangeDimensions()
	Arena3v3.boxSize = Gui.dragFloat3("Arena3v3 Arena Size", Arena3v3.boxSize, 1, -math.huge, math.huge)
	Arena3v3.boxOffset = Gui.dragFloat3("Arena3v3 Position Offset", Arena3v3.boxOffset, 1, -math.huge, math.huge)
	Arena3v3.goalBoxSize = Gui.dragFloat3("Arena3v3 Goal Size", Arena3v3.goalBoxSize, 1, -math.huge, math.huge)
	Arena3v3.goalPositionOffset =
		Gui.dragFloat3("Arena3v3 Goal Position Offset", Arena3v3.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena3v3.boxSize}`)
		print(`boxOffset: {Arena3v3.boxOffset}`)
		print(`goalBoxSize: {Arena3v3.goalBoxSize}`)
		print(`goalPositionOffset: {Arena3v3.goalPositionOffset}`)
	end

	self:setupDimensions()
end

export type Arena4v4 = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
	goalBoxSize: Vec3,
	goalPositionOffset: Vec3,
}

local Arena4v4 = {} :: Arena4v4
Arena4v4.__index = Arena4v4
setmetatable(Arena4v4, { __index = FollowArena })

Arena4v4.homeRotationOffset = Quat.fromEuler(0, 0, 90)
Arena4v4.awayRotationOffset = Quat.fromEuler(0, 0, -90)
Arena4v4.boxSize = Vec3.new(6715, 8400, 1490)
Arena4v4.boxOffset = Vec3.new(0, 0, 685)
Arena4v4.goalBoxSize = Vec3.new(165, 450, 225)
Arena4v4.goalPositionOffset = Vec3.new(4085, 0, 270)

function Arena4v4.new(gamemode: ModuleStateSpectatorLuaApi, readLocation: number): FollowArena
	local self: FollowArena = setmetatable(Arena.new(gamemode, readLocation), Arena4v4) :: any
	self.type = "4v4"

	local name: string = ""

	if self.slotId:find("TKB") then
		name = self.slotId:gsub("TKB_", "")
	elseif self.slotId:find("_") then
		local nameEnd = self.slotId:find("_") :: number
		name = `{self.slotId:sub(1, nameEnd - 1)} {self.slotId:sub(self.slotId:len() - 2)}`
	else
		name = self.slotId
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

function Arena4v4:checkGoalCam(player: ReplayPlayer, goalMode: number): boolean
	return false
end

function Arena4v4:GUIChangeDimensions()
	Arena4v4.boxSize = Gui.dragFloat3("Arena4v4 Arena Size", Arena4v4.boxSize, 1, -math.huge, math.huge)
	Arena4v4.boxOffset = Gui.dragFloat3("Arena4v4 Position Offset", Arena4v4.boxOffset, 1, -math.huge, math.huge)
	Arena4v4.goalBoxSize = Gui.dragFloat3("Arena4v4 Goal Size", Arena4v4.goalBoxSize, 1, -math.huge, math.huge)
	Arena4v4.goalPositionOffset =
		Gui.dragFloat3("Arena4v4 Goal Position Offset", Arena4v4.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Arena4v4.boxSize}`)
		print(`boxOffset: {Arena4v4.boxOffset}`)
		print(`goalBoxSize: {Arena4v4.goalBoxSize}`)
		print(`goalPositionOffset: {Arena4v4.goalPositionOffset}`)
	end

	self:setupDimensions()
end

export type Driftblitz = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
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
Driftblitz.goalBoxSize = Vec3.new(100, 890, 300)
Driftblitz.goalPositionOffset = Vec3.new(5295, 0, 175)

function Driftblitz.new(gamemode: ModuleStateSpectatorLuaApi, readLocation: number): FollowArena
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

function Driftblitz:checkGoalCam(player: ReplayPlayer, goalMode: number): boolean
	return false
end

function Driftblitz:GUIChangeDimensions()
	Driftblitz.boxSize = Gui.dragFloat3("Driftblitz Arena Size", Driftblitz.boxSize, 1, -math.huge, math.huge)
	Driftblitz.boxOffset = Gui.dragFloat3("Driftblitz Position Offset", Driftblitz.boxOffset, 1, -math.huge, math.huge)
	Driftblitz.goalBoxSize = Gui.dragFloat3("Driftblitz Goal Size", Driftblitz.goalBoxSize, 1, -math.huge, math.huge)
	Driftblitz.goalPositionOffset =
		Gui.dragFloat3("Driftblitz Goal Position Offset", Driftblitz.goalPositionOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Driftblitz.boxSize}`)
		print(`boxOffset: {Driftblitz.boxOffset}`)
		print(`goalBoxSize: {Driftblitz.goalBoxSize}`)
		print(`goalPositionOffset: {Driftblitz.goalPositionOffset}`)
	end

	self:setupDimensions()
end

export type ZDrift = FollowArena & {
	homeRotationOffset: Quat,
	awayRotationOffset: Quat,
	boxSize: Vec3,
	boxOffset: Vec3,
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
ZDrift.goalBoxSize = Vec3.new(600, 600, 600)
ZDrift.goalPositionOffset = Vec3.new(8200, 0, 585)

function ZDrift.new(gamemode: ModuleStateSpectatorLuaApi, readLocation: number): FollowArena
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

function ZDrift:checkGoalCam(player: ReplayPlayer, goalMode: number): boolean
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

export type Strike = FollowArena & {
	boxSize: Vec3,
	boxOffset: Vec3,
}

local Strike = {} :: Strike
Strike.__index = Strike
setmetatable(Strike, { __index = FollowArena })

Strike.boxSize = Vec3.new(2050, 2050, 1050)
Strike.boxOffset = Vec3.new(0, 0, 415)

function Strike.new(gamemode: ModuleStateSpectatorLuaApi, readLocation: number): FollowArena
	local self = setmetatable(FollowArena.new(gamemode, readLocation), Strike) :: any
	self.type = "strike"

	if self.slotId:find("FieldHouse") then
		local split = self.slotId:split(" ")
		local _, number = split[1], tonumber(split[2])
		local patchedNumber = typeof(number) == "number" and tostring(number - 2) or split[2]

		self.name = `Strike {patchedNumber}`
	elseif self.slotId:find("HalfG") then
		self.name = `Strike HalfG`
	else
		self.name = self.slotId
	end

	self:setupDimensions()
	return self :: ZDrift
end

function Strike:isPointOnHomeSide(point: Vec3): boolean
	-- There is no Home or Away
	return true
end

function Strike:setupDimensions()
	self.box = Box.new(
		self.transform.position + self.transform.rotation:rotateVector(Strike.boxOffset),
		Strike.boxSize,
		self.transform.rotation
	)
end

function Strike:getTeamRotation(teamIndex: number): Quat
	return self.transform.rotation
end

function Strike:checkGoalCam(player: ReplayPlayer, goalMode: number): boolean
	return false
end

function Strike:GUIChangeDimensions()
	Strike.boxSize = Gui.dragFloat3("Strike Arena Size", Strike.boxSize, 1, -math.huge, math.huge)
	Strike.boxOffset = Gui.dragFloat3("Strike Position Offset", Strike.boxOffset, 1, -math.huge, math.huge)
	Strike.centerBoxOffset =
		Gui.dragFloat3("Strike Place Ball Box Position Offset", Strike.centerBoxOffset, 1, -math.huge, math.huge)

	if Gui.button("Print Dimensions") then
		print(`boxSize: {Strike.boxSize}`)
		print(`boxOffset: {Strike.boxOffset}`)
		print(`centerBoxOffset: {Strike.centerBoxOffset}`)
	end

	self:setupDimensions()
end

return {
	FollowArena = FollowArena,
	Arena3v3 = Arena3v3,
	Arena4v4 = Arena4v4,
	Driftblitz = Driftblitz,
	ZDrift = ZDrift,
	Strike = Strike,
}
