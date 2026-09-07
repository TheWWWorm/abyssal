extends RefCounted
## Habitat-bound wildlife with continuous motion. Fishing owns struggle progress.
const Math = preload("res://native/simulation/fixed_math.gd")
const Transform = preload("res://native/simulation/ship_transform.gd")
const Health = preload("res://native/simulation/health.gd")
var pose := Transform.new()
var turn := Transform.new()
var secondary_pose := Transform.new()
var health := Health.new()
var radius := 1500
var model_id := 0
var secondary_model := -1
var species := 0
var is_creature := true
var base_mass := 0
var resistance := 0
var mass := 0
var state := 0
var stationary := false
var constrained := false
var phase := 0
var struggle_total := 0
var struggle_remaining := 0
var struggle_time := 0
var speed := 1.0
var previous_hull := 0
var fleeing := false
var hooked := false
var subdued := false
var towing := false
var capturable := true
var meat := false
var render_scale: Array = [4096,4096,4096]
var secondary_scale: Array = [4096,4096,4096]
var events: Array = []

var habitat_center: Array=[]
var heading_time := 0.0
func configure(id: int,row: Array,rng,sine: Array,center: Array=[0,0,0]) -> void:
 model_id=id;species=int(row[0]);base_mass=int(row[1]);resistance=int(row[2])
 pose.math.sine_table=sine;turn.math.sine_table=sine
 mass=maxi(1,roundi(base_mass*(.85+float(rng.next_int(31))*.01)))
 health.configure(maxi(10,base_mass*2),0,0);previous_hull=health.hull
 stationary=id in [4443,4444,4445,4446,4447]
 habitat_center=center.duplicate();pose.origin=center.duplicate()
 speed=clampf(1.2+resistance*.08,1.2,3.5)
 heading_time=rng.next_int(628)/100.0
 pose.face([roundi(sin(heading_time)*4096),0,roundi(cos(heading_time)*4096)])
 struggle_total=clampi(3000+resistance*180,3000,12000)
 if id in [4424,4427,4430,4432,4434,4440,4436,4438]:secondary_model=id+1
 secondary_pose=pose.copy_pose();release()
func release() -> void:
 struggle_remaining=struggle_total;struggle_time=0;fleeing=false;hooked=false
 if state!=4:subdued=false
func hook(_slow_percent: int) -> void:
 hooked=true;fleeing=true;struggle_time=0
func countdown() -> int:return ceili(float(struggle_remaining)/1000.0)
func capture(session) -> bool:
 if not session.ship.can_carry(mass):events.append("cargo_full");return false
 if state==4:
  session.counters.p+=mass;session.ship.set_cargo(preload("res://native/simulation/goods.gd").merge(session.ship.cargo,[session.make_goods(18,mass)]));events.append("meat_collected")
 elif not session.register_catch(species,mass):events.append("cargo_full");return false
 else:events.append("caught")
 health.enabled=false;capturable=false;render_scale.fill(0);secondary_scale.fill(0);events.append("depleted");return true
func advance(delta_ms: int,_rng,_camera_origin: Array) -> void:
 if not health.enabled:return
 if health.hull<=0 and state!=4:
  state=4;model_id=14;secondary_model=-1;meat=true;mass=maxi(1,mass/3);events.append("killed");return
 if state==4:
  if not towing:pose.origin[1]+=roundi(delta_ms*.1)
  secondary_pose=pose.copy_pose();return
 if not stationary and not subdued and not towing:
  heading_time+=delta_ms*.0002
  var current:=Vector3(pose.origin[0],pose.origin[1],pose.origin[2])
  var home:=Vector3(habitat_center[0],habitat_center[1],habitat_center[2])
  var desired:=Vector3(sin(heading_time),sin(heading_time*.6)*.08,cos(heading_time))
  if not constrained and current.distance_squared_to(home)>18000.0*18000.0:desired=(home-current).normalized()
  if not constrained:
   var forward:=Vector3(pose.forward[0],pose.forward[1],pose.forward[2]).normalized().lerp(desired.normalized(),1.0-exp(-delta_ms*.001)).normalized()
   pose.face([roundi(forward.x*4096),roundi(forward.y*4096),roundi(forward.z*4096)])
  pose.advance(roundi(delta_ms*speed*(.35 if hooked else 1.0)))
 phase=(phase+delta_ms)%6284;animate()
func animate() -> void:
 secondary_pose=pose.copy_pose()
 if secondary_model>=0:
  var wave:=roundi(sin(phase*.006)*28)
  var fin:=Transform.new();fin.math.sine_table=pose.math.sine_table;fin.set_euler(0,wave,0);secondary_pose.compose_rotation(fin)
