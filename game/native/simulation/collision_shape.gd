extends RefCounted
## Axis-aligned collision volume; escape uses its nearest face, including offset.
const Math=preload("res://native/simulation/fixed_math.gd")
var origin: Array=[0,0,0]
var offset: Array=[0,0,0]
var half_size: Array=[0,0,0]
func contains(point: Array) -> bool:
 var relative:=Math.vector(point)-Math.vector(origin)-Math.vector(offset)
 var extent:=Math.vector(half_size)
 return absf(relative.x)<extent.x and absf(relative.y)<extent.y and absf(relative.z)<extent.z
func avoidance_normal(point: Array) -> Array:
 var relative:=Math.vector(point)-Math.vector(origin)-Math.vector(offset)
 var extent:=Math.vector(half_size)
 var axis:=0
 for candidate in range(1,3):
  if extent[candidate]-absf(relative[candidate])<extent[axis]-absf(relative[axis]):axis=candidate
 var direction:=Vector3.ZERO;direction[axis]=1 if relative[axis]>=0 else -1
 return Math.array(direction*4096)
