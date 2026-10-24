extends RefCounted
## NVIDIA DLSS and DLSS Frame Generation. Stock Godot has neither: they come
## only with the Windows engine build that carries NVIDIA's Streamline
## integration, once Direct3D 12 with NVIDIA DLSS is chosen in Settings
## (renderer_choice.gd). Everywhere else every query here reports unavailable
## and the game keeps its own upscalers. Availability is what the driver and
## NVIDIA's runtime report; a saved choice never assumes it.

## Streamline parameter 0: NVIDIA Reflex, which frame generation needs.
const REFLEX_MODE := 0
## DLSS takes any 3D size from half the output up (Performance to DLAA), but
## Ultra performance only an exact third, which Godot's rounding of the 3D
## size cannot promise. A share that finds no DLSS mode turns DLSS off for
## the rest of the session, so DLSS draws at least half.
const LOWEST_SCALE := 0.5

## Whether frame generation was last asked of the runtime.
static var generating := false

static func bridge() -> Object:
	return Engine.get_singleton("Streamline") if Engine.has_singleton("Streamline") else null

static func status() -> Dictionary:
	var native := bridge()
	if native==null or not native.has_method("get_status"): return {}
	return native.call("get_status")

static func dlss_mode() -> int:
	"""Viewport.SCALING_3D_MODE_DLSS on an engine that has it, else -1."""
	if not ClassDB.class_has_integer_constant("Viewport","SCALING_3D_MODE_DLSS"): return -1
	return ClassDB.class_get_integer_constant("Viewport","SCALING_3D_MODE_DLSS")

static func dlss() -> bool:
	"""DLSS can upscale here: the engine has it, the Forward+ renderer runs on
	Direct3D 12 and NVIDIA's runtime loaded on a supported GPU."""
	if dlss_mode()<0 or RenderingServer.get_current_rendering_method()!="forward_plus": return false
	return bool(status().get("sr_supported",false))

static func frame_generation() -> bool:
	"""DLSS Frame Generation can run: an RTX 40-series or newer GPU, a recent
	driver and hardware-accelerated GPU scheduling, with Reflex."""
	if not dlss(): return false
	var native := status()
	return bool(native.get("fg_supported",false)) and bool(native.get("reflex_supported",false))

static func generate(on: bool) -> bool:
	"""Switches NVIDIA Reflex, which DLSS Frame Generation needs, with it when
	that changes, and returns whether frames are generated."""
	on=on and frame_generation()
	if on!=generating:
		generating=on
		# The bridge switches Reflex at the next frame boundary.
		bridge().call("set_parameter",REFLEX_MODE,1.0 if on else 0.0)
	return on

static func failed(viewport: Viewport) -> bool:
	"""DLSS was in use and NVIDIA's runtime has since stopped it: the view
	needs its ordinary upscaler again."""
	var mode := dlss_mode()
	return mode>=0 and int(viewport.scaling_3d_mode)==mode and not dlss()
