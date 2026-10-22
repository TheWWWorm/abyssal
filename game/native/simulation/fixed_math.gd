extends RefCounted
## Fixed-unit data boundary backed by standard floating-point/vector operations.
## Q12 directions and depth units are retained for imported meshes and saves.
var sine_table: Array=[] # Accepted by existing content adapters; not used for math.
static func vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func array(value: Vector3) -> Array:return [roundi(value.x),roundi(value.y),roundi(value.z)]
static func i32(value: int) -> int:return ((value+2147483648)&0xffffffff)-2147483648
## Java float arithmetic. Inexact literals (1.3f, 0.7f) go through it too.
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
static func java_float_int(value: float) -> int:
 if is_nan(value):return 0
 return int(clampf(value,-2147483648,2147483647))
static func product(a: int,b: int) -> int:return roundi(float(a)*float(b)/4096.0)
func sine(angle: int) -> int:return roundi(sin(angle*TAU/4096.0)*4096)
func cosine(angle: int) -> int:return roundi(cos(angle*TAU/4096.0)*4096)
static func inverse_sqrt(value: int) -> int:return 0 if value<=0 else roundi(4096/sqrt(value/4096.0))
static func cross(a: Array,b: Array) -> Array:return array(vector(a).cross(vector(b))/4096.0)
static func normalized(value: Array) -> Array:return normalize_vector(value)
## dt.a(long): the original's Q12 square root, a 31-step binary search that
## settles on its own answer for small arguments. Station distances (cl.a/cl.b)
## and everything priced or stocked by them depend on its exact results.
static func source_sqrt(value: int) -> int:
 if value == 0: return 0
 var step := 2147483647
 var root := 2147483647
 for _i in 31:
  step >>= 1
  var error: int = value-((root*root) >> 12)
  if error > 0: root += step
  elif error < 0: root -= step
  else: return i32(root)
 return i32(root)
static func fixed_sqrt(value: int) -> int:return roundi(sqrt(maxf(0,float(value))*4096.0))
static func dot_long(a: Array,b: Array) -> int:return roundi(vector(a).dot(vector(b))/4096.0)
static func length_of(value: Array) -> int:return roundi(vector(value).length())
static func normalize_vector(value: Array) -> Array:return array(vector(value).normalized()*4096.0)
static func scaled(value: Array,factor: int) -> Array:return array(vector(value)*factor/4096.0)
static func added(a: Array,b: Array) -> Array:return [a[0]+b[0],a[1]+b[1],a[2]+b[2]]
static func subtracted(a: Array,b: Array) -> Array:return [a[0]-b[0],a[1]-b[1],a[2]-b[2]]
static func from_source(value: Array) -> Array:
 # Authored world positions, offsets and directions: the source has +Y up
 # and the opposite X axis. Native +Y is depth; +Z remains forward.
 # Model-local mesh vertices and native flight vectors have their own frame.
 return [-value[0],-value[1],value[2]]
## cl.b: float32 (depth-15000)/15000*100, truncated. Rounding would put a ship
## rated to a depth one percent deeper than the original, moving pressure and
## contract-destination checks at the band edges.
static func depth_percent(depth: int) -> int:return clampi(int(f32(f32(float(depth-15000)/15000.0)*100.0)),0,100)
static func depth_from_percent(percent: int) -> int:return 15000+percent*150
