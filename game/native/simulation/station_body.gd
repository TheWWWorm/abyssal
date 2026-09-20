extends RefCounted
## Modular station collision derived from locally imported mesh bounds.
const Layout=preload("res://native/simulation/station_layout.gd")
const Shape=preload("res://native/simulation/collision_shape.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var parts: Array=[]
var shapes: Array=[]
var extent:=5000
var contact:=0
func configure(station: Dictionary,colonist: bool,sine: Array,geometry: Dictionary={}) -> void:
 parts=Layout.new().generate(station.id,Layout.seed_depth(station.percent),station.tech,sine);shapes=[];extent=0
 for part in parts:
  # The generator keeps the original's numbers in the original's frame:
  # +y up (the top cap at +4500 over the hangar, the habitats hanging below)
  # and the other hand's x. This simulation's +y is deeper and its x runs
  # the other way (the depth gauge, the models and the render all agree), so
  # the layout is turned over and mirrored here, not in the generator, with
  # each part's yaw reversed to match. Left as it was, every station stood
  # on its head, caps swapped, and its branches grew out of the wrong side
  # of the hangar compared with the phone game.
  part.origin[0]=-int(part.origin[0]);part.origin[1]=-int(part.origin[1])
  part.yaw=(4096-int(part.yaw))%4096
  var box: Dictionary=geometry.get(str(part.model_id),{"center":[0,0,0],"extent":[4000,4000,4000]})
  var rotation:=Basis(Vector3.UP,part.yaw*TAU/4096.0)
  # The module is drawn turned half a turn about its socket axis (see the
  # presentation's STATION_ROLL); its measured box centre turns with it.
  var center: Vector3=Math.vector(box.center);center=Vector3(-center.x,-center.y,center.z)
  var shape:=Shape.new();shape.origin=part.origin.duplicate();shape.offset=Math.array(rotation*center)
  var size:=Math.vector(box.extent)
  shape.half_size=Math.array(rotation.x.abs()*size.x+rotation.y.abs()*size.y+rotation.z.abs()*size.z)
  shapes.append(shape)
  for axis in 3:extent=maxi(extent,absi(shape.origin[axis]+shape.offset[axis])+shape.half_size[axis])
  part.animation_range=Layout.animation_range(int(part.model_id),colonist);part.frame_ms=Layout.frame_interval(int(part.model_id))
 extent+=1000
func contains(point: Array) -> bool:
 for index in shapes.size():
  if shapes[index].contains(point):contact=index;return true
 return false
func avoidance_normal(point: Array) -> Array:return shapes[contact].avoidance_normal(point)
func can_dock(point: Array) -> bool:
 return Math.vector(point).length()<=16000 and not contains(point)
