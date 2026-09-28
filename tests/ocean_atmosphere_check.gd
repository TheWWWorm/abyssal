extends SceneTree
const Profile=preload("res://native/presentation/ocean_profile.gd")
const Wrecks=preload("res://native/presentation/wreck_effects.gd")
class ViewProbe extends Node3D:
	var modern_graphics := true
	var player_model: Node3D
	var player_occluder: StaticBody3D
	var player_clip_enabled := false
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")

func check_profiles(data: Dictionary) -> void:
	# A compatible JAR can change both station placement and the palette.
	# Use synthetic values to ensure the presentation follows those inputs.
	var fixture := {"tables":{"stations":[["A",0,0,0],["B",0,100,0]],"goods":[]},"water_palette":[[240,40,40],[40,40,240]]}
	for i in 15:fixture.tables.goods.append([i,0,1 if i==14 else 0])
	var first := Profile.sample(Vector2.ZERO,fixture)
	var second := Profile.sample(Vector2(100,0),fixture)
	expect(first.tint.x>first.tint.z and second.tint.z>second.tint.x,"Regional hues follow the imported plankton origins and palette")
	expect(first.tint.x<=1.0 and first.tint.z>=.78,"A region cannot amplify a colour channel or heavily suppress the others")
	fixture.tables.stations[0][2]=200
	expect(Profile.sample(Vector2.ZERO,fixture).tint==Vector3.ONE,"Moving a source region in the supplied data moves its tint too")
	var low := 2.0;var high := 0.0;var living := 0;var quiet := 0
	for i in 500:
		var point := Vector2(i*.20,sin(i*.12)*45+50)
		var water := Profile.sample(point,data);var neighbor := Profile.sample(point+Vector2(.001,0),data)
		expect(water==Profile.sample(point,data),"Returning to a location gives the same water")
		expect(water.tint.distance_to(neighbor.tint)<.002 and absf(water.haze-neighbor.haze)<.002,"Regional water is continuous across chart cells")
		expect(absf(water.sun-neighbor.sun)<.002 and water.sun>=.2 and water.sun<=1.0,"Sunlit openings blend continuously and remain bounded")
		expect(water.haze>=.96 and water.haze<=1.06 and water.snow>=.9 and water.snow<=1.1,"Water variation preserves bounded visibility and particle density")
		low=minf(low,water.haze);high=maxf(high,water.haze)
		var glow := Profile.bloom(Vector3(point.x*120,0,point.y*120))
		if glow>.05:living+=1
		if glow<.005:quiet+=1
	expect(high-low>.06,"Imported regions retain a restrained difference in water clarity")
	expect(Profile.sample(Vector2(50,50)).tint==Vector3.ONE,"Older caches fall back to neutral colour rather than invented green regions")
	expect(living>5 and quiet>300,"Bioluminescent patches occur occasionally rather than everywhere")
	var abyss=load("res://native/presentation/abyss.gd")
	expect(abyss.sunlight_profile(22000)>.45 and abyss.sunlight_profile(45000)<.004,"Filtered sunlight survives in middle water and disappears in the abyss")
	var last: float=abyss.sunlight_profile(0)
	for depth in range(100,60000,100):
		var next: float=abyss.sunlight_profile(depth)
		expect(next<=last and last-next<.01,"Sunlight fades smoothly with depth")
		last=next

func check_glass_mask() -> void:
	var hints=load("res://native/presentation/imported_surface.gd")
	for size in [128,256]:
		var source := Image.create(size,size,false,Image.FORMAT_RGBA8);source.fill(Color(.025,.025,.025))
		var scale: int=size/128
		source.fill_rect(Rect2i(54*scale,103*scale,scale,scale),Color(.85,.85,.85))
		var bytes := source.get_data();var map: Image=hints.derive(source)
		expect(source.get_data()==bytes,"Glass analysis preserves imported and replacement albedo")
		expect(map.get_pixel(52*scale,102*scale).a>.9,"The imported dark pane emits at original and replacement resolution")
		for point in [Vector2i(49,102),Vector2i(54,103),Vector2i(54,119),Vector2i(100,10)]:
			expect(map.get_pixelv(point*scale).a==0,"Frames, painted texels, engine grilles and faction panels do not become glass")

