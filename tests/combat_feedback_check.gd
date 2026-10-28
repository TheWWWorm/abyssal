extends SceneTree
const Weapon=preload("res://native/simulation/weapon.gd")
const Effects=preload("res://native/presentation/combat_effects.gd")
const Audio=preload("res://native/presentation/dive_audio.gd")
var failures:=0
var checks:=0
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func run() -> void:
	var shot:=Weapon.new();shot.configure(3,1,1000,200,12,[0,0,0])
	var pose=preload("res://native/simulation/ship_transform.gd").new()
	shot.launch(pose,40);shot.advance(40)
	var start:=Effects.projectile_position(shot,0,0)
	var finish:=Effects.projectile_position(shot,0,1)
	expect(start.is_equal_approx(Vector3.ZERO) and finish.distance_to(start)>4,"A newly fired projectile interpolates from its muzzle")
	expect(Effects.projectile_position(shot,0,.5).is_equal_approx(start.lerp(finish,.5)),"Between ticks a shot draws halfway along its actual movement")
	shot.remaining[0]=-1;pose.origin=[20000,0,0];shot.launch(pose,40)
	expect(Effects.projectile_position(shot,0,0).is_equal_approx(Vector3(200,0,0)),"A reused projectile slot never draws a trail from its previous shot")
	for kind in Audio.LAUNCH_CUES:
		var sound:=Audio.synthesize_cue(kind);var peak:=0;var energy:=0.0
		for i in sound.data.size()/2:
			var value:=sound.data.decode_s16(i*2);peak=maxi(peak,absi(value));energy+=float(value)*value
		expect(peak>4000 and peak<32000 and energy>1e9,"The %s report is audible without clipping"%kind)
		expect(sound.data.decode_s16(0)==0 and sound.data.decode_s16(sound.data.size()-2)==0,"The %s report begins and ends at silence"%kind)
		expect(sound.data==Audio.synthesize_cue(kind).data,"The %s report is reproducible"%kind)
	var args:=OS.get_cmdline_user_args()
	var content=preload("res://native/content.gd").new()
	if args.is_empty() or not content.load_cache(args[0]):push_error("Pass a compatible imported content directory");quit(1);return
	var session=preload("res://native/simulation/session.gd").new();session.new_game(content.data,"Combat feedback",812)
	var world=preload("res://native/simulation/world.gd").new();world.configure(session);world.build_docked_view();session.docked=false
	var region=world.region;region.enemies=[];region.friends=[];region.creatures=[];region.fishing=[];region.weapons=[];region.visual_events=[]
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,50)
	var view=preload("res://native/presentation/world_view.gd").new();root.add_child(view);view.set_process(false);view.configure(world,content,camera)
	var weapons: Array=[]
	for id in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,42]:
		var weapon=region.loadout.create(session.make_equipment(id),content.data)
		weapon.launch(region.player.pose,40);weapon.advance(40);weapons.append(weapon)
		expect(weapon.launch_serial==1 and weapon.remaining.filter(func(v):return v>0).size()==1,"One press launches one logical projectile from equipment %d"%id)
	region.loadout.groups=[weapons]
	var before:=weapons.map(func(w):return JSON.stringify(w.values()))
	world.accumulator=20
	view.combat.update(region,0,0)
	expect(view.combat.projectile_count==13,"All model-based projectiles retain their source identity for Classic and pigment lookup")
	expect(view.combat.ribbon_count==3,"Three coil pulses keep a continuous axial streak; other rounds use attached volumes")
	expect(view.combat.hook_count==3 and view.combat.modern_forms.has("hook:2"),"Each active harpoon carries a visible tether and a distinct barbed dart")
	expect(view.combat.burst_count==0,"Flying harpoons have no travelling flare obscuring the attachment head")
	expect(view.combat.harpoon_colors.size()==3 and view.combat.projectile_colors.size()==11,"Each harpoon and projectile retains its own sampled atlas colour")
	for i in 3:
		expect(view.combat.modern_forms["hook:"+str(i)].moving.is_empty(),"Harpoon tips have fixed barbs, no orbiting fields")
		expect(view.combat.modern_forms["hook:"+str(i)].tier==i,"Harpoon %d selects its own barbed dart"%(i+15))
		expect(view.combat.coil_color(i+3).is_equal_approx(Color(view.combat.harpoon_color(weapons[i+15]),1)),"Coil %d retains its corresponding original atlas pigment"%(i+3))
	for i in weapons.size():
		if weapons[i].fishing or weapons[i].beam:continue
		var key:=str(weapons[i].get_instance_id())+":0"
		expect(view.combat.projectile_nodes[key].position.is_equal_approx(Effects.projectile_position(weapons[i],0,.5)),"Rendered weapon %d follows its interpolated position"%weapons[i].equipment_id)
	expect(view.combat.modern_forms.size()==19,"All nineteen equipment types have independent modern presentation")
	for id in [0,6,9,12]:
		var key:=str(weapons[id].get_instance_id())+":0"
		expect(not view.combat.projectile_nodes[key].visible and view.combat.modern_forms[key].visible,"Modern weapon %d replaces the old mesh, rather than layering a duplicate shot"%id)
	var gun=view.combat.projectile_nodes[str(weapons[0].get_instance_id())+":0"]
	var gun_mesh: MeshInstance3D=gun.figure.get_node("Mesh")
	var detailed: ShaderMaterial=gun_mesh.get_active_material(0)
	expect(detailed.has_meta("weapon_original"),"The projectile receives its own enhanced material")
	var copied:=Effects.Library.pose_copy(detailed)
	expect(copied.shader==detailed.get_meta("weapon_original").shader and not copied.has_meta("weapon_original"),"Advancing an animation never copies presentation overrides into the shared pose cache")
	var palette: Color=view.combat.projectile_color(gun)
	expect(palette.g>palette.r*2 and palette.b>palette.r*2,"The cyan gun samples emitted light without mixing in the subtractive red atlas patch")
	var frozen_time: float=view.combat.visual_time
	view.combat.update(region,0,0)
	expect(view.combat.visual_time==frozen_time,"Frozen simulation time also freezes plasma filaments and tether pulses")
	for frame in 12:
		region.elapsed_ms+=40;view.combat.update(region,40,0)
	var clean_cache:=true
	for entry in view.library.native_pose_cache.values():
		for material in entry.materials:
			if material.has_meta("weapon_original"):clean_cache=false
	expect(clean_cache,"Multiple animated weapon frames leave the shared model poses unchanged")
	view.modern_graphics=false;view.combat.update(region,0,0)
	expect(view.combat.modern_forms.size()==19 and view.combat.hook_count==3,"Classic lighting can retain enhanced weapons")
	view.modern_graphics=true;view.combat.set_enhanced_weapons(false);view.combat.update(region,0,0)
	expect(view.combat.ribbon_count==0 and view.combat.segment_count==6 and view.combat.projectile_count==13,"Classic retains the original lines and imported models")
	expect(view.combat.hook_heads.multimesh.visible_instance_count==0 and view.combat.cables.multimesh.visible_instance_count==0,"Classic removes the enhanced tether hardware")
	var restored:=true
	for visual in view.combat.projectile_nodes.values():
		var mesh: MeshInstance3D=visual.figure.get_node("Mesh")
		for i in mesh.mesh.get_surface_count():
			if mesh.get_active_material(i).has_meta("weapon_original"):restored=false
	expect(restored,"Returning to Classic restores the actual imported materials")
	expect(view.combat.modern_forms.values().all(func(n):return not n.visible),"Classic hides every modern weapon volume")
	expect(weapons.map(func(w):return JSON.stringify(w.values()))==before,"Presentation changes neither projectile positions nor lifetime and cooldown")
	view.combat.set_enhanced_weapons(true)
	for i in 4:
		for w in weapons:
			if w.homing:w.advance(40)
		region.elapsed_ms+=40;view.combat.update(region,40,0)
	expect(view.combat.torpedo_wakes.size()>0,"Moving torpedoes leave a persistent wake")
	var first_wake: Dictionary=view.combat.torpedo_wakes[0].duplicate()
	weapons[12].velocities[0]=[400,0,0]
	weapons[12].advance(40);region.elapsed_ms+=40;view.combat.update(region,40,0)
	expect(view.combat.torpedo_wakes[0].at==first_wake.at,"A guidance turn leaves the old wake at its emission point")
	var wake_count: int=view.combat.torpedo_wakes.size()
	var frozen_bubbles: PackedFloat32Array=view.combat.bubbles.multimesh.buffer
	view.combat.update(region,0,0)
	expect(view.combat.torpedo_wakes.size()==wake_count,"Repeated frozen frames emit no duplicate wake particles")
	expect(view.combat.bubbles.multimesh.buffer==frozen_bubbles,"A frozen frame preserves bubble positions, opacity and the small-bubble pattern")
	# Torpedoes are far ahead of the test camera; streams fade with distance.
	camera.position=Vector3(0,5,300);view.combat.update(region,0,0)
	var lens: MultiMeshInstance3D=view.combat.distortion
	expect(lens.visible and lens.multimesh.visible_instance_count==3,"Each travelling torpedo bends the water in its stream")
	var blast:={"kind":"explosion","position":[0,0,-6000],"creature":false,"delays":[0,0,0,0,0,0,0,0],"offsets":[[0,0,0],[800,0,0],[-800,0,0],[0,800,0],[0,-800,0],[800,800,0],[-800,-800,0],[800,-800,0]],"duration":1000,"time":region.elapsed_ms-200}
	region.visual_events.append(blast);view.combat.update(region,0,0)
	var rings:=0
	for i in lens.multimesh.visible_instance_count:
		if lens.multimesh.get_instance_custom_data(i).r==0:rings+=1
	expect(lens.multimesh.visible_instance_count==Effects.DISTORTION_CAPACITY and rings==Effects.DISTORTION_CAPACITY,"Shock rings take the capped refraction pool before propulsion streams")
	view.combat.set_aftermath(false);view.combat.update(region,0,0)
	expect(lens.multimesh.visible_instance_count==3,"Without the explosion aftermath, detonations bend no water")
	view.combat.set_aftermath(true);view.modern_graphics=false;view.combat.update(region,0,0)
	expect(not lens.visible and lens.multimesh.visible_instance_count==0,"Classic graphics never sample the screen")
	view.modern_graphics=true;region.visual_events.erase(blast);camera.position=Vector3(0,0,50);view.combat.update(region,0,0)
	if DisplayServer.get_name()!="headless":
		await check_ribbon(view)
		var mass_colors: Dictionary={}
		for form in view.combat.modern_forms.values():
			if form.family=="mass":mass_colors[form.equipment]=form.tint
		await check_modern_forms(mass_colors)
	view.modern_graphics=true;view.combat.update(region,0,0)
	for i in 40:view.combat.hook_line(Vector3.ZERO,Vector3(4,0,0),weapons[15])
	expect(view.combat.hook_count==32,"Tether hardware respects its fixed pool capacity")
	view.combat.reset();expect(view.combat.ribbons.multimesh.visible_instance_count==0 and view.combat.hook_heads.multimesh.visible_instance_count==0,"Changing regions clears traces and attachment heads")
	expect(view.combat.torpedo_wakes.is_empty() and view.combat.torpedo_tails.is_empty() and view.combat.modern_forms.is_empty(),"Changing regions clears torpedo history and modern form pools")
	expect(not view.combat.distortion.visible,"Changing regions hides the refraction pool, so no frame copies the screen")
	view.queue_free();camera.queue_free();world.region.dispose();world.region=null;await process_frame
	print("COMBAT_FEEDBACK ",checks," checks; ",failures," failures");quit(1 if failures else 0)
