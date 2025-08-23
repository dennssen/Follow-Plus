--!strict

-- Dep
local Util = require("util")

local Arena = require("arena")
type Arena = Arena.Arena

-- What can be improved:
-- Rolling, basically collision but with no bounce.

-- Sim Class
type BallSim = {
	__index: BallSim,
	arena: Arena?,
	ball: ReplayBall?,
	previousBallRotation: Quat,

	angularVelocity: Vec3,

	resolutionScale: number,
	pathLengthSeconds: number,

	drag: number,
	angularDamping: number,
	rollingFriction: number,
	maxDragAcceleration: number,
	gravityScale: number,
	mass: number,
	radius: number,
	restitution: number,
	collisionRotations: { Quat },
	simPositions: { Vec3 },

	setResolutionScale: (self: BallSim, resolutionScale: number) -> (),

	tick: (self: BallSim) -> (),
	getAngularVelocity: (self: BallSim, ball: ReplayBall) -> (),
	simBallPath: (self: BallSim, ball: ReplayBall, steps: number, dt: number) -> (),
	simBallCollision: (
		self: BallSim,
		previousVelocity: Vec3,
		previousPosition: Vec3,
		currentPosition: Vec3,
		dt: number,
		debug: boolean
	) -> { collision: boolean, collisionPosition: Vec3, hitNormal: Vec3, remainingDt: number },
	simBallBounce: (self: BallSim, normal: Vec3, currentVelocity: Vec3, dt: number) -> Vec3,
	isInGoal: (self: BallSim) -> { home: boolean, away: boolean },
	getClosestSimPointToGoal: (self: BallSim) -> number,
	renderBallPath: (self: BallSim) -> (),

	debug: boolean,
}

local BallSim: BallSim = {} :: BallSim
BallSim.__index = BallSim
BallSim.arena = nil
BallSim.ball = nil
BallSim.angularVelocity = Vec3.zeroVector
BallSim.previousBallRotation = Quat.identity

BallSim.pathLengthSeconds = 4
BallSim.resolutionScale = 0.3

BallSim.drag = 0.125
BallSim.angularDamping = 0
BallSim.rollingFriction = 0.2
BallSim.maxDragAcceleration = 115
BallSim.gravityScale = 0.7
BallSim.mass = 1
BallSim.radius = 17
BallSim.restitution = 0.375
BallSim.collisionRotations = {
	Quat.identity, -- forward
	Quat.fromEuler(0, 0, 90), -- right
	Quat.fromEuler(0, 0, -90), -- left
	Quat.fromEuler(90, 0, 0), -- up
	Quat.fromEuler(-90, 0, 0), -- down
}
BallSim.simPositions = {}

BallSim.debug = false

-- a = Acceleration cm/s^2
-- v = velocity cm/s
-- g = gravity cm/s^2
-- gs = gravity scale
-- d = drag

-- a = (v + g × gs) × (1 - d) - v

-- start time: 20.012s
-- 0s velocity: 0 cm/s
-- 1s velocity: 390.43 cm/s
-- 1s acc: 390.43
-- 2s velocity: 769.31 cm/s
-- 2s acc: 378.88

-- 390.43 = (0 + 550 x gs) x (1 - d) - 0
-- 378.88 = (390.43 + 550 x gs) x (1 - d) - 390.43

-- start time: 20.3s
-- 0s velocity: 117.81 cm/s
-- 1s velocity: 500.14 cm/s
-- 1s acc: 382.33
-- 2s velocity: 877.92 cm/s
-- 2s acc: 377.78

-- 382.33 = (117.81 + 550 x gs) x (1 - d) - 117.81
-- 377.78 = (500.14 + 550 x gs) x (1 - d) - 500.14

function BallSim:setResolutionScale(resolutionScale: number)
	resolutionScale = math.clamp(resolutionScale, 0.1, 1)
	self.resolutionScale = resolutionScale
end

function BallSim:tick()
	if self.arena then
		self.ball = self.arena.ball
	end

	if not self.ball then
		return
	end

	local resolution = 90 * self.resolutionScale

	self:getAngularVelocity(self.ball)
	self:simBallPath(self.ball, resolution * self.pathLengthSeconds, 1 / resolution)

	if self.debug then
		self:renderBallPath()
	end
end

function BallSim:getAngularVelocity(ball: ReplayBall)
	local deltaEuler = ball.transform.rotation:euler() - self.previousBallRotation:euler()
	self.angularVelocity = deltaEuler
end