func check_cabins(content) -> void:
	var model_type=load("res://native/presentation/model.gd")
	var viewport := SubViewport.new();viewport.size=Vector2i(256,192);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_ACES
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=0;viewport.add_child(environment)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(camera)
	for id in 12:
		var entry: Dictionary=content.registry.filter(func(record):return int(record.id)==id)[0]
		var model=model_type.new();viewport.add_child(model);model.configure(content.root,entry)
		var mesh: MeshInstance3D=model.figure.get_node("Mesh")
		var lamps: Array=model.figure.get_meta("lamps",[])
		expect(lamps.size()>0 and lamps.size()<=2,"Hull %d has a bounded cabin light budget"%id)
		for point in lamps:
			var lamp: OmniLight3D=point.node.get_node("Light")
			expect(lamp.shadow_enabled and lamp.omni_range<=3 and lamp.light_energy<=.02 and lamp.light_volumetric_fog_energy==0,"Hull %d cabin spill stays faint, close and shadowed"%id)
			expect(model.solid_bounds().grow(5).has_point(point.node.position),"Hull %d cabin light follows its posed glazing"%id)
			point.node.hide()
		for index in mesh.mesh.get_surface_count():mesh.get_surface_override_material(index).set_shader_parameter("distance_haze",0.0)
		if DisplayServer.get_name()!="headless":
			var bounds: AABB=model.solid_bounds();var center := bounds.get_center();var span := maxf(bounds.size.length(),1.0)
			camera.size=span*.9;camera.look_at_from_position(center+Vector3(.55,.28,-1)*span*2,center)
			var glowing: float=await energy(viewport)
			var lit_pixels := viewport.get_texture().get_image()
			model.library.cabin_lights=false;model.refresh()
			for index in mesh.mesh.get_surface_count():mesh.get_surface_override_material(index).set_shader_parameter("distance_haze",0.0)
			var dark: float=await energy(viewport)
			var dark_pixels := viewport.get_texture().get_image();var largest_glow := 0.0;var readable_pixels := 0
			for y in lit_pixels.get_height():
				for x in lit_pixels.get_width():
					var glow := lit_pixels.get_pixel(x,y).r-dark_pixels.get_pixel(x,y).r
					largest_glow=maxf(largest_glow,glow)
					if glow>.08:readable_pixels+=1
			expect(largest_glow>.15 and largest_glow<.72 and readable_pixels>=8,"Hull %d has readable amber panes without overexposed glazing (peak %.3f, %d pixels)"%[id,largest_glow,readable_pixels])
			expect(glowing>dark+3,"Hull %d imported cockpit is self-lit without headlights or ambient light (%f / %f)"%[id,glowing,dark])
			expect(lamps.all(func(point):return point.node.get_node("Light").light_energy==0),"Hull %d cabin setting also switches off the physical spill"%id)
			model.library.cabin_lights=true;model.refresh()
			if id==0 and not lamps.is_empty():
				mesh.hide();var lamp: OmniLight3D=lamps[0].node.get_node("Light");lamps[0].node.show()
				var card := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(2,2,.1);card.mesh=box
				var paint := StandardMaterial3D.new();paint.albedo_color=Color(.7,.7,.7);paint.roughness=1;card.material_override=paint;viewport.add_child(card)
				card.position=lamp.global_position+Vector3(0,0,-.6);camera.size=4;camera.look_at_from_position(lamp.global_position+Vector3(1,1,2),card.position)
				var spill: float=await energy(viewport);lamp.light_energy=0
				var unlit: float=await energy(viewport)
				expect(spill>unlit+10,"Cabin lighting illuminates a separate nearby surface, not only the window material")
				card.queue_free();await process_frame
		model.queue_free();await process_frame
	# Classic keeps its original dark glass and original additive lamp sprites.
	var classic=model_type.new();classic.modern_graphics=false;viewport.add_child(classic)
	classic.configure(content.root,content.registry.filter(func(record):return int(record.id)==0)[0])
	expect(classic.figure.get_meta("lamps",[]).all(func(point):return not point.lamp.has("energy")),"Classic hulls do not receive cabin spill lights")
	viewport.queue_free();await process_frame

func check_frozen_water(world) -> void:
	var scene := Node3D.new();root.add_child(scene)
	var camera := Camera3D.new();scene.add_child(camera)
	var view := ViewProbe.new();scene.add_child(view)
	var abyss=load("res://native/presentation/abyss.gd").new();abyss.camera=camera;abyss.world=world;abyss.view=view;scene.add_child(abyss);abyss.set_process(false)
	await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	abyss._process(.25)
	var time: float=abyss.ambient_clock;var drift: Vector3=abyss.drift_offset
	view.process_mode=Node.PROCESS_MODE_DISABLED
	for i in 20:abyss._process(.25)
	expect(abyss.ambient_clock==time and abyss.drift_offset==drift,"Action freeze holds marine snow, currents and bioluminescence still")
	view.process_mode=Node.PROCESS_MODE_INHERIT
	for i in 50:
		world.region.player.pose.origin[0]+=500;abyss._process(.25)
	expect(abyss.luminous_trail.size()==10 and abyss.luminous_strength.size()==10,"The luminous wake has a fixed history budget")
	scene.queue_free()
	await process_frame