func frame_energy(viewport: SubViewport) -> float:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image();var result:=0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel:=image.get_pixel(x,y);result+=pixel.r+pixel.g+pixel.b
	return result
func check_ribbon(view) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;viewport.add_child(environment)
	var camera:=Camera3D.new();viewport.add_child(camera)
	var saved: Camera3D=view.camera;view.camera=camera
	var effect:=Effects.new();effect.owner_view=view;viewport.add_child(effect)
	for position in [Vector3(0,0,20),Vector3(20,0,0),Vector3(0,20,0),Vector3(0,0,120)]:
		camera.position=position;camera.look_at(Vector3.ZERO,Vector3.FORWARD if position.y>0 else Vector3.UP)
		effect.ribbon_count=0;effect.ribbon(Vector3(-4,0,0),Vector3(4,0,0),.4,Color(.4,.8,1,.45));effect.ribbons.multimesh.visible_instance_count=1;effect.refresh_bounds()
		expect(await frame_energy(viewport)>.01,"A soft line stays visible at "+str(position))
	# Exercise signed lobes at several animation phases, including the negative
	# half-cycle. Undefined pow(negative, 2) used to turn a trace into a white
	# oval on Vulkan, despite the shader compiling and visibility tests passing.
	camera.position=Vector3(2,3,20);camera.look_at(Vector3.ZERO)
	for phase in [0.0,.15,.4,.8,1.1]:
		for trail in [false,true]:
			effect.visual_time=phase;effect.ribbon_count=0
			effect.ribbon(Vector3(-4,0,0),Vector3(4,0,0),.4,Color(.1,.5,.9,.45),trail)
			effect.ribbons.multimesh.visible_instance_count=1;effect.refresh_bounds()
			await frame_energy(viewport)
			expect(white_pixels(viewport)==0,"The coloured trace has no blown white pixels at phase %s (trail %s)"%[phase,trail])
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;camera.position=Vector3(0,0,120);camera.look_at(Vector3.ZERO)
	await frame_energy(viewport)
	var image:=viewport.get_texture().get_image();var rows:=0
	for y in image.get_height():
		var lit:=false
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			if maxf(c.r,maxf(c.g,c.b))>.005:lit=true
		if lit:rows+=1
	expect(rows>0 and rows<12,"An orthographic inspection keeps the line thin rather than expanding it with distance")
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=Vector3(0,0,20);camera.look_at(Vector3.ZERO)
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(12,12,1);blocker.mesh=box
	var black:=StandardMaterial3D.new();black.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;black.albedo_color=Color.BLACK;blocker.material_override=black;blocker.position.z=10;viewport.add_child(blocker)
	expect(await frame_energy(viewport)<.001,"Opaque hulls and walls hide the enhanced line")
	blocker.queue_free();effect.ribbons.multimesh.visible_instance_count=0;await process_frame
	view.modern_graphics=true
	for id in [6754,6760,6763,6766]:
		var shot=view.model(id,32,viewport,false)
		for phase in [0.0,.4,.8]:
			effect.visual_time=phase;effect.shade_projectile(shot,id==6760)
			for at in [Vector3(20,0,0),Vector3(0,20,0),Vector3(0,0,20)]:
				camera.position=at;camera.look_at(Vector3.ZERO,Vector3.FORWARD if at.y>0 else Vector3.UP)
				expect(await frame_energy(viewport)>1.0,"Projectile %d remains visible from %s at phase %s"%[id,at,phase])
				expect(white_pixels(viewport)==0,"Projectile %d preserves its pigment without a white flare"%id)
		shot.queue_free();await process_frame
	for pair in [[0,6754],[3,-1],[7,6761],[11,6765],[14,16],[42,6766]]:
		camera.position=Vector3(0,0,20);camera.look_at(Vector3.ZERO)
		for age in [0.0,.2,.6]:
			effect.burst_count=0;effect.ribbon_count=0;effect.bubble_count=0;effect.impact_count=0
			for form in effect.impact_forms:form.hide()
			effect.effect_bounds.clear()
			effect.impact({"position":[0,0,0],"direction":[0,0,-4096],"equipment":pair[0],"model":pair[1],"damage":30,"beam":pair[0]==3,"homing":pair[0]==14},age)
			effect.bursts.multimesh.visible_instance_count=effect.burst_count
			effect.ribbons.multimesh.visible_instance_count=effect.ribbon_count
			effect.bubbles.multimesh.visible_instance_count=effect.bubble_count;effect.refresh_bounds()
			expect(await frame_energy(viewport)>.001,"Weapon %d has visible impact feedback at age %.1f"%[pair[0],age])
			expect(white_pixels(viewport)==0,"Weapon %d retains a coloured impact without a white flash"%pair[0])
	effect.bursts.multimesh.visible_instance_count=0;effect.ribbons.multimesh.visible_instance_count=0;effect.bubbles.multimesh.visible_instance_count=0
	for form in effect.impact_forms:form.hide()
	for id in [15,16,17]:
		var hook:=Weapon.new();hook.equipment_id=id
		for distance in [20.0,120.0]:
			camera.position=Vector3(0,distance*.15,distance);camera.look_at(Vector3.ZERO)
			effect.hook_count=0;effect.effect_bounds.clear();effect.hook_line(Vector3(0,0,5),Vector3.ZERO,hook)
			effect.cables.multimesh.visible_instance_count=1;effect.hook_heads.multimesh.visible_instance_count=0;effect.refresh_bounds()
			expect(await frame_energy(viewport)>3.0,"Harpoon %d remains readable from the chase angle at %.0f m"%[id,distance])
			expect(white_pixels(viewport)==0,"Harpoon %d has no white glow obscuring its head"%id)
	effect.cables.multimesh.visible_instance_count=0;effect.hook_heads.multimesh.visible_instance_count=0
	for form in effect.modern_forms.values():form.hide()
	# A bright water background models the wash inside a headlight cone.
	# Additive-only effects can pass black-background tests while disappearing
	# here. Every supplied pigment must retain visible contrast.
	environment.environment.background_color=Color(.56,.70,.78)
	camera.position=Vector3(0,3,20);camera.look_at(Vector3.ZERO)
	for id in [16,6754,6755,6756,6760,6761,6762,6763,6764,6765,6766]:
		var shot=view.model(id,32,viewport,false);effect.shade_projectile(shot,id in [6760,6761,6762])
		await frame_energy(viewport)
		expect(contrast_pixels(viewport)>4,"Projectile %d remains distinct against bright headlight haze"%id)
		shot.queue_free();await process_frame
	for id in [3,4,5,15,16,17]:
		effect.ribbon_count=0;effect.hook_count=0;effect.effect_bounds.clear()
		if id<15:
			effect.ribbon(Vector3(0,0,-4),Vector3(0,0,4),.8,effect.coil_color(id),false,id-3)
			effect.ribbons.multimesh.visible_instance_count=1
		else:
			var hook:=Weapon.new();hook.equipment_id=id
			effect.hook_line(Vector3(0,0,5),Vector3.ZERO,hook)
			effect.cables.multimesh.visible_instance_count=1;effect.hook_heads.multimesh.visible_instance_count=0
		effect.refresh_bounds();await frame_energy(viewport)
		expect(contrast_pixels(viewport)>4,"Weapon %d remains distinct against bright headlight haze"%id)
		effect.ribbons.multimesh.visible_instance_count=0;effect.cables.multimesh.visible_instance_count=0;effect.hook_heads.multimesh.visible_instance_count=0
	view.camera=saved;viewport.queue_free();await process_frame

