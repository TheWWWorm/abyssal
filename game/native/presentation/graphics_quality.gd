extends RefCounted
## Graphics presets and the render settings they own. The title, the station
## and the dive read the same values and apply them to the one viewport, so a
## preset chosen or detected anywhere draws the same picture everywhere.
##
## Measured cost near a station (median GPU time; see the release notes):
## station work-lamp shadows are the largest single item on the phone and web
## renderers, then volumetric light and ambient occlusion (Vulkan only) and
## multisampling. The ocean effects and the headlight beams cost little, so
## presets leave those as the player set them. Resolution is the player's
## own choice too: presets never change it.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")

const PRESETS := ["Classic","Low","Medium","High","Very high"]
static func preset_names() -> Array:
	"""PRESETS in the engine's language."""
	return [EngineLanguage.translate("Classic"),EngineLanguage.translate("Low"),EngineLanguage.translate("Medium"),EngineLanguage.translate("High"),EngineLanguage.translate("Very high")]
const CLASSIC := 0
const LOW := 1
const MEDIUM := 2
const HIGH := 3
const VERY_HIGH := 4
const CUSTOM := 5
## Display resolution: the height the 3D view is drawn for, 0 for the
## screen's own. The interface is always drawn at the screen's resolution.
const HEIGHTS := [720,900,1080,1440,2160]
## 3D resolution, in percent of the display resolution.
const SCALES := [100,90,80,75,67,50]
const MSAA := ["Off","2×","4×"]
const SHADOWS := ["Off","Low","Medium","High"]
static func msaa_names() -> Array:
	"""MSAA in the engine's language."""
	return [EngineLanguage.translate("Off"),"2×","4×"]
static func shadow_names() -> Array:
	"""SHADOWS in the engine's language."""
	return [EngineLanguage.translate("Off"),EngineLanguage.translate("Low"),EngineLanguage.translate("Medium"),EngineLanguage.translate("High")]
## What each preset from Low up sets; Classic is the original lighting and
## leaves the rest alone.
const VALUES := {
	"msaa":[0,0,1,2],
	"shadows":[0,1,2,3],
	"detail":[false,true,true,true],
	"volumetric":[false,false,true,true],
}
const HEADLIGHT_LOW := 0.2
const HEADLIGHT_HIGH := 1.0

static func handheld() -> bool:
	"""Phones and browsers share memory with the GPU; their shadow maps stay smaller."""
	return OS.has_feature("mobile") or OS.has_feature("web")

static func integer(config: ConfigFile, section: String, key: String, fallback: int, highest: int) -> int:
	var value: Variant=config.get_value(section,key,fallback)
	if value is not int and value is not float: return fallback
	if value is float and not is_finite(value): return fallback
	return clampi(int(value),0,highest)