func check_aftermath(region) -> void:
	var wrecks := Wrecks.new();root.add_child(wrecks)
	region.visual_events.clear();region.elapsed_ms=0
	region.visual_event({"kind":"explosion","position":[0,0,0],"creature":false,"delays":[0,400],"offsets":[[0,0,0],[500,0,0]],"duration":4000})
	var anchor := Vector3(5000,-100,8000)
	wrecks.update(region,0,anchor,Vector3.ZERO,true)
	expect(wrecks.events.size()==1,"A delayed explosion emits only its first aftermath initially")
	region.elapsed_ms=500;wrecks.update(region,500,anchor,Vector3.ZERO,true)
	expect(wrecks.events.size()==2,"A delayed blast receives its own cloud")
	var at: Vector3=wrecks.events[0].at;var age: float=wrecks.events[0].age
	for i in 40:wrecks.update(region,0,anchor,Vector3.ZERO,true)
	expect(wrecks.events.size()==2 and wrecks.events[0].age==age,"Pause freezes the aftermath and never duplicates emissions")
	region.visual_events.clear();region.elapsed_ms=5000;wrecks.update(region,4500,anchor,Vector3.ZERO,true)
	expect(wrecks.events.size()==2 and wrecks.clouds.multimesh.visible_instance_count>0 and wrecks.fragments.multimesh.visible_instance_count>0,"Clouds and debris outlast removal of the simulation flash")
	var transform: Transform3D=wrecks.fragments.multimesh.get_instance_transform(0)
	var shift := Vector3(1300,0,-800);wrecks.update(region,0,anchor+shift,Vector3.ZERO,true)
	var rebased: Transform3D=wrecks.fragments.multimesh.get_instance_transform(0)
	expect(wrecks.events[0].at==at,"Floating-origin rebasing preserves the absolute event position")
	# The headless dummy renderer does not retain MultiMesh transforms.
	if DisplayServer.get_name()!="headless":expect((transform.origin-rebased.origin).distance_to(shift)<.01,"Floating-origin rebasing leaves drawn debris at the same absolute position")
	for i in 30:
		region.visual_event({"kind":"explosion","position":[i*100,0,0],"creature":false,"delays":[0],"offsets":[],"duration":4000})
	wrecks.update(region,0,anchor,Vector3.ZERO,true)
	expect(wrecks.events.size()==Wrecks.CAPACITY and wrecks.clouds.multimesh.visible_instance_count<=Wrecks.CAPACITY*Wrecks.CLOUDS,"Simultaneous explosions stay within fixed pools")
	region.visual_events.clear();wrecks.update(region,11000,anchor,Vector3.ZERO,true)
	expect(wrecks.events.is_empty() and wrecks.fragments.multimesh.visible_instance_count==0,"Old aftermath fully expires")
	region.visual_event({"kind":"explosion","position":[0,0,0],"creature":true,"delays":[0],"offsets":[],"duration":4000})
	wrecks.update(region,0,anchor,Vector3.ZERO,true)
	expect(wrecks.events.is_empty(),"Creatures never produce metal wreckage")
	wrecks.queue_free()

func energy(viewport: SubViewport) -> float:
	await process_frame;await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image();var result := 0.0
	for y in pixels.get_height():
		for x in pixels.get_width():
			var pixel := pixels.get_pixel(x,y);result+=pixel.r+pixel.g+pixel.b
	return result

func check_rendered_regions(world) -> void:
	if DisplayServer.get_name()=="headless":return
	var viewport := SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();viewport.add_child(camera)
	var view := ViewProbe.new();viewport.add_child(view)
	var abyss=load("res://native/presentation/abyss.gd").new();abyss.camera=camera;abyss.world=world;abyss.view=view;viewport.add_child(abyss);abyss.set_process(false);abyss.particles.hide();abyss.set_headlights(false)
	var cold := Vector2.ZERO;var green := Vector2.ZERO;var coldest := 2.0;var greenest := 0.0
	for x in range(0,101,5):
		for y in range(0,101,5):
			var chart := Vector2(x,y);var water := Profile.sample(chart,world.session.data)
			if water.tint.y<coldest:coldest=water.tint.y;cold=chart
			if water.tint.y>greenest:greenest=water.tint.y;green=chart
	var saved: Array=world.region.player.pose.origin.duplicate()
	var origin: Array=world.station_origin(world.session.station_id)
	var colors: Array[Vector3]=[]
	for chart in [cold,green]:
		world.region.player.pose.origin=[roundi(chart.x*world.map_scale())-origin[0],saved[1],roundi(chart.y*world.map_scale())-origin[2]]
		var before: Vector3=abyss.water_tint;abyss.update_water_light(22500,1.0/60)
		expect(abyss.water_tint.distance_to(before)<.015,"Crossing a regional boundary blends the water rather than jumping")
		for i in 300:abyss.update_water_light(22500,.05)
		var target := Profile.sample(chart,world.session.data)
		expect(abyss.water_tint.distance_to(target.tint)<.001 and absf(abyss.haze_gain-target.haze)<.001 and absf(abyss.snow_density-target.snow)<.001,"Actual chart position drives tint, visibility and particle density together")
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(64,32)
		colors.append(Vector3(pixel.r,pixel.g,pixel.b))
	# Blue and green water can have equal total brightness; compare their hue.
	expect(colors[0].distance_to(colors[1])>minf(colors[0].length(),colors[1].length())*.02,"Regional colour differences reach the rendered ocean (%s / %s)"%[colors[0],colors[1]])
	view.modern_graphics=false
	for i in 300:abyss.update_water_light(22500,.05)
	expect(abyss.water_tint.distance_to(Vector3.ONE)<.001 and absf(abyss.haze_gain-1)<.001,"Classic lighting restores neutral regional water")
	world.region.player.pose.origin=saved
	viewport.queue_free();await process_frame

