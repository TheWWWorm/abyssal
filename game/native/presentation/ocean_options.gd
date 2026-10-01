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
	"cool_lighting":["Cool ambient light","Optional blue-green ambient and overhead lighting inspired by the promo artwork."]
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
		"cool_lighting":[EngineLanguage.translate("Cool ambient light"),EngineLanguage.translate("Optional blue-green ambient and overhead lighting inspired by the promo artwork.")]
	}

static func default_on(key: String) -> bool:
	# White/Blue is a colour choice; all effect switches start enabled.
	return key!="blue_headlights"

static func flag(config: ConfigFile, section: String, key: String) -> bool:
	var value: Variant=config.get_value(section,key,default_on(key))
	return bool(value) if value is bool or value is int else default_on(key)

static func read(config: ConfigFile) -> Dictionary:
	var choices := {}
	for key in VISUALS:choices[key]=flag(config,"graphics",key)
	return choices

static func defaults() -> Dictionary:
	return read(ConfigFile.new())
