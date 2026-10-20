extends RefCounted
## Collision volume, a box; escape uses its nearest face, including offset.
const Math=preload("res://native/simulation/fixed_math.gd")
var origin: Array=[0,0,0]
var offset: Array=[0,0,0]
var half_size: Array=[0,0,0]
## Escape straight away from the centre instead of through the nearest face,
## as a S.T.R.E.A.M. gate pushes a hull out (bb.a with at/cu).
var radial := false
## The box's own axes. Station parts and gates keep the world's; a hull that
## turns (a freighter) carries its own, so a long ship blocks along its
## length whichever way it heads, not across the water beside it.
var basis := Basis.IDENTITY
func to_local(point: Vector3) -> Vector3:
 return basis.transposed()*(point-Math.vector(origin))-Math.vector(offset)
func to_world(local: Vector3) -> Vector3:
 return Math.vector(origin)+basis*(local+Math.vector(offset))
## The box in its own frame, grown on every side by a hull's radius.
func local_box(radius: float=0.0) -> AABB:
 var half:=Math.vector(half_size)+Vector3.ONE*radius
 return AABB(-half,half*2.0)
func contains(point: Array) -> bool:
 var relative:=to_local(Math.vector(point))
 var extent:=Math.vector(half_size)
 return absf(relative.x)<extent.x and absf(relative.y)<extent.y and absf(relative.z)<extent.z
func avoidance_normal(point: Array) -> Array:
 var relative:=to_local(Math.vector(point))
 # The original adds 100 to x of the unit direction, which also gives a hull
 # at the very centre a way out.
 if radial:return Math.array(basis*(relative.normalized()*4096+Vector3(100,0,0)))
 var extent:=Math.vector(half_size)
 var axis:=0
 for candidate in range(1,3):
  if extent[candidate]-absf(relative[candidate])<extent[axis]-absf(relative[axis]):axis=candidate
 var direction:=Vector3.ZERO;direction[axis]=1 if relative[axis]>=0 else -1
 return Math.array(basis*direction*4096)
