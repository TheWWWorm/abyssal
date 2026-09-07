extends RefCounted
## Device-neutral analog steering. Only the most recently used controller owns flight.
## The right stick always aims, so the left stick is free to strafe instead of turn.
var device := -1
var axes := {}
var buttons := {}
var deadzone := 0.18
var invert := false
var blocked := false
const ACTIONS := {JOY_BUTTON_X:"bank",JOY_BUTTON_Y:"dock",JOY_BUTTON_LEFT_SHOULDER:"autopilot",JOY_BUTTON_RIGHT_SHOULDER:"time",JOY_BUTTON_BACK:"map",JOY_BUTTON_DPAD_LEFT:"camera",JOY_BUTTON_DPAD_RIGHT:"lights"}
func reset() -> void:
	axes.clear();buttons.clear();blocked=true
func accept(event: InputEvent) -> void:
	if event is not InputEventJoypadMotion and event is not InputEventJoypadButton:return
	if device!=event.device:
		# Ignore another controller's resting axes and button releases.
		if event is InputEventJoypadMotion and absf(event.axis_value)<deadzone:return
		if event is InputEventJoypadButton and not event.pressed:return
		reset();device=event.device
	if event is InputEventJoypadMotion:axes[event.axis]=event.axis_value
	else:buttons[event.button_index]=event.pressed
func stick(horizontal: int=JOY_AXIS_LEFT_X,vertical: int=JOY_AXIS_LEFT_Y) -> Vector2:
	var value:=Vector2(axes.get(horizontal,0.0),axes.get(vertical,0.0))
	var length:=value.length()
	if length<=deadzone:return Vector2.ZERO
	return value.normalized()*clampf((length-deadzone)/(1-deadzone),0,1)
func snapshot() -> Dictionary:
	var aim:=stick()*Vector2(1,1 if invert else -1)
	var look:=stick(JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y)*Vector2(1,1 if invert else -1)
	var fire: bool=buttons.get(JOY_BUTTON_A,false)
	var guns: bool=axes.get(JOY_AXIS_TRIGGER_RIGHT,0.0)>0.25
	var hook: bool=axes.get(JOY_AXIS_TRIGGER_LEFT,0.0)>0.25
	if blocked:
		if not fire and not guns and not hook:blocked=false
		fire=false;guns=false;hook=false
	return {"yaw":aim.x,"pitch":aim.y,"look":look,"fire":fire,"guns":guns,"hook":hook,"boost":buttons.get(JOY_BUTTON_LEFT_STICK,false),"throttle":int(buttons.get(JOY_BUTTON_DPAD_UP,false))-int(buttons.get(JOY_BUTTON_DPAD_DOWN,false))}
