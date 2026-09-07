extends RefCounted
## Modular station collision derived from locally imported mesh bounds.
const Layout=preload("res://native/simulation/station_layout.gd")
const Shape=preload("res://native/simulation/collision_shape.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var parts: Array=[]
var shapes: Array=[]
var extent:=5000
var contact:=0
func configure(station: Dictionary,_colonist: bool,sine: Array,geometry: Dictionary={}) -> void:
 parts=Layout.new().generate(station.id,station.depth,station.tech,sine,geometry);shapes=[];extent=0
 for part in parts:
  var box: Dictionary=geometry.get(str(part.model_id),{"center":[0,0,0],"extent":[4000,4000,4000]})
  var rotation:=Basis(Vector3.UP,part.yaw*TAU/4096.0)
  var shape:=Shape.new();shape.origin=part.origin.duplicate();shape.offset=Math.array(rotation*Math.vector(box.center))
  var size:=Math.vector(box.extent)
  shape.half_size=Math.array(rotation.x.abs()*size.x+rotation.y.abs()*size.y+rotation.z.abs()*size.z)
  shapes.append(shape)
  for axis in 3:extent=maxi(extent,absi(shape.origin[axis]+shape.offset[axis])+shape.half_size[axis])
  # Station modules keep a stable pose; faction is conveyed by status/UI.
  part.animation_range=[0,0];part.frame_ms=100
 extent+=1000
func contains(point: Array) -> bool:
 for index in shapes.size():
  if shapes[index].contains(point):contact=index;return true
 return false
func avoidance_normal(point: Array) -> Array:return shapes[contact].avoidance_normal(point)
func can_dock(point: Array) -> bool:
 return Math.vector(point).length()<=16000 and not contains(point)
