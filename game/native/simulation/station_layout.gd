extends RefCounted
## Join imported habitable modules by their measured faces. Fixed station pose:
## animation frames include alternate emblems/configurations, not an idle loop.
var rng:=RandomNumberGenerator.new()
var geometry: Dictionary={}
const SEAM_OVERLAP:=80.0
func generate(station_id: int,depth: int,tech: int,_sine_table: Array,bounds: Dictionary={}) -> Array:
 geometry=bounds
 rng.seed=station_id*7919+depth*17+tech*101
 var variant:=posmod(station_id,2)
 var design:=posmod(station_id,6)
 var high_capacity:=tech>=6 and design in [2,5]
 # The rectangular hangar provides usable side sockets. The triangular
 # hangar's bounds include an apron, so it cannot serve as a three-way hub.
 var core:=part(3308,Vector3.ZERO,2048)
 var parts: Array=[core]
 # Habitable blocks already include roofs and floors. Separate top/bottom assets
 # are incompatible with these footprints and must not float above/below them.
 var arms: Array=[-1024,1024] if design==0 else ([-1024,0] if design==1 else ([-1024,1024,0] if design==2 else [0]))
 for angle in arms:
  var direction:=Vector3(sin(angle*TAU/4096.0),0,cos(angle*TAU/4096.0))
  var bridge:=attach(core,3302 if design in [1,3] else 3301,angle,direction)
  var habitat:=attach(bridge,3305+variant,angle,direction)
  parts.append(bridge);parts.append(habitat)
  if design in [1,2]:
   # Engine/vent module plugs into the outward habitat face. Its complete
   # imported assembly supplies the machinery; no detached decorative caps.
   # Its open mounting socket is +Z: turn that end toward the habitat.
   parts.append(attach(habitat,3304,angle+2048,direction))
  elif design==3:
   parts.append(attach(habitat,3309,angle+2048,direction))
 # Stacked industrial blocks share the same footprint. Their imported beveled
 # roof/floor rims seat 5 m inside each bounding face, so stack by the wall
 # height rather than leaving a gap between the bevels' extreme points.
 if design in [2,3,4,5] or high_capacity:
  var tower:=core
  var levels:=clampi(tech-2,3,8) if high_capacity else (2 if design in [3,5] else 1)
  for level in levels:
   tower=attach(tower,3305+variant,core.yaw,Vector3.DOWN,1000.0)
   parts.append(tower)
   if high_capacity:
    var direction:=Vector3.RIGHT if level%2==0 else Vector3.LEFT
    var angle:=1024 if level%2==0 else -1024
    var bridge:=attach(tower,3301,angle,direction)
    var habitat:=attach(bridge,3305+variant,angle,direction)
    parts.append(bridge);parts.append(habitat)
    if level%2==0:parts.append(attach(habitat,3304,angle+2048,direction))
  if design in [2,5]:parts.append(attach(core,3305+variant,core.yaw,Vector3.UP,1000.0))
  if design in [4,5]:
   var direction:=Vector3.RIGHT if design==4 else Vector3.LEFT
   var angle:=1024 if design==4 else -1024
   var bridge:=attach(tower,3301,angle,direction)
   var habitat:=attach(bridge,3305+variant,angle,direction)
   parts.append(bridge);parts.append(habitat)
   parts.append(attach(habitat,3304,angle+2048,direction))
 return parts
func measured(entry: Dictionary) -> AABB:
 var box: Dictionary=geometry.get(str(entry.model_id),{"center":[0,0,0],"extent":[4000,2250,4000]})
 var center:=Vector3(box.center[0],box.center[1],box.center[2])
 var size:=Vector3(box.extent[0],box.extent[1],box.extent[2])
 var rotation:=Basis(Vector3.UP,entry.yaw*TAU/4096.0)
 var half:=rotation.x.abs()*size.x+rotation.y.abs()*size.y+rotation.z.abs()*size.z
 center=rotation*center+Vector3(entry.origin[0],entry.origin[1],entry.origin[2])
 return AABB(center-half,half*2)
func attach(parent: Dictionary,id: int,yaw: int,direction: Vector3,overlap: float=SEAM_OVERLAP) -> Dictionary:
 var child:=part(id,Vector3.ZERO,yaw)
 var a:=measured(parent);var b:=measured(child)
 var spacing: float=(a.size*.5+b.size*.5).dot(direction.abs())-overlap
 var center:=a.get_center()+direction*spacing
 child.origin=point(center-b.get_center())
 if direction.y!=0:
  # Hangar bounds include a projecting apron; stack on its shared hull origin.
  child.origin[0]=parent.origin[0];child.origin[2]=parent.origin[2]
 return child
func point(value: Vector3) -> Array:return [roundi(value.x),roundi(value.y),roundi(value.z)]
func part(id: int,position: Vector3,yaw: int) -> Dictionary:return {"model_id":id,"yaw":yaw,"origin":point(position),"upper":false}
