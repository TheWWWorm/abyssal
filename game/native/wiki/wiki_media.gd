extends VBoxContainer
## The picture beside a reference page: a vessel or creature turning in its
## own showroom, the imported pixel art enlarged without blurring, a pilot's
## portrait, or the station chart. A model can be turned by dragging it.
## Without a renderer (a headless check) a model falls back to its image.
signal followed(key: String)

const StationIcon = preload("res://native/presentation/station_icon.gd")
const ShipPreview = preload("res://native/presentation/ship_preview.gd")
const Model = preload("res://native/presentation/model.gd")
const WikiChart = preload("res://native/wiki/wiki_chart.gd")
const StationPreview = preload("res://native/presentation/station_preview.gd")

var frame: PanelContainer
var caption: Label
## What is shown now: "model", "image", "portrait", "chart", "glyph" or "".
var shown := ""

## Builds the picture for a page. Returns false when there is nothing to show.
func show_media(descriptor: Dictionary, catalog, content, art, palette: Dictionary, options: Dictionary) -> bool:
	for child in get_children(): remove_child(child); child.queue_free()
	frame = PanelContainer.new(); caption = Label.new(); shown = ""
	add_theme_constant_override("separation", 6)
	var style := StyleBoxFlat.new(); style.bg_color = Color(palette.panel, 0.5); style.border_color = Color(palette.edge, 0.6)
	style.set_border_width_all(1); style.set_corner_radius_all(4); style.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", style)
	# A steady landscape-ish shape: a frame stretched down the whole column
	# leaves a model small in the middle of empty water.
	if not resized.is_connected(_reshape): resized.connect(_reshape, CONNECT_DEFERRED)
	_reshape()
	frame.clip_contents = true; add_child(frame)
	caption.add_theme_color_override("font_color", palette.dim); caption.add_theme_font_size_override("font_size", 13)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption)
	var renders := DisplayServer.get_name() != "headless" and content != null and content.get("registry") != null
	if descriptor.has("model") and renders and has_model(content, int(descriptor.model)):
		var preview = ShipPreview.new(); frame.add_child(preview)
		preview.configure(content, int(descriptor.model), bool(options.get("modern", true)), options.get("library"))
		preview.custom_minimum_size = Vector2(200, 180)
		# Creatures are framed by their body, which leaves fins and tails
		# outside the showroom's ship framing.
		if int(descriptor.model) > 11: preview.radius *= 1.6; preview.creature = true
		# The showroom frames for a wide card; a tall frame narrows the view
		# across, so the camera stands further back in proportion.
		var base: float = preview.radius
		var reframe := func():
			if preview.size.x > 0: preview.radius = base * maxf(1.0, preview.size.y / preview.size.x * 1.15)
		preview.resized.connect(reframe)
		if preview.vessel != null and int(descriptor.get("faction", 0)) > 0:
			preview.vessel.apply_range(Model.ship_animation_range(int(descriptor.model), int(descriptor.faction)))
		caption.text = tr("Drag to turn"); shown = "model"
		# The game's own sprite of it, as the shop and the hold show it.
		var sprite: Texture2D = art.image(descriptor.image) if art != null and descriptor.has("image") else null
		if sprite != null:
			var picture := TextureRect.new(); picture.texture = sprite
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = sprite.get_size() * clampf(floorf(96.0 / maxf(1.0, sprite.get_height())), 1.0, 3.0)
			picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			add_child(picture); move_child(picture, caption.get_index())
		return true
	if descriptor.has("station") and renders:
		var station = StationPreview.new(); frame.add_child(station)
		station.configure_content(content, int(descriptor.station), bool(descriptor.get("colonist", true)), options.get("library"), bool(options.get("modern", true)))
		station.custom_minimum_size = Vector2(200, 180)
		station.sweep_shown = 1.0
		caption.text = tr("Drag to turn"); shown = "station"
		if descriptor.has("chart"):
			# The chart stays below, smaller, to show where the station lies.
			var map := PanelContainer.new(); map.add_theme_stylebox_override("panel", frame.get_theme_stylebox("panel"))
			map.custom_minimum_size.y = 190; add_child(map)
			var chart = WikiChart.new(); chart.configure(catalog, descriptor.chart, palette); map.add_child(chart)
			chart.followed.connect(func(key): followed.emit(key))
		return true
	if descriptor.has("chart"):
		var chart = WikiChart.new(); chart.configure(catalog, descriptor.chart, palette); frame.add_child(chart)
		chart.followed.connect(func(key): followed.emit(key))
		caption.text = catalog.chart_caption(int(descriptor.chart.get("as_of", 0)))
		shown = "chart"
		return true
	var texture: Texture2D = null
	if art != null:
		if descriptor.has("portrait"): texture = art.portrait(descriptor.portrait)
		elif descriptor.has("image"): texture = art.image(descriptor.image)
	if texture != null:
		var picture := TextureRect.new(); picture.texture = texture
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; picture.custom_minimum_size = Vector2(160, 120)
		frame.add_child(picture); caption.hide(); shown = "portrait" if descriptor.has("portrait") else "image"
		return true
	if descriptor.has("glyph"):
		var glyph = StationIcon.new(str(descriptor.glyph), palette.accent, 96)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; frame.add_child(glyph)
		caption.hide(); shown = "glyph"
		return true
	return false

func _reshape() -> void:
	if frame == null or not is_instance_valid(frame): return
	# Above the article the reader gives the picture a fixed band to fill;
	# beside it, the column is tall and the frame takes the shape instead.
	# Only a real change is applied: each one lays the column out again.
	if not is_visible_in_tree() or size.x <= 0: return
	var band := custom_minimum_size.y > 0
	var flags := Control.SIZE_EXPAND_FILL if band else Control.SIZE_FILL
	var height := 0.0 if band else roundf(clampf(size.x * 0.82, 180.0, 460.0))
	if frame.size_flags_vertical != flags: frame.size_flags_vertical = flags
	if not is_equal_approx(frame.custom_minimum_size.y, height): frame.custom_minimum_size.y = height

static func has_model(content, id: int) -> bool:
	for entry in content.registry:
		if int(entry.id) == id: return true
	return false

## A small fixed-size picture for a list row.
static func thumbnail(descriptor: Dictionary, art, palette: Dictionary, extent := Vector2(56, 34)) -> Control:
	var texture: Texture2D = null
	if art != null:
		if descriptor.has("portrait"): texture = art.portrait(descriptor.portrait)
		elif descriptor.has("image"): texture = art.image(descriptor.image)
	if texture != null:
		var picture := TextureRect.new(); picture.texture = texture
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; picture.custom_minimum_size = extent
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return picture
	var glyph = StationIcon.new(str(descriptor.get("glyph", "book")), palette.accent, extent.y * 0.8)
	glyph.custom_minimum_size = extent
	return glyph