function BallSim:simBallPath(ball: ReplayBall, steps: number, dt: number)
	self.simPositions = { ball.transform.position }
	local currentPosition = ball.transform.position
	local currentVelocity = ball.velocity
	for i = 1, steps, 1 do
		local previousVelocity: Vec3 = currentVelocity

		local dragAcceleration = currentVelocity * -self.drag
		dragAcceleration = Util.clampMagnitude3(dragAcceleration, self.maxDragAcceleration)

		currentVelocity = currentVelocity + (gravity.gravity * self.gravityScale * dt)

		currentVelocity = currentVelocity + (dragAcceleration * dt)

		currentVelocity = Util.clampMagnitude3(currentVelocity, 18 * 100)

		local angularDampingFactor = 1 - (self.angularDamping * dt)
		self.angularVelocity = self.angularVelocity * math.max(0, angularDampingFactor)

		currentPosition = currentPosition + (currentVelocity * dt)

		-- collision
		local lastPosition: Vec3 = self.simPositions[#self.simPositions]

		local debugCollision: boolean = i == 1

		local collisionInfo = self:simBallCollision(previousVelocity, lastPosition, currentPosition, dt, debugCollision)
		if collisionInfo.collision then
			currentPosition = collisionInfo.collisionPosition
			local bounceVelocity = self:simBallBounce(collisionInfo.hitNormal, currentVelocity, dt)

			currentVelocity = bounceVelocity
			currentPosition = currentPosition + (currentVelocity * collisionInfo.remainingDt)
		end

		table.insert(self.simPositions, currentPosition)
	end
end

function BallSim:simBallCollision(
	previousVelocity: Vec3,
	previousPosition: Vec3,
	currentPosition: Vec3,
	dt: number,
	debug: boolean
): { collision: boolean, collisionPosition: Vec3, hitNormal: Vec3, remainingDt: number }
	local collisionInfo = {
		collision = false,
		collisionPosition = currentPosition,
		hitNormal = Vec3.zeroVector,
		remainingDt = dt,
	}

	local ballDirection: Vec3 = previousVelocity:normalize()
	local lastHit = {
		hitPosition = Vec3.zeroVector,
		hitStart = Vec3.zeroVector,
	}

	for _, collisionRotation: Quat in self.collisionRotations do
		local offset: Vec3 = collisionRotation:rotateVector(ballDirection) * self.radius
		local hit: RayHit = camera:castRay(previousPosition + offset, currentPosition + offset)

		if hit.successful then
			if
				lastHit.hitPosition ~= Vec3.zeroVector
				and Util.getDist(hit.position, previousPosition + offset)
					> Util.getDist(lastHit.hitPosition, lastHit.hitStart)
			then
				if debug then
					WorldDraw.drawLine(previousPosition + offset, currentPosition + offset, 1, 0, 0, 1, 0)
				end
				continue
			end

			if debug then
				WorldDraw.drawLine(previousPosition + offset, currentPosition + offset, 0, 1, 0, 1, 0)
			end

			collisionInfo.collision = true
			collisionInfo.hitNormal = hit.normal

			local bounceRatio = Util.getDist(hit.position, currentPosition)
				/ Util.getDist(previousPosition, currentPosition)
			collisionInfo.remainingDt = dt * (1 - bounceRatio)

			collisionInfo.collisionPosition = hit.position + (hit.normal * self.radius)
			lastHit.hitPosition = hit.position
			lastHit.hitStart = previousPosition + offset
		else
			if self.debug and debug then
				WorldDraw.drawLine(previousPosition + offset, currentPosition + offset, 0, 1, 1, 1, 0)
			end
		end
	end

	if self.debug then
		WorldDraw.drawLine(
			collisionInfo.collisionPosition,
			collisionInfo.collisionPosition + collisionInfo.hitNormal * 100,
			0,
			0,
			1,
			10,
			0
		)
	end

	return collisionInfo
end

function BallSim:simBallBounce(normal: Vec3, currentVelocity: Vec3, dt: number): Vec3
	local ballCircumference = 2 * math.pi * self.radius
	local angularDegreesSeconds = self.angularVelocity:length()
	local angularContribution = 0
	if angularDegreesSeconds > 0 then
		angularContribution = self.angularVelocity:length() / 360 * ballCircumference
	end
	local surfaceVelocity = currentVelocity + (currentVelocity:normalize() * angularContribution)

	local normalCompoent = normal * surfaceVelocity:dot(normal)
	local tangentialComponent = surfaceVelocity - normalCompoent

	local bounceNormal = normalCompoent * -self.restitution

	local frictionTangential = tangentialComponent * (1 - self.rollingFriction)

	local velocity = bounceNormal + frictionTangential

	return velocity
end

function BallSim:isInGoal(): { home: boolean, away: boolean }
	local isInGoal = {
		home = false,
		away = false,
	}

	if not self.arena then
		return isInGoal
	end

	for _, ballPos: Vec3 in self.simPositions do
		local homeDist: number = Util.getDist(ballPos, self.arena.home.goal.position)
		local awayDist: number = Util.getDist(ballPos, self.arena.away.goal.position)

		if homeDist < 500 and self.arena.home.goal.box:checkPointIntersect(ballPos) then
			isInGoal.home = true
			break
		elseif awayDist < 500 and self.arena.away.goal.box:checkPointIntersect(ballPos) then
			isInGoal.away = true
			break
		end
	end

	return isInGoal
end

function BallSim:getClosestSimPointToGoal()
	local closestSimPointDistance: number = math.huge

	if not self.arena then
		return closestSimPointDistance
	end

	for _, simPoint: Vec3 in self.simPositions do
		local homeDist: number = Util.getDist(simPoint, self.arena.home.goal.position)
		local awayDist: number = Util.getDist(simPoint, self.arena.away.goal.position)

		local closestPoint: number = math.min(homeDist, awayDist)
		if closestPoint < closestSimPointDistance then
			closestSimPointDistance = closestPoint
		end
	end

	return closestSimPointDistance
end

function BallSim:renderBallPath()
	local lastPosition: Vec3? = nil
	for _, position: Vec3 in self.simPositions do
		if lastPosition then
			WorldDraw.drawLine(lastPosition, position, 1, 0, 1, 10, 0)
		end
		lastPosition = position
	end
end

return BallSim
