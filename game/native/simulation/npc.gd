extends RefCounted
## Predictable steering AI: nearest-target selection, stand-off combat and salvage.
const Math = preload("res://native/simulation/fixed_math.gd")
const Transform = preload("res://native/simulation/ship_transform.gd")
const Health = preload("res://native/simulation/health.gd")
const Goods = preload("res://native/simulation/goods.gd")
var pose := Transform.new()
var health := Health.new()
var radius := 2000
var model_id := 0
var original_model_id := 0
var faction := 0
var hostile := false
var excluded_from_objectives := false
var state := 0
var targets: Array = []
var weapons: Array = []
var shapes: Array = []
var obstacle_groups: Array = []
var route = null
var player = null
var rng
var base_speed := 2.1
var base_turn := 2.0
var speed := 2.1
var turn_speed := 2.0
var smart_boost := false
var boost_timer := 0
var boost_duration := 0
var target_timer := 0
var target_index := 0
var target_lock := false
var straight := false
var following := false
var target = null
var target_position: Array = [0,0,0]
var collision_enabled := true
var origin: Array = [0,0,0]
var capturable := true
var protected_target := false
var escaped := false
var towing := false
var subdued := false
var is_creature := false
var render_scale: Array = [4096,4096,4096]
var loot = null
var explosion_ms := 0
var explosion_duration := 4000
var explosion_delays: Array = [0]
var explosion_offsets: Array = [[0,0,0]]
var has_explosion := true
var events: Array = []
var trail := preload("res://native/simulation/bubble_trail.gd").new()

func configure(id: int, team: int, enemy: bool, location: Array, data: Dictionary, _chapter: int, source_rng) -> void:
 model_id=id;original_model_id=id;faction=team;hostile=enemy;rng=source_rng
 pose.math.sine_table=data.constants.dt["a:[S"];set_position(location)
 capturable=id!=19;speed=2.4;base_speed=speed;turn_speed=1.8
 var candidates: Array=[];var weights: Array=[];var weight_sum:=0
 for row in data.tables.goods:
  var weight:=maxi(0,int(row[4]))
  if weight==0:continue
  weight_sum+=weight;candidates.append(row);weights.append(weight_sum)
 if weight_sum>0:
  var draw: int=rng.next_int(weight_sum)
  for index in candidates.size():
   if draw<weights[index]:
    loot=Goods.new();loot.configure(candidates[index]);loot.owned=1+rng.next_int(3);loot.price=loot.maximum_price;break
static func within(a: Array,b: Array,distance: int) -> bool:
 return Vector3(a[0]-b[0],a[1]-b[1],a[2]-b[2]).length_squared()<float(distance)*distance
static func vector(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
static func coordinates(value: Vector3) -> Array:return [roundi(value.x),roundi(value.y),roundi(value.z)]
func dormant() -> void:state=5;health.enabled=false
func activate() -> void:state=1;health.enabled=true
func protect(value: bool) -> void:
 protected_target=value
 if value:loot=null
func rescued() -> bool:return protected_target and not capturable
func set_position(value: Array) -> void:
 pose.origin=value.duplicate();origin=value.duplicate()
func set_speed(value: int) -> void:speed=value;base_speed=value
func release() -> void:pass
func hook(_slow: int) -> void:pass
func capture(session) -> bool:
 if protected_target:
  state=4;capturable=false;health.enabled=false;events.append("rescued");return true
 if loot==null:state=4;capturable=false;health.enabled=false;return true
 if not session.ship.can_carry(loot.owned):events.append("cargo_full");return false
 session.ship.set_cargo(Goods.merge(session.ship.cargo,[loot]));session.counters.r+=1
 state=4;capturable=false;health.enabled=false;events.append("salvaged");return true
func choose_target(delta_ms: int) -> void:
 target_timer+=delta_ms
 if target!=null and (not target.health.enabled or target.health.hull<=0):target=null
 if target_timer>=500 or target==null:
  target_timer=0
  var best_distance:=float(65000*65000)
  var best=target
  if best!=null:best_distance=vector(best.pose.origin).distance_squared_to(vector(pose.origin))*.8
  for candidate in targets:
   if not candidate.health.enabled or candidate.health.hull<=0:continue
   var distance:=vector(candidate.pose.origin).distance_squared_to(vector(pose.origin))
   if distance<best_distance:best=candidate;best_distance=distance
  target=best
 following=false
 if target!=null:target_position=target.pose.origin.duplicate()
 elif route!=null:
  route.advance(pose.origin)
  if route.current()!=null:target_position=route.current().duplicate();following=true
func advance(delta_ms: int) -> void:
 if not capturable and state==4:health.enabled=false;return
 if health.hull<=0 and state not in [3,4]:
  state=3;explosion_ms=0;events.append("killed");collision_enabled=false
  if capturable:model_id=17;origin=pose.origin.duplicate()
 if state==3:
  explosion_ms+=delta_ms
  if explosion_ms>=explosion_duration:state=4
  return
 if state==4:
  if capturable and health.enabled and not towing:
   target_timer+=delta_ms;pose.origin[1]-=roundi(delta_ms*.15)
   if target_timer>120000:escaped=true;health.enabled=false
  return
 choose_target(delta_ms)
 if state==5:
  if player!=null and within(player.pose.origin,pose.origin,55000):activate()
  else:return
 if target==null and not following:return
 var difference:=vector(target_position)-vector(pose.origin)
 var distance:=difference.length()
 var desired:=difference.normalized()
 # Hold a firing distance while keeping the nose on target. A tangential
 # orbit here prevented the weapon alignment test from ever becoming true.
 var movement := speed
 if target!=null:movement*=clampf((distance-8000.0)/6000.0,-.45,1.0)
 # Avoid compound station volumes before committing the next movement step.
 var next_point:=coordinates(vector(pose.origin)+desired*movement*delta_ms)
 for obstacle in obstacle_groups:
  if obstacle.contains(next_point):desired=vector(obstacle.avoidance_normal(next_point)).normalized();break
 var facing:=vector(pose.forward).normalized()
 var turn_axis := facing.cross(desired)
 if turn_axis.length_squared()<.000001:turn_axis=vector(pose.up).normalized()
 var angle := acos(clampf(facing.dot(desired),-1,1))
 facing=facing.rotated(turn_axis.normalized(),minf(angle,turn_speed*delta_ms/1000.0)).normalized()
 if facing.length_squared()<.001:facing=desired
 pose.face(coordinates(facing*4096.0));pose.advance(roundi(delta_ms*movement))
 for shape in shapes:shape.origin=pose.origin.duplicate()
 if target!=null and distance<38000 and facing.dot(difference.normalized())>.965:
  for weapon in weapons:weapon.request_fire(pose,delta_ms,target)
 trail.advance(pose.origin,delta_ms,rng)
func contains(point: Array) -> bool:
 return state not in [3,4] and shapes.any(func(shape):return shape.contains(point))
func avoidance_normal(point: Array) -> Array:
 return shapes[0].avoidance_normal(point) if not shapes.is_empty() else [0,0,0]