static func default_msaa() -> int:
	return clampi(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d",0)),0,2)

static func read(config: ConfigFile) -> Dictionary:
	# The earlier single 3D resolution (1080p, 1440p, native) became the
	# display resolution, drawn at 100%.
	var height := 0
	if config.has_section_key("view","resolution_height"): height=integer(config,"view","resolution_height",0,99999)
	elif config.has_section_key("view","resolution_v5"): height=[1080,1440,0][integer(config,"view","resolution_v5",2,2)]
	if height!=0 and not height in HEIGHTS: height=0
	var scale := integer(config,"view","render_scale",100,100)
	return {
		"modern":bool(config.get_value("graphics","modern",config.get_value("graphics","materials",true))),
		"height":height,
		"scale":scale if scale in SCALES else 100,
		"msaa":integer(config,"view","msaa",default_msaa(),2),
		"taa":bool(config.get_value("view","temporal_aa",false)),
		"shadows":integer(config,"graphics","shadows",3,3),
		"volumetric":bool(config.get_value("graphics","volumetric",true)),
		"detail":bool(config.get_value("graphics","detail",true)),
	}

static func headlight_strength(config: ConfigFile) -> float:
	var value: Variant=config.get_value("graphics","headlight_strength",HEADLIGHT_HIGH)
	if (value is not float and value is not int) or not is_finite(float(value)): return HEADLIGHT_HIGH
	return clampf(float(value),HEADLIGHT_LOW,HEADLIGHT_HIGH)

static func has_preset(config: ConfigFile) -> bool:
	return config.has_section_key("graphics","preset")

static func current(config: ConfigFile) -> int:
	"""The preset the settings still match, or Custom once any of them moved."""
	var quality := read(config)
	if not quality.modern: return CLASSIC
	if quality.taa: return CUSTOM
	for preset in range(LOW,VERY_HIGH+1):
		var same := true
		for key in VALUES:
			if quality[key]!=VALUES[key][preset-LOW]: same=false;break
		if same: return preset
	return CUSTOM

static func write(config: ConfigFile, preset: int) -> void:
	config.set_value("graphics","preset",PRESETS[clampi(preset,0,VERY_HIGH)].to_lower().replace(" ","_"))
	config.set_value("graphics","modern",preset!=CLASSIC)
	if preset==CLASSIC: return
	config.set_value("view","msaa",VALUES.msaa[preset-LOW])
	config.set_value("view","temporal_aa",false)
	config.set_value("graphics","shadows",VALUES.shadows[preset-LOW])
	config.set_value("graphics","detail",VALUES.detail[preset-LOW])
	config.set_value("graphics","volumetric",VALUES.volumetric[preset-LOW])

static func preset_quality(preset: int) -> Dictionary:
	var config := ConfigFile.new();write(config,preset);return read(config)

## The settings a preset owns; changing one by hand leaves the preset Custom.
const OWNED := [["graphics","modern"],["graphics","shadows"],["graphics","volumetric"],["graphics","detail"],["view","msaa"],["view","temporal_aa"]]

## Raised when detection measures something new; an older recommendation is
## measured again. 2: the station close up, with room for the dive's own work.
const DETECTION_VERSION := 2

static func measured(config: ConfigFile) -> bool:
	"""Whether this profile has a recommendation from the current detection."""
	return recommended(config)>=0 and integer(config,"graphics","detection",1,99)>=DETECTION_VERSION

static func following_recommendation(config: ConfigFile) -> bool:
	"""The preset in use is the one detection chose, untouched since."""
	var best := recommended(config)
	return best>=0 and has_preset(config) and str(config.get_value("graphics","preset",""))==PRESETS[best].to_lower().replace(" ","_") and current(config)==best

static func recommended(config: ConfigFile) -> int:
	"""The preset measured for this device, or -1."""
	var value: Variant=config.get_value("graphics","recommended",-1)
	return int(value) if (value is int or value is float) and int(value)>=LOW and int(value)<=VERY_HIGH else -1

static func heights_for(screen_height: int) -> Array:
	"""Display resolutions below the screen's own, which comes first."""
	var choices: Array=[0]
	for height in HEIGHTS:
		if height<screen_height: choices.append(height)
	return choices

static func height_name(height: int) -> String:
	return EngineLanguage.translate("Native") if height==0 else "%dp"%height

static func mark_chosen(config: ConfigFile, section: String, key: String) -> void:
	"""A hand-made change counts as a choice, so first-start detection does
	not replace it later."""
	if [section,key] in OWNED and not has_preset(config):config.set_value("graphics","preset","custom")

static func render_scale(quality: Dictionary, pixels: Vector2i) -> float:
	"""The display resolution relative to the window, times the 3D percentage.
	Detection draws more pixels than that (margin), as headroom for what the
	dive draws and runs beyond the station."""
	var display := 1.0 if quality.height<=0 else minf(1.0,float(quality.height)/maxf(1,pixels.y))
	return clampf(display*quality.scale/100.0,0.25,1.0)*float(quality.get("margin",1.0))

static func apply_viewport(viewport: Viewport, quality: Dictionary, pixels: Vector2i) -> void:
	"""Resolution, antialiasing and shadow-map sizes for the 3D view."""
	var forward: bool=RenderingServer.get_current_rendering_method()=="forward_plus"
	viewport.scaling_3d_scale=render_scale(quality,pixels)
	# FSR only upscales; detection's margin draws above the window's size.
	viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR if forward and viewport.scaling_3d_scale<1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.use_taa=quality.modern and quality.taa and forward
	var msaa: int=[Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][clampi(quality.msaa,0,2)]
	if viewport.msaa_3d!=msaa: viewport.msaa_3d=msaa
	var level: int=quality.shadows if quality.modern else 3
	var small := handheld()
	var atlas: int=([1024,2048,2048,4096] if small else [1024,2048,4096,8192])[level]
	if viewport.positional_shadow_atlas_size!=atlas: viewport.positional_shadow_atlas_size=atlas
	RenderingServer.directional_shadow_atlas_set_size(([1024,1024,1024,2048] if small else [1024,1024,2048,4096])[level],false)
	var filter: int=[RenderingServer.SHADOW_QUALITY_HARD,RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,RenderingServer.SHADOW_QUALITY_SOFT_LOW][level]
	RenderingServer.positional_soft_shadow_filter_set_quality(filter)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)

## Station lights by shadow level. A shadowed lamp is not a fixed cost: the
## Compatibility renderer (browsers, phones) draws every object in its reach
## again for it, and near a station that is most of the screen once per
## lamp. So only the lamps nearest the camera cast shadows, as many as the
## level allows (world_view.gd picks them); the rest light unshadowed. On
## Vulkan, below High the work lamps use two hemispheres instead of six cube
## faces, about half the cost, with small leaks close to a lamp. The
## Compatibility renderer has no hemisphere shadows.
static func compatibility() -> bool:
	return RenderingServer.get_current_rendering_method()=="gl_compatibility"

static func shadow_budget(level: int) -> Vector2i:
	"""How many work lamps (x) and sprite lamps (y) may cast shadows at once."""
	level=clampi(level,0,3)
	if compatibility(): return [Vector2i(0,0),Vector2i(1,0),Vector2i(2,2),Vector2i(4,4)][level]
	return [Vector2i(0,0),Vector2i(4,0),Vector2i(8,4),Vector2i(14,8)][level]

## Station lamps take their shadows from the station alone (StationShadow is
## on this render layer too). A caster that moves in a lamp's reach - the
## submarine, a fish - makes it draw all six faces of its shadow again every
## frame, for every caster; with only the station, the shadow is drawn once
## and kept. The submarine keeps its shadows from the headlights and the sun.
const STATION_CASTER_LAYER := 1<<10

static func work_lamp_shadow(light: OmniLight3D, level: int) -> void:
	light.shadow_caster_mask=STATION_CASTER_LAYER
	light.omni_shadow_mode=OmniLight3D.SHADOW_CUBE if level>=3 or compatibility() else OmniLight3D.SHADOW_DUAL_PARABOLOID

static func sprite_lamp_shadow(light: OmniLight3D, wanted: bool, level: int, budgeted: bool=false) -> void:
	"""Outside a budgeted view (the station catalogue) the level decides alone."""
	light.shadow_enabled=wanted and level>=2 and not budgeted
	light.shadow_caster_mask=STATION_CASTER_LAYER
	light.omni_shadow_mode=OmniLight3D.SHADOW_CUBE if level>=3 or compatibility() else OmniLight3D.SHADOW_DUAL_PARABOLOID