func contrast_pixels(viewport: SubViewport) -> int:
	var image:=viewport.get_texture().get_image();var background:=image.get_pixel(0,0);var result:=0
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			if maxf(absf(c.r-background.r),maxf(absf(c.g-background.g),absf(c.b-background.b)))>.12:result+=1
	return result

func white_pixels(viewport: SubViewport) -> int:
	var image:=viewport.get_texture().get_image();var result:=0
	for y in image.get_height():
		for x in image.get_width():
			var pixel:=image.get_pixel(x,y)
			if not is_finite(pixel.r+pixel.g+pixel.b) or minf(pixel.r,minf(pixel.g,pixel.b))>.94:result+=1
	return result

func check_mass_bolt(form, viewport: SubViewport, camera: Camera3D, environment: Environment) -> void:
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=30
	camera.position=Vector3(20,0,0);camera.look_at(Vector3.ZERO)
	environment.background_color=Color(.01,.03,.06)
	form.advance(.35,camera);await frame_energy(viewport)
	var frozen:=viewport.get_texture().get_image()
	var background:=frozen.get_pixel(0,0)
	var low:=Vector2i(192,192);var high:=Vector2i.ZERO
	var colored:=0;var visible:=0
	for y in frozen.get_height():
		for x in frozen.get_width():
			var pixel:=frozen.get_pixel(x,y)
			if maxf(absf(pixel.r-background.r),maxf(absf(pixel.g-background.g),absf(pixel.b-background.b)))<.12:continue
			low=low.min(Vector2i(x,y));high=high.max(Vector2i(x,y));visible+=1
			if pixel.s>.5:colored+=1
	var span:=high-low
	expect(span.x>60 and span.x>span.y*4,"Mass Driver %d draws a long, thin energy streak from the side"%form.equipment)
	expect(visible>0 and colored>visible*.9,"Mass Driver %d retains its supplied pigment throughout its energy trail"%form.equipment)
	expect(form.pieces.all(func(piece):return piece.material_override.shader!=form.SOLID),"Mass Driver %d has no metal projectile casing"%form.equipment)
	form.advance(.35,camera);await frame_energy(viewport)
	expect(frozen.get_data()==viewport.get_texture().get_image().get_data(),"Frozen Mass Driver %d retains the same energy texture"%form.equipment)
	form.advance(.75,camera);await frame_energy(viewport)
	expect(frozen.get_data()!=viewport.get_texture().get_image().get_data(),"Mass Driver %d energy texture advances with simulation time"%form.equipment)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE

func check_modern_forms(mass_colors: Dictionary) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(192,192);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;viewport.add_child(env)
	var camera:=Camera3D.new();viewport.add_child(camera)
	for id in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,42]:
		# Physical torpedoes retain the original world size rather than being
		# inflated to six pixels. Inspect them at a small phone's render height.
		viewport.size=Vector2i(384,384) if id in [12,13,14] else Vector2i(192,192)
		var pigment: Color=mass_colors.get(id,[Color("13c8ff"),Color("ffae14"),Color("e8273a")][id%3])
		var form=preload("res://native/presentation/weapon_form.gd").new();form.configure(id,pigment);viewport.add_child(form)
		for bright in [false,true]:
			env.environment.background_color=Color(.56,.70,.78) if bright else Color(.01,.03,.06)
			for at in [Vector3(0,8,60),Vector3(40,8,10)]:
				camera.position=at;camera.look_at(Vector3.ZERO);form.advance(.35,camera)
				await frame_energy(viewport)
				expect(contrast_pixels(viewport)>8,"Modern weapon %d has a readable silhouette at %s with bright water %s"%[id,at,bright])
				expect(white_pixels(viewport)==0,"Modern weapon %d has no white obscuring flash"%id)
				if id in [12,13,14]:
					# A visible wake can hide a missing physical projectile in a
					# whole-effect test. Inspect the metal alone on both backgrounds.
					for piece in form.pieces:piece.visible=piece.material_override.shader in [form.SOLID,form.TORPEDO]
					await frame_energy(viewport)
					expect(contrast_pixels(viewport)>8,"Weapon %d retains its physical body without the energy field at %s with bright water %s"%[id,at,bright])
					for piece in form.pieces:piece.show()
		if id in [9,10,11]:await check_mass_bolt(form,viewport,camera,env.environment)
		var rotation: Array=form.moving.map(func(m):return m.node.rotation)
		form.advance(.35,camera)
		expect(form.moving.map(func(m):return m.node.rotation)==rotation,"Frozen weapon %d does not animate on wall time"%id)
		# A scaled or tilted child mesh must never push a newborn wake back
		# inside the launcher. Check the rendered plane, not mesh-local bounds.
		env.environment.background_color=Color.BLACK
		form.position=Vector3(2,3,4);form.rotation.y=.73
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=30
		camera.position=form.position+form.basis.x.normalized()*60;camera.look_at(form.position)
		form.advance(.35,camera,0.0);await frame_energy(viewport)
		var center:=camera.unproject_position(form.position)
		var behind:=camera.unproject_position(form.position+form.basis.z.normalized()*10)
		var image:=viewport.get_texture().get_image();var leaked:=0
		for y in image.get_height():
			for x in image.get_width():
				if (x-center.x)*signf(behind.x-center.x)<=2:continue
				var c:=image.get_pixel(x,y)
				if maxf(c.r,maxf(c.g,c.b))>.02:leaked+=1
		expect(leaked==0,"Newborn weapon %d leaves no effect behind its launch plane"%id)
		expect(contrast_pixels(viewport)>0,"Launch-plane clipping preserves the visible front of weapon %d"%id)
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE;form.position=Vector3.ZERO;form.rotation=Vector3.ZERO;form.advance(.35,camera)
		# All surfaces obey ordinary scene depth, including the volume shells.
		env.environment.background_color=Color.BLACK;camera.position=Vector3(0,0,60);camera.look_at(Vector3.ZERO)
		var block:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(40,40,2);block.mesh=box;block.position.z=20
		var black:=StandardMaterial3D.new();black.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;black.albedo_color=Color.BLACK;block.material_override=black;viewport.add_child(block)
		expect(await frame_energy(viewport)<.001,"Modern weapon %d is occluded by a hull"%id)
		block.queue_free();form.queue_free();await process_frame
	viewport.queue_free();await process_frame
