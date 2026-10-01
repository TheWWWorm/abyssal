extends RefCounted
## Device-neutral analog steering. Only the most recently used controller owns flight.
## Each stick axis has a role, set in the Gamepad settings. By default the right
## stick aims, so the left stick is free to strafe instead of turn.
##
## D-pad left cycles the camera on a tap. Held, it lends the right stick to the
## camera, which swings back behind the hull once both are let go.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
var device := -1
var axes := {}
var buttons := {}
var deadzone := 0.18
var invert := false
var blocked := false
## Roles for left X, left Y, right X, right Y.
var roles: Array = DEFAULT_ROLES.duplicate()
## The right stick turned the camera while D-pad left was held, so letting go
## of the button is not a tap.
var look_hold_used := false
const ROLE_NAMES := ["Turn or strafe","Turn","Strafe","Pitch","Throttle","Camera","Off"]
static func role_names() -> Array:
	"""ROLE_NAMES in the engine's language."""
	return [EngineLanguage.translate("Turn or strafe"),EngineLanguage.translate("Turn"),EngineLanguage.translate("Strafe"),EngineLanguage.translate("Pitch"),EngineLanguage.translate("Throttle"),EngineLanguage.translate("Camera"),EngineLanguage.translate("Off")]
enum Role {TURN_OR_STRAFE,TURN,STRAFE,PITCH,THROTTLE,CAMERA,OFF}
const DEFAULT_ROLES := [Role.TURN_OR_STRAFE,Role.PITCH,Role.TURN,Role.PITCH]
const AXIS_KEYS := ["pad_left_x","pad_left_y","pad_right_x","pad_right_y"]
const AXIS_NAMES := ["Left stick left/right","Left stick up/down","Right stick left/right","Right stick up/down"]
static func axis_names() -> Array:
	"""AXIS_NAMES in the engine's language."""
	return [EngineLanguage.translate("Left stick left/right"),EngineLanguage.translate("Left stick up/down"),EngineLanguage.translate("Right stick left/right"),EngineLanguage.translate("Right stick up/down")]
const LOOK_BUTTON := JOY_BUTTON_DPAD_LEFT
const ACTIONS := {JOY_BUTTON_X:"bank",JOY_BUTTON_Y:"dock",JOY_BUTTON_LEFT_SHOULDER:"autopilot",JOY_BUTTON_RIGHT_SHOULDER:"time",JOY_BUTTON_BACK:"map",JOY_BUTTON_DPAD_LEFT:"camera",JOY_BUTTON_DPAD_RIGHT:"lights"}
func reset() -> void:
	axes.clear();buttons.clear();blocked=true;look_hold_used=false
func accept(event: InputEvent) -> void:
	if event is not InputEventJoypadMotion and event is not InputEventJoypadButton:return
	if device!=event.device:
		# Ignore another controller's resting axes and button releases.
		if event is InputEventJoypadMotion and absf(event.axis_value)<deadzone:return
		if event is InputEventJoypadButton and not event.pressed:return
		reset();device=event.device
	if event is InputEventJoypadMotion:axes[event.axis]=event.axis_value
	else:
		if event.button_index==LOOK_BUTTON and event.pressed:look_hold_used=false
		buttons[event.button_index]=event.pressed
func stick(horizontal: int=JOY_AXIS_LEFT_X,vertical: int=JOY_AXIS_LEFT_Y) -> Vector2:
	var value:=Vector2(axes.get(horizontal,0.0),axes.get(vertical,0.0))
	var length:=value.length()
	if length<=deadzone:return Vector2.ZERO
	return value.normalized()*clampf((length-deadzone)/(1-deadzone),0,1)
func default_roles() -> bool:
	return roles==DEFAULT_ROLES
func looking() -> bool:
	"""D-pad left is held: the right stick turns the camera."""
	return buttons.get(LOOK_BUTTON,false)
func snapshot() -> Dictionary:
	var left:=stick();var right:=stick(JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y)
	# Stick down is positive; pitch and throttle read up as positive.
	var values: Array=[left.x,-left.y,right.x,-right.y]
	var result := {"horizontal":0.0,"yaw":0.0,"strafe":0.0,"pitch":0.0,"throttle":0,"camera":Vector2.ZERO}
	var throttle := 0.0
	for index in 4:
		var value: float=values[index];var vertical: bool=index%2==1
		var role: int=roles[index]
		if index>=2 and looking():
			role=Role.CAMERA
			if value!=0.0:look_hold_used=true
		match role:
			Role.TURN_OR_STRAFE:result.horizontal+=value
			Role.TURN:result.yaw+=value
			Role.STRAFE:result.strafe+=value
			Role.PITCH:result.pitch+=value*(-1 if invert else 1)
			Role.THROTTLE:throttle+=value
			# Up lifts the camera, as moving the mouse up does in free look.
			Role.CAMERA:result.camera+=Vector2(0,-value) if vertical else Vector2(value,0)
	for key in ["horizontal","yaw","strafe","pitch"]:result[key]=clampf(result[key],-1,1)
	var fire: bool=buttons.get(JOY_BUTTON_A,false)
	var guns: bool=axes.get(JOY_AXIS_TRIGGER_RIGHT,0.0)>0.25
	var hook: bool=axes.get(JOY_AXIS_TRIGGER_LEFT,0.0)>0.25
	if blocked:
		if not fire and not guns and not hook:blocked=false
		fire=false;guns=false;hook=false
	# A stick on the throttle steps it as the D-pad does, once pushed past half.
	result.throttle=int(buttons.get(JOY_BUTTON_DPAD_UP,false))-int(buttons.get(JOY_BUTTON_DPAD_DOWN,false))+(1 if throttle>.5 else -1 if throttle<-.5 else 0)
	result.merge({"fire":fire,"guns":guns,"hook":hook,"boost":buttons.get(JOY_BUTTON_LEFT_STICK,false)})
	return result
static func read_roles(config: ConfigFile) -> Array:
	var chosen: Array=[]
	for index in 4:
		var value: Variant=config.get_value("input",AXIS_KEYS[index],DEFAULT_ROLES[index])
		chosen.append(clampi(int(value),0,ROLE_NAMES.size()-1) if (value is int or (value is float and is_finite(value))) else DEFAULT_ROLES[index])
	return chosen
