extends RefCounted
## Steering by tilting the device. The reading is absolute gravity rather than
## accumulated rotation, so it cannot drift: a phone held still always reports
## the same angles, and "centre" is simply the pair of angles held at the moment
## the player asked for it.
signal notice(message: String)
## Below this the device is in free fall or the sensor is asleep; a normalised
## direction taken from it would be noise.
const REST := 1.0
const DEADBAND := 1.5
var neutral := Vector2.ZERO
var filtered := Vector2.ZERO
var calibrated := false
var callback: JavaScriptObject
var available := true
var screen_angle := NAN

func enable() -> void:
	"""Browsers only hand out motion after a permission prompt, and that prompt
	only opens from a user gesture, which is why this runs when the setting is
	switched on rather than at startup."""
	calibrated=false; filtered=Vector2.ZERO; screen_angle=NAN
	if not OS.has_feature("web"): return
	if callback==null: callback=JavaScriptBridge.create_callback(permission_result)
	JavaScriptBridge.eval("""
window.abyssalMotion = window.abyssalMotion || {x:0,y:0,z:0,angle:0,time:0};
window.abyssalEnableMotion = async function(done) {
 try {
  if (!window.DeviceMotionEvent) { done('This browser reports no motion sensor.'); return; }
  if (typeof DeviceMotionEvent.requestPermission === 'function' && await DeviceMotionEvent.requestPermission() !== 'granted') {
   done('Motion sensor permission was refused.'); return;
  }
  if (!window.abyssalMotionListening) {
   window.addEventListener('devicemotion', e => {
    const g = e.accelerationIncludingGravity;
    if (!g || ![g.x,g.y,g.z].every(Number.isFinite)) return;
    // On iPhone, window.orientation tracks the visible page even when
    // screen.orientation exists but still reports the portrait value.
    const ios = /iP(hone|ad|od)/.test(navigator.userAgent)
     || (navigator.maxTouchPoints > 1 && /Mac/.test(navigator.platform || ''));
    const legacy = Number(window.orientation);
    const modern = Number(screen.orientation ? screen.orientation.angle : NaN);
    const angle = ios && Number.isFinite(legacy) ? legacy
     : Number.isFinite(modern) ? modern : Number.isFinite(legacy) ? legacy : 0;
    window.abyssalMotion = {
     x:g.x, y:g.y, z:g.z, angle,
     time: performance.now()
    };
   });
   window.abyssalMotionListening = true;
  }
  done('');
 } catch (_) { done('Motion sensors could not be started.'); }
};
""",true)
	JavaScriptBridge.get_interface("window").abyssalEnableMotion(callback)

func permission_result(args: Array) -> void:
	var message := str(args[0])
	available=message.is_empty()
	if not available: notice.emit(message)

func reading() -> Vector3:
	if OS.has_feature("web"):
		# A stale sample is worse than none: a sensor that stopped reporting would
		# otherwise hold the submarine in whatever turn it last saw.
		var raw: Variant = JavaScriptBridge.eval("window.abyssalMotion && performance.now()-window.abyssalMotion.time < 1000 ? JSON.stringify([window.abyssalMotion.x,window.abyssalMotion.y,window.abyssalMotion.z,window.abyssalMotion.angle]) : null")
		if raw is String:
			var values: Variant = JSON.parse_string(str(raw))
			if values is Array and values.size()==4 and values.all(func(value):return value is float or value is int):
				var acceleration := Vector3(values[0],values[1],values[2])
				var angle := float(values[3])
				if acceleration.is_finite() and is_finite(angle):
					if is_finite(screen_angle) and absf(wrapf(angle-screen_angle,-180.0,180.0))>1.0:
						calibrated=false;filtered=Vector2.ZERO
					screen_angle=angle
					return screen_gravity(acceleration,angle)
		# Safari suspends sensor events with the page. Centre on the next fresh
		# sample so resuming in a different grip cannot kick the helm sideways.
		calibrated=false;filtered=Vector2.ZERO
		return Vector3.ZERO
	if OS.has_feature("android") or OS.has_feature("ios"):
		var gravity := Input.get_gravity()
		return gravity if gravity.length_squared()>REST else Input.get_accelerometer()
	return Vector3.ZERO

static func screen_gravity(acceleration: Vector3, angle_degrees: float) -> Vector3:
	# DeviceMotion's accelerationIncludingGravity is proper acceleration,
	# opposite physical gravity, in portrait device axes. Rotate it into the
	# visible screen before turning it into the gravity vector used by angles().
	var angle := deg_to_rad(angle_degrees)
	var c := cos(angle);var s := sin(angle)
	return Vector3(-acceleration.x*c+acceleration.y*s,
		-acceleration.x*s-acceleration.y*c,-acceleration.z)

static func angles(gravity: Vector3) -> Vector2:
	"""Screen-space gravity points down at rest, so the vertical term reads zero
	there. Rolling the device left tips screen-down toward -X, which has to read
	as steering left, matching a stick pushed left."""
	var unit := gravity.normalized()
	return Vector2(atan2(unit.x,sqrt(unit.y*unit.y+unit.z*unit.z)),atan2(unit.z,-unit.y))

func calibrate() -> bool:
	var gravity := reading()
	if gravity.length_squared()<REST or not gravity.is_finite():
		notice.emit("No motion sensor reading. Tilt steering needs a device with motion sensors, and permission to use them.")
		return false
	neutral=angles(gravity); calibrated=true; filtered=Vector2.ZERO
	return true

func sample(gravity: Vector3, seconds: float, sensitivity: float) -> Vector2:
	"""The first reading after switching on becomes the centre, so a player who
	never calibrates still steers from however they happened to be holding it."""
	if not gravity.is_finite() or gravity.length_squared()<REST:
		filtered=Vector2.ZERO
		return filtered
	var current := angles(gravity)
	if not calibrated: neutral=current; calibrated=true
	var offset := Vector2(wrapf(current.x-neutral.x,-PI,PI),wrapf(current.y-neutral.y,-PI,PI))
	# A tilt of this much is full deflection. More sensitivity means less tilt.
	var full := deg_to_rad(lerpf(40,10,clampf(sensitivity,0,1)))
	var target := Vector2.ZERO
	for axis in 2:
		# The deadband keeps a hand that is merely not perfectly still from
		# steering, and is subtracted rather than clipped so the response leaves
		# it smoothly instead of stepping.
		target[axis]=signf(offset[axis])*clampf((absf(offset[axis])-deg_to_rad(DEADBAND))/full,0,1)
	filtered=filtered.lerp(target,1.0-exp(-maxf(0,seconds)/.07))
	return filtered

func look(seconds: float, sensitivity: float) -> Vector2:
	return sample(reading(),seconds,sensitivity)
