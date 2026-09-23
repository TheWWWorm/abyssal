extends RefCounted
## Horizontal metres per atlas unit; local models and depths keep their scale.
const MIN_METERS := 400
const DEFAULT_METERS := 600
const ORIGINAL_METERS := 18850
## Saved IDs stay stable when the display order gains another option.
enum Preset { SHORT, NORMAL, HIGH, ORIGINAL, CUSTOM, MEDIUM_SHORT }
const ORDER := [Preset.SHORT,Preset.MEDIUM_SHORT,Preset.NORMAL,Preset.HIGH,Preset.ORIGINAL,Preset.CUSTOM]
const PRESETS := {Preset.SHORT:MIN_METERS,Preset.MEDIUM_SHORT:DEFAULT_METERS,Preset.NORMAL:1000,Preset.HIGH:2000,Preset.ORIGINAL:ORIGINAL_METERS}
const NAMES := {Preset.SHORT:"Short · 400 m",Preset.MEDIUM_SHORT:"Medium short · 600 m",Preset.NORMAL:"Normal · 1 km",Preset.HIGH:"High · 2 km",Preset.ORIGINAL:"Original · 18.85 km",Preset.CUSTOM:"Custom"}
var preset := Preset.MEDIUM_SHORT
var custom_meters := DEFAULT_METERS

static func valid_meters(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):return DEFAULT_METERS
	# Reject values that cannot be represented by fixed world coordinates.
	if float(value)>float(9223372036854775807)/1000000.0:return DEFAULT_METERS
	return maxi(MIN_METERS,roundi(maxf(MIN_METERS,float(value))))

func meters() -> int:
	return valid_meters(custom_meters) if preset==Preset.CUSTOM else PRESETS.get(preset,DEFAULT_METERS)

func read_config(config: ConfigFile) -> void:
	var choice: Variant=config.get_value("world","spacing_preset",Preset.MEDIUM_SHORT)
	preset=int(choice) if choice is int and NAMES.has(choice) else Preset.MEDIUM_SHORT
	custom_meters=valid_meters(config.get_value("world","custom_spacing_meters",DEFAULT_METERS))

func write_config(config: ConfigFile) -> void:
	config.set_value("world","spacing_preset",preset)
	config.set_value("world","custom_spacing_meters",valid_meters(custom_meters))