func check_jellyfish_pulse(content) -> void:
	if DisplayServer.get_name()=="headless":return
	var entries: Array=content.registry.filter(func(entry):return int(entry.id)==4426)
	expect(entries.size()==1,"Compatible content provides the original luminous jellyfish")
	if entries.is_empty():return
	var viewport := SubViewport.new();viewport.size=Vector2i(160,160);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=0;viewport.add_child(environment)
	var model=load("res://native/presentation/model.gd").new();viewport.add_child(model);model.configure(content.root,entries[0])
	var bounds: AABB=model.solid_bounds();var center := bounds.get_center();var span := maxf(bounds.size.length(),1.0)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=span*1.1;viewport.add_child(camera);camera.look_at_from_position(center+Vector3(0,0,span*2+10),center)
	var mesh: MeshInstance3D=model.figure.get_node("Mesh")
	for index in mesh.mesh.get_surface_count():mesh.get_surface_override_material(index).set_shader_parameter("distance_haze",0.0)
	var low := INF;var high := 0.0
	for i in 8:
		RenderingServer.global_shader_parameter_set("ocean_visual_time",float(i)*TAU/(8*1.15))
		var brightness: float=await energy(viewport);low=minf(low,brightness);high=maxf(high,brightness)
	expect(low>1.0 and high-low>high*.04 and high-low<high*.4,"The imported jellyfish glows in darkness with a gentle, visible pulse")
	model.library.bioluminescence=false;model.refresh()
	for index in mesh.mesh.get_surface_count():mesh.get_surface_override_material(index).set_shader_parameter("distance_haze",0.0)
	var dark: float=await energy(viewport)
	expect(dark<low*.25,"Disabling bioluminescence removes the jellyfish's emitted light")
	RenderingServer.global_shader_parameter_set("ocean_visual_time",0.0)
	viewport.queue_free();await process_frame

func check_lit_snow() -> void:
	if DisplayServer.get_name()=="headless":return
	var viewport := SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;viewport.add_child(environment)
	var camera := Camera3D.new();viewport.add_child(camera)
	var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/particulate.gdshader")
	var quad := QuadMesh.new();quad.material=material;quad.size=Vector2.ONE
	var mesh := MultiMesh.new();mesh.transform_format=MultiMesh.TRANSFORM_3D;mesh.use_custom_data=true;mesh.mesh=quad;mesh.instance_count=1
	mesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(0,0,-14)));mesh.set_instance_custom_data(0,Color(.1,0,1,1))
	var node := MultiMeshInstance3D.new();node.multimesh=mesh;node.custom_aabb=AABB(Vector3(-30,-30,-40),Vector3.ONE*60);viewport.add_child(node)
	var pixels := Image.create(12,12,false,Image.FORMAT_RF);pixels.fill(Color(80,0,0));var reach := ImageTexture.create_from_image(pixels)
	material.set_shader_parameter("enhanced",1.0);material.set_shader_parameter("snow_density",1.3)
	for suffix in ["_a","_b"]:
		material.set_shader_parameter("lamp_frame"+suffix,Transform3D.IDENTITY);material.set_shader_parameter("lamp_occlusion"+suffix,reach)
	var unlit: float=await energy(viewport)
	material.set_shader_parameter("lamp_active_a",1.0)
	var lit: float=await energy(viewport)
	expect(lit>unlit*5 and lit>1,"Marine snow becomes much brighter inside a headlight cone")
	material.set_shader_parameter("lamp_color_a",Color(1,.3,.33))
	await energy(viewport)
	var red_pixels := viewport.get_texture().get_image();var red := Vector3.ZERO
	for y in red_pixels.get_height():
		for x in red_pixels.get_width():
			var pixel := red_pixels.get_pixel(x,y);red+=Vector3(pixel.r,pixel.g,pixel.b)
	expect(red.x>red.y*2 and red.x>red.z*2,"Snow illuminated by a red headlight renders red, rather than cyan")
	material.set_shader_parameter("lamp_color_a",Color(.72,.9,1.0))
	material.set_shader_parameter("snow_enabled",false)
	var no_snow: float=await energy(viewport)
	expect(no_snow<lit*.05,"The marine snow switch removes headlight-lit flakes")
	material.set_shader_parameter("snow_enabled",true)
	pixels.fill(Color(4,0,0));reach.update(pixels)
	var blocked: float=await energy(viewport)
	expect(blocked<lit*.25,"A wall blocking the beam also stops illumination of snow behind it")
	material.set_shader_parameter("lamp_active_a",0.0)
	var trail := PackedVector4Array();trail.resize(10);trail[0]=Vector4(0,0,-14,0)
	var strengths := PackedFloat32Array();strengths.resize(10);strengths[0]=1
	material.set_shader_parameter("disturbance",trail);material.set_shader_parameter("disturbance_strength",strengths)
	var glow: float=await energy(viewport)
	material.set_shader_parameter("snow_enabled",false)
	var glow_only: float=await energy(viewport)
	expect(glow_only>glow*.85,"Bioluminescent particles remain visible with marine snow off")
	material.set_shader_parameter("bioluminescence_enabled",false)
	var neither: float=await energy(viewport)
	expect(neither<glow*.05,"Disabling both effects removes the luminous particles")
	material.set_shader_parameter("snow_enabled",true);material.set_shader_parameter("bioluminescence_enabled",true)
	material.set_shader_parameter("drift_time",5.0)
	var faded: float=await energy(viewport)
	expect(glow>unlit*5 and faded<glow*.25,"Disturbed bioluminescence is visible with lamps off and fades after passage")
	viewport.queue_free();await process_frame

