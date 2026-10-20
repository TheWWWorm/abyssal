extends RefCounted
## Credits for the vendor graphics SDK a package includes. The exporter sets
## this flag in its copy of the project when it bundles AMD's FidelityFX
## SDK, so the credits follow the package, never the GPU or the chosen
## settings. Source runs and ordinary packages show none.

const EngineLanguage = preload("res://native/presentation/engine_language.gd")

const AMD := "abyssal/graphics_sdk/amd"
## AMD's white FSR lockups, from AMD's FSR naming and branding guidelines.
const AMD_LOGOS := ["res://ui/vendors/amd-fsr-upscaling-white.png","res://ui/vendors/amd-fsr-frame-generation-white.png"]
## The licensor's attribution is kept as written in every language.
const AMD_CREDIT := "AMD FSR Upscaling and AMD FSR Frame Generation via the AMD FidelityFX SDK. AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of Advanced Micro Devices, Inc."

static func amd() -> bool:
	return bool(ProjectSettings.get_setting(AMD,false))

static func text() -> String:
	"""The attributions for the end credits, empty for an ordinary package."""
	return AMD_CREDIT if amd() else ""

static func logos() -> Array:
	"""The vendor's marks, in a row: AMD's two FSR lockups."""
	return AMD_LOGOS.map(load) if amd() else []

static func panel(size: float=64.0) -> Control:
	"""The marks and attributions for About, or null for an ordinary package."""
	if not amd(): return null
	var box := VBoxContainer.new();box.name="GraphicsCredits";box.add_theme_constant_override("separation",8)
	var heading := Label.new();heading.text=EngineLanguage.translate("Graphics technologies");heading.add_theme_font_size_override("font_size",16)
	heading.add_theme_color_override("font_color",Color("aedbec"));box.add_child(heading)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",28);box.add_child(row)
	for picture in logos():
		# The lockups are drawn far smaller than they are made: mipmaps keep
		# their small lettering whole.
		var mark := TextureRect.new();mark.texture=picture;mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;mark.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size=Vector2(size*picture.get_width()/maxf(1.0,picture.get_height()),size);row.add_child(mark)
	var words := Label.new();words.text=text();words.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;words.custom_minimum_size.x=520
	words.add_theme_font_size_override("font_size",12);words.add_theme_color_override("font_color",Color("a2c3d3"));box.add_child(words)
	var notices := Label.new();notices.text=EngineLanguage.translate("Full licence and copyright notices are in the package's licenses folder.")
	notices.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notices.custom_minimum_size.x=520
	notices.add_theme_font_size_override("font_size",12);notices.add_theme_color_override("font_color",Color("a2c3d3"));box.add_child(notices)
	return box
