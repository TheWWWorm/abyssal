extends RefCounted
## Shared names and defaults for the title, station and in-flight settings.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
const VISUALS := {
	"marine_snow":["Marine snow","Fine suspended particles caught by the headlights."],
	"deep_darkness":["Deep-water darkness","Less ambient light and a darker sky at depth."],
	"bioluminescence":["Bioluminescence","Disturbed glowing plankton and softly pulsing jellyfish."],
	"explosion_aftermath":["Explosion aftermath","Short flashes followed by rising bubbles and sinking fragments."],
	"regional_water":["Regional water","Gradual changes in water colour, haze, particles and currents along a route."],
	"filtered_sunlight":["Filtered sunlight","Overhead shafts and brighter openings in the upper water."],
	"cabin_lights":["Cabin lights","Amber interior light behind reflective cockpit windows."],
	"blue_headlights":["Headlight colour","White work lights or blue original-atlas light. Aquarius keeps its red lights in either mode."],
	"cool_lighting":["Cool ambient light","Optional blue-green ambient and overhead lighting inspired by the promo artwork."],
	"warm_station_lights":["Warm station lights","Amber station lamps and windows. Off: the pale cream light of the original windows."]
}

static func visuals() -> Dictionary:
	"""VISUALS with the names and descriptions in the engine's language."""
	return {
		"marine_snow":[EngineLanguage.translate("Marine snow"),EngineLanguage.translate("Fine suspended particles caught by the headlights.")],
		"deep_darkness":[EngineLanguage.translate("Deep-water darkness"),EngineLanguage.translate("Less ambient light and a darker sky at depth.")],
		"bioluminescence":[EngineLanguage.translate("Bioluminescence"),EngineLanguage.translate("Disturbed glowing plankton and softly pulsing jellyfish.")],
		"explosion_aftermath":[EngineLanguage.translate("Explosion aftermath"),EngineLanguage.translate("Short flashes followed by rising bubbles and sinking fragments.")],
		"regional_water":[EngineLanguage.translate("Regional water"),EngineLanguage.translate("Gradual changes in water colour, haze, particles and currents along a route.")],
		"filtered_sunlight":[EngineLanguage.translate("Filtered sunlight"),EngineLanguage.translate("Overhead shafts and brighter openings in the upper water.")],
		"cabin_lights":[EngineLanguage.translate("Cabin lights"),EngineLanguage.translate("Amber interior light behind reflective cockpit windows.")],
		"blue_headlights":[EngineLanguage.translate("Headlight colour"),EngineLanguage.translate("White work lights or blue original-atlas light. Aquarius keeps its red lights in either mode.")],
		"cool_lighting":[EngineLanguage.translate("Cool ambient light"),EngineLanguage.translate("Optional blue-green ambient and overhead lighting inspired by the promo artwork.")],
		"warm_station_lights":[EngineLanguage.translate("Warm station lights"),EngineLanguage.translate("Amber station lamps and windows. Off: the pale cream light of the original windows.")]
	}

## Whether stations currently use the warm lamp colours. Set from the
## warm_station_lights choice; lamps built later read it when they are made.
static var warm_station := true

static func default_on(key: String) -> bool:
	# White/Blue is a colour choice; all effect switches start enabled. The
	# warm station look is one of them: switched off, stations take the
	# original's pale cream window light.
	return key!="blue_headlights"

static func station_lamp_color(overhead: bool, warm: bool) -> Color:
	"""A station work lamp. The original stations have no lamps; their
	windows are pale cream texels (about fef8cb) lit like the rest of the
	hull, so the accurate lamp is a near-white cream. The warm amber pair is
	the alternative look."""
	if warm:return Color("ffd39a") if overhead else Color("ffbc76")
	return Color("fff3dc")

static func station_window_warmth(warm: bool) -> float:
	"""ocean_station_warmth: 0 keeps the window texels' own cream as their
	emission, 1 shifts it to amber."""
	return 1.0 if warm else 0.0

static func flag(config: ConfigFile, section: String, key: String) -> bool:
	var value: Variant=config.get_value(section,key,default_on(key))
	return bool(value) if value is bool or value is int else default_on(key)

## How much of each region's algae colour the enhanced water takes, from
## 0 (plain water) to 1 (the region's hue at full strength). The default is
## the muted tint the enhanced water was tuned for.
const WATER_COLOUR_DEFAULT := .6

static func water_colour(config: ConfigFile) -> float:
	var value: Variant=config.get_value("graphics","water_colour",WATER_COLOUR_DEFAULT)
	if (value is not float and value is not int) or not is_finite(float(value)): return WATER_COLOUR_DEFAULT
	return clampf(float(value),0.0,1.0)

static func read(config: ConfigFile) -> Dictionary:
	var choices := {}
	for key in VISUALS:choices[key]=flag(config,"graphics",key)
	return choices

static func defaults() -> Dictionary:
	return read(ConfigFile.new())
