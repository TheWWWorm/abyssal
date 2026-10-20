extends RefCounted
## AMD FSR 3.1 and FSR 4 upscaling and frame generation from AMD's FidelityFX
## SDK. Stock Godot has neither: they come only with the Windows engine
## build that carries the FidelityFX integration, once Direct3D 12 is chosen
## in Settings (renderer_choice.gd). Everywhere else every query here reports unavailable and
## the game keeps its own upscalers. Availability is what AMD's runtime
## reports for this GPU and driver; a saved choice never assumes it. FSR 4
## needs a Radeon RX 7000 or newer, FSR 3.1 runs on other recent GPUs too.

## The integration was qualified from Native AA to Performance (half the
## output size), so the SDK upscalers draw at least half.
const LOWEST_SCALE := 0.5

## The upscaler version last selected, and the frame-generation version
## last asked of the runtime; 0 is off.
static var selected := 0
static var generating := 0

static func bridge() -> Object:
	return Engine.get_singleton("FidelityFX") if Engine.has_singleton("FidelityFX") else null

static func status() -> Dictionary:
	var native := bridge()
	if native==null or not native.has_method("get_status"): return {}
	return native.call("get_status")

static func mode() -> int:
	"""Viewport.SCALING_3D_MODE_FSR_SDK on an engine that has it, else -1."""
	if not ClassDB.class_has_integer_constant("Viewport","SCALING_3D_MODE_FSR_SDK"): return -1
	return ClassDB.class_get_integer_constant("Viewport","SCALING_3D_MODE_FSR_SDK")

static func upscaler(version: int) -> bool:
	"""FSR <version> (3 or 4) can upscale here: the engine has it, the
	Forward+ renderer runs on Direct3D 12 and AMD's runtime supports it."""
	if mode()<0 or RenderingServer.get_current_rendering_method()!="forward_plus": return false
	return bool(status().get("sr%d_supported"%version,false))

static func frame_generation(version: int) -> int:
	"""The frame generation to pair with FSR <version> upscaling: the same
	version where it runs, else FSR 3.1's, else 0. FSR 4's needs Windows 11
	and a Radeon RX 9000 or newer."""
	if not upscaler(version): return 0
	var native := status()
	for candidate in ([4,3] if version==4 else [3]):
		if bool(native.get("fg%d_supported"%candidate,false)): return candidate
	return 0

static func select(version: int) -> void:
	"""Picks the upscaler the FSR SDK mode runs, before the view uses it."""
	selected=version
	bridge().call("set_upscaler_version",version)

static func generate(version: int) -> bool:
	"""Asks the runtime for frame generation of <version> (0 stops it) when
	that changes, and returns whether it runs."""
	if bridge()==null: return false
	if version!=generating:
		generating=version
		bridge().call("set_frame_generation_version",version)
	return version>0

static func failed(viewport: Viewport) -> bool:
	"""The FSR SDK upscaler in use has since stopped: the view needs its
	ordinary upscaler again."""
	var sdk := mode()
	return sdk>=0 and int(viewport.scaling_3d_mode)==sdk and not upscaler(selected)
