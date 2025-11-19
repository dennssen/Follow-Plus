--!strict

local Util = require("util")

export type HUD = {
	__index: HUD,
	cameraId: string,
	width: number,
	height: number,
	depth: number,
	transform: {
		origin: Vec3,
		top: Vec3,
		left: Vec3,
		bottom: Vec3,
		right: Vec3,
	},

	new: (cameraId: string, width: number, height: number, depth: number) -> HUD,
	setCamera: (self: HUD, cameraId: string) -> (),
	generateTransform: (self: HUD) -> (),

	tick: (self: HUD) -> (),
	drawPoint: (self: HUD, anchor: Vec2, color: Vec3, pointSize: number, lifetime: number) -> (),
	drawLine: (self: HUD, startAnchor: Vec2, endAnchor: Vec2, color: Vec3, thickness: number, lifetime: number) -> (),
	drawTriangle: (self: HUD, anchor1: Vec2, anchor2: Vec2, anchor3: Vec2, color: LinearColor, lifetime: number) -> (),
	worldToHUD: (self: HUD, worldPosition: Vec3) -> Vec2,
	convertOffsetToHUD: (self: HUD, offset: Vec2) -> Vec3,
	convertHUDToOffset: (self: HUD, point: Vec3) -> Vec2,
	getApparentLength: (self: HUD, length: number, point: Vec3) -> number,
	getUniversalLength: (self: HUD, length: number) -> number,
}

local HUD: HUD = {} :: HUD
HUD.__index = HUD

function HUD.new(cameraId: string, width: number, height: number, depth: number): HUD
	local self: HUD = setmetatable({}, HUD) :: any
	self.cameraId = cameraId
	self.width = width
	self.height = height
	self.depth = depth

	self:generateTransform()

	return self :: HUD
end

function HUD:setCamera(cameraId: string)
	self.cameraId = cameraId
end

function HUD:generateTransform()
	self.transform = {} :: any

	local _camera

	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local _cameraPosition: Vec3
	local _cameraRotation: Quat
	_cameraPosition = _camera.position
	_cameraRotation = _camera.rotation

	self.transform.origin = _cameraPosition + (_cameraRotation:getForwardVector() * self.depth)

	local fovRad = math.rad(_camera.fieldOfView)
	local aspectRatio = self.width / self.height
	local halfWidth = math.tan(fovRad / 2) * self.depth
	local halfHeight = halfWidth / aspectRatio

	self.transform.top = self.transform.origin + (_cameraRotation:getUpVector() * halfHeight)
	self.transform.left = self.transform.origin + (_cameraRotation:getRightVector() * -halfWidth)
	self.transform.bottom = self.transform.origin + (_cameraRotation:getUpVector() * -halfHeight)
	self.transform.right = self.transform.origin + (_cameraRotation:getRightVector() * halfWidth)
end

function HUD:tick()
	self:generateTransform()
end

function HUD:drawPoint(anchor: Vec2, color: Vec3, pointSize: number, lifetime: number)
	local vec = self.transform.origin + self:convertOffsetToHUD(anchor)
	WorldDraw.drawPoint(vec, color.x, color.y, color.z, pointSize, lifetime)
end

function HUD:drawLine(startAnchor: Vec2, endAnchor: Vec2, color: Vec3, thickness: number, lifetime: number)
	local vec1 = self.transform.origin + self:convertOffsetToHUD(startAnchor)
	local vec2 = self.transform.origin + self:convertOffsetToHUD(endAnchor)
	WorldDraw.drawLine(vec1, vec2, color.x, color.y, color.z, thickness, lifetime)
end

function HUD:drawTriangle(anchor1: Vec2, anchor2: Vec2, anchor3: Vec2, color: LinearColor, lifetime: number)
	local vec1 = self.transform.origin + self:convertOffsetToHUD(anchor1)
	local vec2 = self.transform.origin + self:convertOffsetToHUD(anchor2)
	local vec3 = self.transform.origin + self:convertOffsetToHUD(anchor3)
	WorldDraw.drawTriangle(vec1, vec2, vec3, color, lifetime)
end

function HUD:worldToHUD(worldPosition: Vec3): Vec2
	local _camera

	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local camPos = _camera.position
	local camForward = _camera.rotation:getForwardVector()
	local hudOrigin = self.transform.origin

	local rayDir = (worldPosition - camPos):getSafeNormal()
	local denom = camForward:dot(rayDir)

	if denom <= 1e-3 then
		return Vec2.zeroVector
	end

	-- Ray-plane intersection:
	local t = (hudOrigin - camPos):dot(camForward) / denom
	local projected = camPos + rayDir * t
	local converted = self:convertHUDToOffset(projected)

	return converted
end

function HUD:convertOffsetToHUD(offset: Vec2): Vec3
	local _camera

	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local fovRad = math.rad(_camera.fieldOfView)
	local aspectRatio = self.width / self.height
	local halfWidth = math.tan(fovRad / 2) * self.depth
	local halfHeight = halfWidth / aspectRatio

	local convertedOffset: Vec3 =
		Vec3.new(0, (offset.x / self.width) * halfWidth, (offset.y / self.height) * halfHeight)

	return _camera.rotation:rotateVector(convertedOffset)
end

function HUD:convertHUDToOffset(position: Vec3): Vec2
	local _camera

	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local fovRad = math.rad(_camera.fieldOfView)
	local aspectRatio = self.width / self.height
	local halfWidth = math.tan(fovRad / 2) * self.depth
	local halfHeight = halfWidth / aspectRatio

	local localPosition = _camera.rotation:inverse():rotateVector(position - self.transform.origin)

	local offsetX = (localPosition.y / halfWidth) * self.width
	local offsetY = (localPosition.z / halfHeight) * self.height

	return Vec2.new(offsetX, offsetY)
end

function HUD:getApparentLength(length: number, point: Vec3): number
	local _camera
	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local fovRad = math.rad(_camera.fieldOfView)
	local halfWidth = math.tan(fovRad / 2) * self.depth
	local distance = Util.getDist(_camera.position, point)
	local apparentWorldLength = self.depth * (length / distance)

	return (apparentWorldLength / halfWidth) * self.width
end

function HUD:getUniversalLength(length: number): number
	local _camera

	if self.cameraId ~= "" then
		_camera = getCameraById(self.cameraId)
	else
		_camera = camera
	end

	local fovRad = math.rad(_camera.fieldOfView)
	local aspectRatio = self.width / self.height
	local halfWidth = math.tan(fovRad / 2) * self.depth
	local halfHeight = halfWidth / aspectRatio

	return (length / self.height) * halfHeight
end

return HUD
