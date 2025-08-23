metadata = {
	name = "Follow Pluss Msg Example",
	description = "Example script that shows you how to use messaging with follow pluss with explanations and examples",
	author = "Dennssen",
	defaultKeybind = "",
}

-- creating a custom message variable/function forcing this type creates a better programming experience and ensures you are typing the variables correctly
type MessageValues = {
	versionCallback: (string) -> ()?,
	callback: (() -> ()) -> ()?,
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
}

-- store the camera for easy access
local followPlussCamera: SpectatorCamera

-- these are enum tables that make it easier to change to the correct mode without having to remember what number is assotiated with what mode. Highly recommended.
local CameraMode = {
	FirstPerson = 1,
	HeadRotation = 2,
	VelocityRotation = 3,
	FaceTheBall = 4,
	HandHeld = 5,
}
local GoalMode = {
	YourGoal = 1,
	BothGoals = 2,
}
local BallGoalMode = {
	EnemyGoal = 1,
	BothGoals = 2,
}

--- Examples of how to use the Enums ---
local _changeCameraMode: MessageValues = { -- CameraMode Example
	cameraMode = CameraMode.HeadRotation,
}
local _changeGoalMode: MessageValues = { -- GoalMode Example
	goalMode = GoalMode.BothGoals,
}
local _changeBallGoalMode: MessageValues = { -- BallGoalMode Example
	BallGoalMode = BallGoalMode.EnemyGoal,
}

-- helper function to get game data from both replays and live
function getReplayFrameFromIndex(replayIndex: number)
	replayIndex = math.clamp(replayIndex, 0, #Replay.listLoaded())
	local replay = Replay.getByIndex(replayIndex)
	if replay then
		return replay:getCurrentFrame(true)
	else
		-- 0 = live game
		return getGameData()
	end
end

-- message for overwritting the default values.
local defaultValues: MessageValues = {
	readLocation = 5, -- this tries to change the game data to read from replay number 5, however there most likely isn't 5 replays active but this is fine and won't crash anything. it will however clamp to the nearest replay, and if no replays are active it will use live data.
	showNameTags = true,
	isLeftHanded = false, -- this makes it so when using Hand Held mode the camera will go on the players right hand
	muteSelf = true, -- this will mute the player that you are following
	targetPlayer = getReplayFrameFromIndex(5):getPlayerByName("Griid"), -- If Griid is found by this camera then follow pluss will switch to Griid as the targetPlayer (make sure this camera and follow pluss shares the same read location by using something like getReplayFrameFromIndex())
	targetPlayerName = "Griid", -- If Griid is found by follow pluss then it will switch to Griid as the targetPlayer
	positionSmoothing = 0.1,
	rotationSmoothing = 0.2,
	cameraFOV = 90,
	cameraMode = CameraMode.FirstPerson, -- this is one of the examples where the enum table comes in handy, instead of writing 1, CameraMode.FirstPerson makes more sense to read and does the same thing.
	radius = 40, -- this doesn't affect First Person
	threshold = 0, -- This means if the current camera mode is Head Rotation, no matter how close the camera gets to the player it will never switch to First Person.
	cameraPositionOffset = tostring(Vec3.new(-25, 0, 50)), -- Only takes affect for First Person and Head Rotation Modes.
	cameraEulerOffset = tostring(Vec3.new(0, 0, 15)), -- Only takes affect for First Person and Head Rotation Modes.
	gestureControls = true, -- This enables gesture controls allowing the player to pick up their camera and throw it to change modes form in game. Note: This might be good to disable if you don't want to switch modes.
	forwardGestureMode = CameraMode.FaceTheBall, -- This overrides the default forwards gesture and sets the new mode to FaceTheBall. When changing gesture modes it is important to remember that First Person and HandHeld will not work.
	upGestureMode = CameraMode.FirstPerson, -- This tries to set the up gesture to First Person, but it will not work as these customizable gestures with directions don't accept First Person or Hand Held
	backwardsGestureMode = CameraMode.HeadRotation, -- This sets the backwards gesture to its default mode. When changing gesture modes it is important to remember that First Person and HandHeld will not work.
	autoBall = false, -- disables the auto shooting camera.
	simResolutionScale = 0.2, -- A resolution scale of 1 means the simulation is running at 90 fps, this will usually tank performance heavily.
	simTimeLength = 4, -- sets the ball prediction to predict 4 seconds into the future.
	ballGoalMode = BallGoalMode.EnemyGoal, -- sets the ball goal mode to Enemy Goal making it so the auto shooting camera only activates when the ball is being shot at the enemy goal.
	autoGoalCam = false, -- disables the auto goal camera.
	goalMode = GoalMode.BothGoals, -- sets the auto goal camera to activate when near both goals, instead of only your own teams goal.
	showQuests = false, -- disables visable quests for the followed player.
}

-- none of these values are needed, if any are left out they stay as they are. This means you only have to change the values you care about.
-- e.g if you only want to change the targeted player, you only include targetPlayerName in the table.

-- More information on what the different values mean is at the bottom of the follow pluss script inside the onMessageRecived() function.

-- messages can also be used to completely prevent changes without having control over the GUI
local preventAutoBallCamera: MessageValues =
	{ -- using variables with message types makes it easier to type the correct values
		autoBall = false,
	}

local followPlussGui: () -> () = nil -- the appened gui from the followPluss Camera

-- this function runs when followpluss gets asked for the gui, it then takes the function given and stores it localy for use in your own GUI
function guiCallback(func: () -> ())
	followPlussGui = func
end

local askForGui: MessageValues = { -- using variables with message types makes it easier to type the correct values
	callback = guiCallback,
}

local followPlussVersion: string = ""

function versionCallback(version: string)
	followPlussVersion = version
end

local askForVersion: MessageValues = {
	versionCallback = versionCallback,
}

function main()
	-- the main function is the EARLIEST point you can get another spectatorCamera without causing issues (e.i don't call getCamera during initialization)
	followPlussCamera = getCameraById("dennssen.followpluss")
	sendMessage(followPlussCamera, askForVersion)
end

function onTransitionBegin(transitionInfo: Transition)
	-- set our default values
	sendMessage(followPlussCamera, defaultValues)

	camera:followCamera(followPlussCamera) -- this is just to avoid staring into nothingness at 0, 0, 0. it is not needed for the message to reach the camera
end

function onGui()
	Gui.text("This is the default GUI")
	Gui.text("everything after this text is captured from followpluss GUI")
	Gui.text(`You are using version {followPlussVersion} of follow pluss`)
	if followPlussGui ~= nil then
		followPlussGui()
	else
		-- send call to receive gui if it hasn't already got it
		sendMessage(followPlussCamera, askForGui)
	end

	-- if there are certaint values you want to restrict the player from changing in the GUI you can override them manually at the end of the onGui function to ensure their wanted value
	sendMessage(followPlussCamera, preventAutoBallCamera)
end
