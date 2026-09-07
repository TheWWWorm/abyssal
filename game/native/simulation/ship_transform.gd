extends RefCounted
## Orthonormal Godot basis with explicit conversion at the fixed-unit boundary.
const Math=preload("res://native/simulation/fixed_math.gd")
var math:=Math.new()
var right: Array=[4096,0,0]
var up: Array=[0,4096,0]
var forward: Array=[0,0,4096]
var origin: Array=[0,0,0]
func basis() -> Basis:return Basis(Math.vector(right)/4096.0,Math.vector(up)/4096.0,Math.vector(forward)/4096.0).orthonormalized()
func assign(value: Basis) -> void:
 value=value.orthonormalized();right=Math.array(value.x*4096);up=Math.array(value.y*4096);forward=Math.array(value.z*4096)
func set_euler(pitch: int,yaw: int,roll: int) -> void:assign(Basis.from_euler(Vector3(pitch,yaw,roll)*TAU/4096.0,EULER_ORDER_XYZ))
func rotate_direction(value: Array) -> Array:return Math.array(basis()*Math.vector(value))
func face(direction: Array) -> void:
 var target:=Math.vector(direction).normalized()
 if target.length_squared()<.5:return
 var reference:=Vector3.UP if absf(target.dot(Vector3.UP))<.995 else Vector3.RIGHT
 var x:=reference.cross(target).normalized()
 assign(Basis(x,target.cross(x),target))
func compose_rotation(other) -> void:assign(basis()*other.basis())
func copy_pose():
 var result=get_script().new();result.origin=origin.duplicate();result.assign(basis());return result
func auto_level(delta_ms: int) -> void:
 var before:=basis();var target:=Math.vector(forward).normalized()
 if absf(target.y)>.99:return
 var x:=Vector3.UP.cross(target).normalized()
 # Retain the nearest upright OR inverted horizon after releasing the controls.
 # A half-loop must not turn into an unsolicited half-roll.
 if x.dot(before.x)<0:x=-x
 var authority:=1.0-smoothstep(.85,.99,absf(target.y))
 assign(before.slerp(Basis(x,target.cross(x),target),1-exp(-delta_ms*.002*authority)))
func advance(distance: int) -> void:origin=Math.array(Math.vector(origin)+basis().z*distance)
func strafe(distance: int) -> void:origin=Math.array(Math.vector(origin)+basis().x*distance)
func rotate_vector(value: Array,axis: Array,angle: int) -> Array:
 var normal:=Math.vector(axis).normalized()
 return value.duplicate() if normal.length_squared()<.5 else Math.array(Basis(normal,angle*TAU/4096.0)*Math.vector(value))
func rotate_local(axis: String,angle: int) -> void:
 var local_axis: Vector3={"pitch":Vector3.RIGHT,"yaw":Vector3.UP,"roll":Vector3.BACK}.get(axis,Vector3.ZERO)
 if local_axis!=Vector3.ZERO:assign(basis()*Basis(local_axis,angle*TAU/4096.0))
func values() -> Array:return [right[0],up[0],forward[0],origin[0],right[1],up[1],forward[1],origin[1],right[2],up[2],forward[2],origin[2]]
func godot_transform() -> Transform3D:return preload("res://scripts/model_library.gd").matrix(values(),true)
