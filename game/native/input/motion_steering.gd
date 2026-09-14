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

func enable() -> void:
	"""Browsers only hand out motion after a permission prompt, and that prompt
	only opens from a user gesture, which is why this runs when the setting is
	switched on rather than at startup."""
	calibrated=false; filtered=Vector2.ZERO
	if not OS.has_feature("web"): return
	if callback==null: callback=JavaScriptBridge.create_callback(permission_result)
	JavaScriptBridge.eval("""
window.abyssalMotion = window.abyssalMotion || {x:0,y:0,z:0,time:0};
window.abyssalEnableMotion = async function(done) {
 try {
  if (!window.DeviceMotionEvent) { done('This browser reports no motion sensor.'); return; }
  if (typeof DeviceMotionEvent.requestPermission === 'function' && await DeviceMotionEvent.requestPermission() !== 'granted') {
   done('Motion sensor permission was refused.'); return;
  }
  if (!window.abyssalMotionListening) {
   // WebKit reports accelerationIncludingGravity as gravity itself and every
   // other browser as the equal and opposite reaction, so one of the two
   // steered backwards. Normalising to gravity pointing down leaves pitch
   // alone: flipping the whole vector only shifts the pitch term by PI, and
   // that cancels against the neutral. Only left and right ever read reversed.
   const webkit = /iP(hone|ad|od)/.test(navigator.userAgent)
    || (navigator.maxTouchPoints > 1 && /Mac/.test(navigator.platform || ''));
   const down = webkit ? 1 : -1;
   window.addEventListener('devicemotion', e => {
    const g = e.accelerationIncludingGravity;
    if (!g || g.x === null || g.y === null || g.z === null) return;
    // The screen's up axis is the device's +Y at angle 0 and its +X at 90, so
    // rotating by the reported angle reads the same held any way up.
    const o = screen.orientation;
    const a = (o ? o.angle : (window.orientation || 0)) * Math.PI / 180;
    const cos = Math.cos(a), sin = Math.sin(a);
    window.abyssalMotion = {
     x: down * (g.x * cos - g.y * sin),
     y: down * (g.x * sin + g.y * cos),
     z: -down * g.z,
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
		var raw: Variant = JavaScriptBridge.eval("window.abyssalMotion && performance.now()-window.abyssalMotion.time < 1000 ? JSON.stringify([window.abyssalMotion.x,window.abyssalMotion.y,window.abyssalMotion.z]) : null")
		if raw is String:
			var values: Variant = JSON.parse_string(str(raw))
			if values is Array and values.size()==3: return Vector3(values[0],values[1],values[2])
		return Vector3.ZERO
	if OS.has_feature("android") or OS.has_feature("ios"):
		var gravity := Input.get_gravity()
		return gravity if gravity.length_squared()>REST else Input.get_accelerometer()
	return Vector3.ZERO

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
