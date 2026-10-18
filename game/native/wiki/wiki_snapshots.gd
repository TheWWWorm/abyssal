extends Control
## Photographs the reference's 3D pages for the web page export: each ship,
## creature and station is set up in the same showroom the reader uses, off
## screen, and its picture is saved once it has been drawn. Needs a renderer;
## without one (a headless run) nothing is photographed and the export keeps
## the imported pixel art instead.
signal progressed(done: int, total: int)

const ShipPreview = preload("res://native/presentation/ship_preview.gd")
const StationPreview = preload("res://native/presentation/station_preview.gd")
const Model = preload("res://native/presentation/model.gd")
const PICTURE := Vector2i(640, 440)
## Frames a showroom is given to build, frame and draw before its picture is taken.
const SETTLE := 8

static func available() -> bool: return DisplayServer.get_name() != "headless"

## Pages with a model or a station, and what to set up for each.
static func subjects(catalog) -> Dictionary:
	var found := {}
	for key: String in catalog.ordered:
		var shown: Dictionary = catalog.media(key)
		if shown.has("model") or shown.has("station"): found[key] = shown
	return found

## Saves directory/images/render-<key>.png for every subject and returns
## {key: path inside the site}.
func render(catalog, content, directory: String, options := {}) -> Dictionary:
	var written := {}
	if not available() or content == null: return written
	DirAccess.make_dir_recursive_absolute(directory.path_join("images"))
	# Off screen but in the tree, so the showrooms run and draw.
	position = Vector2(-PICTURE.x - 100, 0); size = PICTURE
	var subjects_ := subjects(catalog)
	# The water's haze takes its colour from the dive's ocean map, which is
	# not drawn here; without it distant parts fade to white. Pictures are
	# taken in clear water; afterwards the project's own value returns until
	# a dive sets the water's again.
	RenderingServer.global_shader_parameter_set("ocean_haze_gain", 0.0)
	var done := 0
	for key: String in subjects_:
		var shown: Dictionary = subjects_[key]
		var stage: SubViewportContainer
		if shown.has("station"):
			stage = StationPreview.new(); stage.sweep_shown = 1.0; add_child(stage)
			stage.configure_content(content, int(shown.station), bool(shown.get("colonist", true)), options.get("library"), bool(options.get("modern", true)))
		else:
			stage = ShipPreview.new(); add_child(stage)
			stage.configure(content, int(shown.model), bool(options.get("modern", true)), options.get("library"))
			if stage.vessel != null and int(shown.get("faction", 0)) > 0:
				stage.vessel.apply_range(Model.ship_animation_range(int(shown.model), int(shown.faction)))
			if int(shown.model) > 11: stage.make_creature(content); stage.radius *= 1.1
		stage.custom_minimum_size = Vector2(PICTURE); stage.size = Vector2(PICTURE)
		# The ocean's colour map only exists while a dive is drawn; the page
		# paints its own water behind a transparent picture instead.
		stage.stretch = false; stage.viewport.size = PICTURE; stage.viewport.transparent_bg = true
		stage.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# A station is framed once its modules are built, a few frames in.
		if stage is StationPreview:
			for frame in 120:
				if stage.fitted: break
				await get_tree().process_frame
		for frame in SETTLE: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = stage.viewport.get_texture().get_image()
		var path: String = "images/render-%s.png" % key.replace("/", "-")
		if picture != null and picture.save_png(directory.path_join(path)) == OK: written[key] = path
		remove_child(stage); stage.queue_free()
		done += 1; progressed.emit(done, subjects_.size())
	var haze = ProjectSettings.get_setting("shader_globals/ocean_haze_gain", {})
	RenderingServer.global_shader_parameter_set("ocean_haze_gain", float(haze.get("value", 1.0)) if haze is Dictionary else 1.0)
	return written
