extends Node3D
## Moving geometry and pumpjet wash follow rendered poses, independent of physics.
var visual
var moving: Array = []
var wakes: Array[GPUParticles3D] = []
var elapsed := 0.0
var throttle := 0.0
var opening := 0.0
var ship := false
func mesh_nodes(root_node: Node) -> Array:
	var result: Array=[]
	if root_node is MeshInstance3D: result.append(root_node)
	for child in root_node.get_children(): result.append_array(mesh_nodes(child))
	return result
func configure(model,id: int) -> void:
	visual=model;ship=id in range(12) or id==19
	for mesh in mesh_nodes(model):
		if str(mesh.name).contains("Motion_"):moving.append({"node":mesh,"rest":mesh.transform,"name":str(mesh.name)})
	if ship and DisplayServer.get_name()!="headless":
		for mount in model.get_meta("propellers",[]):
			var emitter := GPUParticles3D.new();model.add_child(emitter)
			emitter.top_level=true;emitter.set_meta("mount",mount.position);emitter.position=mount.position;emitter.amount=220;emitter.lifetime=1.9;emitter.local_coords=false;emitter.explosiveness=0
			emitter.visibility_aabb=AABB(Vector3(-80,-80,-100),Vector3(160,160,260));emitter.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var process := ParticleProcessMaterial.new();process.direction=Vector3.BACK;process.spread=9;process.gravity=Vector3(0,.20,0)
			process.initial_velocity_min=4;process.initial_velocity_max=10;process.scale_min=.3;process.scale_max=.85
			process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;process.emission_sphere_radius=maxf(.15,mount.radius*.35)
			var gradient := Gradient.new();gradient.offsets=PackedFloat32Array([0,.15,.6,1]);gradient.colors=PackedColorArray([Color(.52,.8,.88,0),Color(.60,.84,.90,.25),Color(.35,.60,.72,.12),Color(.20,.4,.5,0)])
			var ramp := GradientTexture1D.new();ramp.gradient=gradient;process.color_ramp=ramp
			var curve := Curve.new();curve.add_point(Vector2(0,.25));curve.add_point(Vector2(1,1));var size_curve := CurveTexture.new();size_curve.curve=curve;process.scale_curve=size_curve
			emitter.process_material=process
			var quad := QuadMesh.new();quad.size=Vector2.ONE*maxf(.25,mount.radius*.22)
			var material := ShaderMaterial.new();material.shader=preload("res://native/presentation/vessel_wake.gdshader");quad.material=material;emitter.draw_pass_1=quad
			emitter.emitting=false;wakes.append(emitter)
func animate(delta: float,power: float,gate_open: float=0.0) -> void:
	throttle=clampf(power,0,1);opening=gate_open;elapsed+=delta
	for entry in moving:
		var node: Node3D=entry.node;var rest: Transform3D=entry.rest
		if entry.name.contains("rotor"):
			var angle: float=float(node.get_meta("angle",0.0))+delta*(throttle*18.0 if ship else 1.5)
			node.set_meta("angle",angle);node.transform=rest*Transform3D(Basis(Vector3.BACK,angle),Vector3.ZERO)
		elif entry.name.contains("radar"):node.transform=rest*Transform3D(Basis(Vector3.UP,elapsed*.32),Vector3.ZERO)
		elif entry.name.contains("gate"):
			var radial := Vector3(rest.origin.x,rest.origin.y,0).normalized()
			node.transform=rest;node.position+=radial*opening*3.2
			node.rotate_object_local(Vector3.BACK,sin(elapsed*.7+rest.origin.x)*.035+opening*.28)
	for emitter in wakes:
		var valid_pose: bool=absf(visual.global_basis.determinant())>.00001
		if valid_pose: emitter.global_transform=Transform3D(visual.global_basis.orthonormalized(),visual.global_transform*Vector3(emitter.get_meta("mount")))
		# Dying source actors can collapse all three axes. World-space emitters
		# retain their last valid pose while existing wash particles dissipate.
		emitter.emitting=valid_pose and throttle>.025 and visual.is_visible_in_tree()
		emitter.amount_ratio=maxf(.05,throttle)
