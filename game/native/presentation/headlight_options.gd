extends RefCounted
## One presentation choice owns the lenses, surface light and visible beams.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
enum Mode { OFF, LIGHT_ONLY, LIGHT_BEAMS, CLASSIC }
const NAMES := ["Off", "Light only", "Light + beams", "Classic"]
static func names() -> Array:
	"""NAMES in the engine's language."""
	return [EngineLanguage.translate("Off"),EngineLanguage.translate("Light only"),EngineLanguage.translate("Light + beams"),EngineLanguage.translate("Classic")]
const DEFAULT := Mode.LIGHT_BEAMS

static func read(config: ConfigFile) -> int:
	var value: Variant=config.get_value("graphics","headlight_mode",-1)
	if value is int and value>=Mode.OFF and value<=Mode.CLASSIC:return value
	# Preserve the effective state of settings written before the single control.
	if not bool(config.get_value("graphics","headlights",true)):return Mode.OFF
	return Mode.LIGHT_BEAMS if bool(config.get_value("graphics","beams",true)) else Mode.LIGHT_ONLY

static func previous(config: ConfigFile) -> int:
	var fallback := Mode.LIGHT_BEAMS if bool(config.get_value("graphics","beams",true)) else Mode.LIGHT_ONLY
	var value: Variant=config.get_value("graphics","headlight_previous",fallback)
	return value if value is int and value>Mode.OFF and value<=Mode.CLASSIC else fallback

static func write(config: ConfigFile, mode: int) -> void:
	config.set_value("graphics","headlight_mode",mode)
	if mode!=Mode.OFF:config.set_value("graphics","headlight_previous",mode)
	for key in ["headlights","beams"]:
		if config.has_section_key("graphics",key):config.erase_section_key("graphics",key)

static func casts_light(mode: int) -> bool:
	return mode in [Mode.LIGHT_ONLY,Mode.LIGHT_BEAMS]
