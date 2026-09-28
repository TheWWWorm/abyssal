extends SubViewport
## The water's colour in every direction, drawn into a small octahedral map
## each frame (ocean_radiance.gdshaderinc) and shared as the global
## ocean_radiance_map. The sky and the distance haze of every station, hull
## and terrain surface read it with one texture lookup; evaluating the eight
## light shafts per pixel instead was most of the cost of an empty frame on
## phones and in browsers, twice over for the sky.
const SIZE := 256
const NAME := "OceanRadianceMap"

static func ensure(tree: SceneTree) -> void:
	"""One map for the whole program, kept on the root across scene changes."""
	if tree==null or tree.root.has_node(NAME):return
	var map: SubViewport=load("res://native/presentation/ocean_radiance_map.gd").new()
	map.name=NAME
	tree.root.add_child.call_deferred(map)
	RenderingServer.global_shader_parameter_set("ocean_radiance_map",map.get_texture())

func _init() -> void:
	size=Vector2i(SIZE,SIZE)
	# Half-float: the deep water is a few thousandths and must not band.
	use_hdr_2d=true
	transparent_bg=false
	disable_3d=true
	render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var painter := ColorRect.new()
	painter.size=Vector2(SIZE,SIZE)
	var material := ShaderMaterial.new()
	material.shader=preload("res://native/presentation/ocean_radiance_map.gdshader")
	painter.material=material
	add_child(painter)