func prominent_peaks(values: Array[float], threshold: float) -> int:
	# Count visible bright crests, ignoring quantisation and tiny fluctuations.
	var low := values[0];var high := low;var rising := false;var count := 0
	for value in values:
		if rising:
			high=maxf(high,value)
			if high-value>threshold:count+=1;rising=false;low=value
		else:
			low=minf(low,value)
			if value-low>threshold:rising=true;high=value
	return count+(1 if rising else 0)

func check_sky_scattering() -> void:
	if DisplayServer.get_name()=="headless":return
	# Looking straight up exposed repeated curved stripes that a horizontal
	# flight screenshot missed. Render the actual sky at several orientations.
	var viewport := SubViewport.new();viewport.size=Vector2i(256,256);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.fov=75;viewport.add_child(camera)
	var environment := WorldEnvironment.new();var env := Environment.new();environment.environment=env
	var sky := Sky.new();var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/abyss_sky.gdshader");sky.sky_material=material
	env.background_mode=Environment.BG_SKY;env.sky=sky;env.tonemap_mode=Environment.TONE_MAPPER_ACES;viewport.add_child(environment)
	# Isolate scattered light from the original sky palette and sun opening.
	RenderingServer.global_shader_parameter_set("ocean_upper_color",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set("ocean_sun_gain",0.0)
	RenderingServer.global_shader_parameter_set("ocean_light_gain",1.0)
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",1.0)
	camera.look_at_from_position(Vector3.ZERO,Vector3.UP,Vector3.FORWARD)
	var lit: float=await energy(viewport)
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",0.0)
	var unlit: float=await energy(viewport)
	expect(lit>unlit+100,"Filtered sunlight remains visible and its switch removes the scattered light")
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",1.0)
	for direction in [Vector3.UP,Vector3(0,1,-.5),Vector3(1,.7,.2)]:
		camera.look_at_from_position(Vector3.ZERO,direction,Vector3.FORWARD if direction==Vector3.UP else Vector3.UP)
		for time in [0.0,14.0,57.0]:
			RenderingServer.global_shader_parameter_set("ocean_visual_time",time)
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			var largest := 0
			for vertical in [false,true]:
				for line in range(32,225,32):
					var values: Array[float]=[]
					for at in 256:values.append(pixels.get_pixel(line,at).get_luminance() if vertical else pixels.get_pixel(at,line).get_luminance())
					var span: float=values.max()-values.min()
					if span>.02:largest=maxi(largest,prominent_peaks(values,maxf(.01,span*.08)))
			expect(largest<=8,"Uneven strands do not repeat into extra contour bands (%s, time %s: %d crests)"%[direction,time,largest])
	# The bright opening and the converging shafts must agree even while the
	# scattering changes. A horizontal-only capture can hide an offset source.
	var sun_direction := Vector3(-.25,.95,-.15).normalized()
	for direction in [sun_direction,Vector3.UP]:
		camera.look_at_from_position(Vector3.ZERO,direction,Vector3.FORWARD if direction==Vector3.UP else Vector3.UP)
		var centre := camera.unproject_position(sun_direction*10)
		for time in [0.0,14.0,57.0]:
			RenderingServer.global_shader_parameter_set("ocean_visual_time",time)
			await energy(viewport)
			var pixels := viewport.get_texture().get_image()
			var brightest := Vector2.ZERO;var peak := -1.0
			for y in 256:
				for x in 256:
					var value := pixels.get_pixel(x,y).get_luminance()
					if value>peak:peak=value;brightest=Vector2(x+.5,y+.5)
			expect(brightest.distance_to(centre)<4,"Sun shafts converge at the bright opening at every animation phase (%s / %s)"%[brightest,centre])
	# A sky-only energy check also passed when the shafts were indistinct.
	# Verify contrast against the complete water background in a swimming view,
	# at mid-water depth with a typical regional attenuation rather than 1x.
	RenderingServer.global_shader_parameter_set("ocean_upper_color",Vector3(.025,.095,.22))
	RenderingServer.global_shader_parameter_set("ocean_water_tint",Vector3.ONE)
	RenderingServer.global_shader_parameter_set("ocean_light_gain",.6)
	RenderingServer.global_shader_parameter_set("ocean_sun_gain",.25)
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",.25)
	camera.look_at_from_position(Vector3.ZERO,Vector3(-.8,.25,-.6))
	await energy(viewport)
	var shafts: Image=viewport.get_texture().get_image()
	RenderingServer.global_shader_parameter_set("ocean_shaft_gain",0.0)
	await energy(viewport)
	var plain: Image=viewport.get_texture().get_image()
	var readable := 0;var maximum := 0.0
	for y in 256:
		for x in 256:
			var difference: float=shafts.get_pixel(x,y).get_luminance()-plain.get_pixel(x,y).get_luminance()
			maximum=maxf(maximum,difference)
			if difference>.025:readable+=1
	expect(maximum>.04 and readable>2000,"Sun shafts are distinguishable in mid-water with the full background (contrast %.3f, %d pixels)"%[maximum,readable])
	viewport.queue_free();await process_frame

func run() -> void:
	check_glass_mask();check_headlight_attachment()
	await check_beam_intersections()
	var content=load("res://native/content.gd").new()
	if not content.load_cache(OS.get_cmdline_user_args()[0]):quit(1);return
	check_profiles(content.data)
	await check_cabins(content)
	var session=load("res://native/simulation/session.gd").new();session.new_game(content.data,"Atmosphere check",612)
	var world=load("res://native/simulation/world.gd").new();world.configure(session);world.build_docked_view()
	session.docked=false
	await check_headlight_counts(world,content)
	await check_headlight_lenses(content)
	check_headlight_transitions(content)
	await check_frozen_water(world);check_aftermath(world.region)
	await process_frame
	await check_lit_snow()
	await check_rendered_regions(world)
	await check_jellyfish_pulse(content)
	await check_sky_scattering()
	world.dispose();await process_frame
	print("OCEAN_ATMOSPHERE %d failures"%failures);quit(1 if failures else 0)

func check_headlight_attachment() -> void:
	var rig=load("res://native/presentation/headlight_rig.gd")
	for scale in [1,2]:
		var atlas := Image.create(64*scale,32*scale,false,Image.FORMAT_RGBA8)
		atlas.fill(Color(.9,.18,.27));atlas.fill_rect(Rect2i(32*scale,0,32*scale,32*scale),Color(.18,.45,.9))
		atlas.fill_rect(Rect2i(15*scale,15*scale,2*scale,2*scale),Color.WHITE)
		var red: Color=rig.sample_tint(atlas,Rect2(0,0,31,16),Vector2(64,32))
		var blue: Color=rig.sample_tint(atlas,Rect2(32,0,31,16),Vector2(64,32))
		expect(red.r>.99 and red.g<.22 and red.b<.32 and blue.b>.99 and blue.r<.22,"Beam colour follows its original UV footprint at both native and replacement resolution, despite a white apex")
	# A flat hull with two original beam apices floating ahead of it. The
	# expected housings are analytical points on the plane, not mesh bounds.
	var points: Array[Vector3]=[Vector3(-2,-2,-2),Vector3(2,-2,-2),Vector3(2,2,-2),Vector3(-2,2,-2)]
	var polygons: Array=[{"blend":0,"indices":[0,1,2,0,2,3]}]
	for origin in [Vector3(-.7,.4,-3),Vector3(.7,-.4,-2.5)]:
		var apex: int=points.size();points.append(origin)
		for offset in [Vector3(-3,0,-20),Vector3(0,3,-20),Vector3(3,0,-20),Vector3(0,-3,-20)]:points.append(origin+offset)
		for i in 4:polygons.append({"blend":4,"indices":[apex,apex+1+i,apex+1+(i+1)%4]})
	var source: Dictionary={"vertices":[],"polygons":polygons,"bones":[{"vertices":points.size()}]}
	for point in points:source.vertices.append_array([point.x*100,-point.y*100,-point.z*100])
	var lamps: Array=rig.describe(source,[[1,0,0,0,0,1,0,0,0,0,1,0]])
	expect(lamps.size()==2,"Two original beam fans produce two lamps")
	if lamps.size()==2:
		expect(lamps[0].frame.origin.distance_to(Vector3(-.7,.4,-2.02))<.0001 and lamps[1].frame.origin.distance_to(Vector3(.7,-.4,-2.02))<.0001,"Floating source apices attach to actual hull faces with only 2 cm of clearance")
		expect((-lamps[0].frame.basis.z).distance_to(Vector3.FORWARD)<.0001,"The original cone direction survives attachment")
	source.polygons=[polygons[0]]
	expect(rig.describe(source,[[1,0,0,0,0,1,0,0,0,0,1,0]]).is_empty(),"A hull without original beam geometry does not gain invented headlights")

func check_headlight_counts(world, content) -> void:
	var scene := Node3D.new();root.add_child(scene)
	var camera := Camera3D.new();scene.add_child(camera)
	var view := ViewProbe.new();scene.add_child(view)
	var actors=load("res://native/presentation/world_view.gd").new();scene.add_child(actors);actors.set_process(false)
	var abyss=load("res://native/presentation/abyss.gd").new();abyss.camera=camera;abyss.world=world;abyss.view=view;scene.add_child(abyss);abyss.set_process(false)
	for id in 12:
		var model=load("res://native/presentation/model.gd").new();scene.add_child(model)
		model.library.blue_headlights=true
		model.configure(content.root,content.registry.filter(func(entry):return int(entry.id)==id)[0])
		model.transform=Transform3D(Basis.from_euler(Vector3(.25,.8,-.4)),Vector3(30,-12,40))
		view.player_model=model;abyss._process(0)
		var expected: int=0 if id==11 else 1 if id in [8,9] else 2
		var frames: Array=model.headlight_frames()
		expect(frames.size()==expected and abyss.lamps.filter(func(lamp):return lamp.visible).size()==expected,"Hull %d retains the original number of headlights for the player"%id)
		var other: Array=actors.add_actor_lights(model)
		expect(other.size()==expected,"Hull %d uses the same lamp count on other ships"%id)
		for i in frames.size():
			expect(abyss.lamps[i].global_transform.is_equal_approx(other[i].global_transform),"Player and NPC emitters coincide on a pitched, banked hull")
			var tint: Color=abyss.lamps[i].light_color
			expect(tint.is_equal_approx(other[i].light_color) and tint.is_equal_approx(abyss.beams[i].material_override.get_shader_parameter("tint")) and tint.is_equal_approx(other[i].get_child(0).material_override.get_shader_parameter("tint")),"Player and NPC beams and surface lights share their original atlas colour")
			expect(tint.r>tint.b*2 if id==10 else tint.b>tint.r*2,"Aquarius keeps its original red beams; the other equipped hulls keep blue beams")
		if id==4:expect(absf(frames[0].origin.x-frames[1].origin.x)<.01 and absf(frames[0].origin.y-frames[1].origin.y)>4,"Derketo retains its original vertical lamp arrangement")
		if id==8:expect(frames[0].origin.x<-1,"Pontos retains its single lamp on the original side")
		if id==9:expect(absf(frames[0].origin.x)<.3,"Lir retains its original central lamp")
		model.queue_free();await process_frame
	view.player_model=null;scene.queue_free();await process_frame

func check_headlight_lenses(content) -> void:
	for id in [0,5,8]:await check_ship_lenses(content,id)

func expect_lenses(model, enabled: bool, why: String) -> void:
	var mesh: MeshInstance3D=model.figure.get_node("Mesh")
	var count := 0
	for i in mesh.mesh.get_surface_count():
		var material: ShaderMaterial=mesh.get_surface_override_material(i)
		if not material.get_shader_parameter("headlight_lens"):continue
		count+=1
		expect(material.get_shader_parameter("headlight_lens_enabled")==enabled,why)
	expect(count>0,"The transition check covers actual lamp lens materials")

func check_headlight_transitions(content) -> void:
	var kind=load("res://native/presentation/model.gd")
	var entry: Dictionary=content.registry.filter(func(record):return int(record.id)==0)[0]
	var model=kind.new();root.add_child(model);model.configure(content.root,entry)
	expect_lenses(model,true,"Default white lamp panes are enabled on first construction")
	model.set_headlight_lenses(false)
	model.set_portal_clip(true,Vector4(0,0,1,0))
	model.set_headlight_lenses(true)
	model.set_portal_clip(false)
	model.set_headlight_lenses(true)
	expect_lenses(model,true,"Leaving the hangar keeps the lamp panes on without changing colour settings")
	model.set_headlight_lenses(false);model.set_stream_visibility(.4)
	model.set_headlight_lenses(true);model.set_stream_visibility(1.0)
	expect_lenses(model,true,"Finishing a streaming fade cannot restore disabled lamp panes")
	model.set_headlight_lenses(false);model.apply_range([1,1])
	var peer=kind.new();peer.library=model.library;root.add_child(peer);peer.configure(content.root,entry);peer.apply_range([1,1])
	expect_lenses(model,false,"The player's disabled lights remain off on another pose")
	expect_lenses(peer,true,"A pose first cached with the player's lights off does not darken another vessel")
	model.queue_free();peer.queue_free()

func check_ship_lenses(content, id: int) -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(192,128);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=0;viewport.add_child(environment)
	var model=load("res://native/presentation/model.gd").new();model.library.cabin_lights=false;model.library.blue_headlights=true;viewport.add_child(model)
	var entry: Dictionary=content.registry.filter(func(record):return int(record.id)==id)[0]
	model.configure(content.root,entry)
	var lenses: Dictionary=model.headlight_lens_faces()
	expect(lenses.size()==(4 if id==0 else 2),"Hull %d lights its complete lamp faces and keeps the cockpit separate"%id)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.1;viewport.add_child(camera)
	var peer=load("res://native/presentation/model.gd").new();peer.library=model.library;viewport.add_child(peer);peer.configure(content.root,entry);peer.position.x=1000
	for mount in model.headlight_rig():
		if DisplayServer.get_name()=="headless":continue
		model.set_headlight_lenses(true);model.library.blue_headlights=true;model.refresh()
		camera.look_at_from_position(mount.surface+mount.direction*3,mount.surface)
		var lit: float=await energy(viewport);var blue := pixel_sum(viewport)
		expect(lit>5 and blue.z>blue.x*2,"Hull %d lamp at %s renders blue with cabin lights disabled"%[id,mount.surface])
		if id in [5,8]:
			var centre := viewport.get_texture().get_image().get_pixel(96,64)
			expect(centre.b>.3 and centre.b>centre.r*2,"The beam axis meets the lit lens centre, not its frame or the neighboring grille")
		model.set_headlight_lenses(false)
		var dark: float=await energy(viewport)
		expect(dark<lit*.05,"Turning headlights off extinguishes the lens without making it an amber cabin")
		var peer_mesh: MeshInstance3D=peer.figure.get_node("Mesh")
		for i in peer_mesh.mesh.get_surface_count():
			var material: ShaderMaterial=peer_mesh.get_surface_override_material(i)
			if material.get_shader_parameter("headlight_lens"):expect(material.get_shader_parameter("headlight_lens_enabled"),"Switching one vessel's headlights leaves another identical vessel's lenses on")
		model.set_headlight_lenses(true);model.library.blue_headlights=false;model.refresh()
		await energy(viewport);var white := pixel_sum(viewport)
		expect(white.x>white.z*.65 and white.x>blue.x*1.5,"The White setting also restores white light to the actual lens")
	viewport.queue_free();await process_frame

func pixel_sum(viewport: SubViewport) -> Vector3:
	var pixels := viewport.get_texture().get_image();var total := Vector3.ZERO
	for y in pixels.get_height():
		for x in pixels.get_width():
			var pixel := pixels.get_pixel(x,y);total+=Vector3(pixel.r,pixel.g,pixel.b)
	return total

func beam_frame(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check_beam_intersections() -> void:
	if DisplayServer.get_name()=="headless":return
	var lighting=load("res://native/presentation/abyss.gd")
	var viewport := SubViewport.new();viewport.size=Vector2i(256,192);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;viewport.add_child(environment)
	var scene := Node3D.new();viewport.add_child(scene)
	var camera := Camera3D.new();camera.fov=65;camera.far=10000;scene.add_child(camera)
	var beams: Array=[]
	for x in [-2.14,2.14]:
		var beam: MeshInstance3D=lighting.create_beam();scene.add_child(beam);beam.position.x=x
		beam.material_override.set_shader_parameter("tint",Color.WHITE);beam.material_override.set_shader_parameter("energy",.2);beams.append(beam)
	camera.look_at_from_position(Vector3(0,5,3),Vector3(0,5,-40))
	var open := await beam_frame(viewport)
	# A common rigid transform cannot carve curves or polygonal sheets into
	# clear water. This also checks precision away from the world origin.
	scene.transform=Transform3D(Basis.from_euler(Vector3(-1.2,.8,.35)),Vector3(600,3000,-2000))
	var moved := await beam_frame(viewport)
	var difference := 0.0;var count := 0
	for y in 192:
		for x in 256:
			var a := open.get_pixel(x,y).r
			if a>.05:difference+=absf(a-moved.get_pixel(x,y).r);count+=1
	expect(count>400 and difference/maxi(1,count)<.003,"Pitched overlapping beams stay continuous while travelling across the map")
	# Two additive beams must neither cut one another off nor depend on draw
	# order. Compare their actual combined radiance with independent renders.
	beams[1].hide();var left := await beam_frame(viewport)
	beams[1].show();beams[0].hide();var right := await beam_frame(viewport)
	beams[0].show();scene.move_child(beams[0],scene.get_child_count()-1);var pair := await beam_frame(viewport)
	var error := 0.0
	for y in range(0,192,2):
		for x in range(0,256,2):
			var sum := left.get_pixel(x,y).srgb_to_linear().r+right.get_pixel(x,y).srgb_to_linear().r
			error=maxf(error,absf(sum-pair.get_pixel(x,y).srgb_to_linear().r))
	expect(error<.015,"Crossing beams add light without a sorting seam")
	scene.transform=Transform3D.IDENTITY
	beams[1].hide();beams[0].position=Vector3.ZERO
	beams[0].material_override.set_shader_parameter("energy",.7)
	camera.position=Vector3(0,0,-20);camera.rotation=Vector3.ZERO
	var inside := await beam_frame(viewport)
	var jump := 0.0
	for x in range(1,256):jump=maxf(jump,absf(inside.get_pixel(x,96).r-inside.get_pixel(x-1,96).r))
	expect(inside.get_pixel(128,96).r>.03 and jump<.025,"Inside a beam there is lit water without a disappearing volume or a bright circular discontinuity")
	# A wall before the lens hides all scattering; one farther into the cone
	# leaves only the water between the lens and the wall visible.
	camera.position=Vector3(0,0,5)
	var clear := await energy(viewport)
	var wall := MeshInstance3D.new();var quad := QuadMesh.new();quad.size=Vector2(100,100);wall.mesh=quad
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color.BLACK;wall.material_override=material;scene.add_child(wall)
	wall.position.z=-10;var shortened := await energy(viewport)
	wall.position.z=.2;var hidden := await energy(viewport)
	expect(shortened>clear*.05 and shortened<clear*.98 and hidden<clear*.001,"Solid surfaces terminate the visible beam at scene depth, preserving only foreground scattering")
	wall.queue_free();await process_frame
	# Check the lamp's occlusion map independently of camera depth: the wall
	# is collision-only and the camera sees water beyond it from the side.
	camera.look_at_from_position(Vector3(15,0,-30),Vector3(0,0,-30));camera.fov=30
	var unblocked := await energy(viewport)
	var blocker := StaticBody3D.new();blocker.collision_layer=2;blocker.position.z=-10;scene.add_child(blocker)
	var collider := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(50,50,1);collider.shape=box;blocker.add_child(collider)
	var lamp := SpotLight3D.new();lamp.visible=false;scene.add_child(lamp)
	await physics_frame;await process_frame
	for phase in 2:lighting.shade_beam_in(scene.get_world_3d().direct_space_state,lamp,beams[0],phase)
	var blocked := await energy(viewport)
	expect(unblocked>10 and blocked<unblocked*.05,"A blocker at the lamp stops the beam beyond it even when viewed from the side")
	viewport.queue_free();await process_frame
