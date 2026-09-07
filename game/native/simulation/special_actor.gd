extends "res://native/simulation/npc.gd"
## Simple hazard, rescue and transport lifecycle. Destroyed objects stay destroyed.
var kind := "debris"
var moving := false
var timer := 0
var acceleration := 0
var trigger_delta: Array=[0,0,0]
var mine_yaw := 0
var animation_range: Array=[]
func configure_special(type_name: String,id: int,enemy: bool,location: Array,data: Dictionary,source_rng) -> void:
 kind=type_name;model_id=id;original_model_id=id;hostile=enemy;rng=source_rng
 pose.math.sine_table=data.constants.dt["a:[S"];set_position(location)
 capturable=kind=="capsule";state=0
 if kind=="mine":animation_range=[0,0]
func set_position(location: Array) -> void:
 super.set_position(location)
 for shape in shapes:shape.origin=location.duplicate()
func reset_capsule() -> void:
 # Explicit reset exists for fixtures; normal gameplay never recycles a loss.
 state=0;health.enabled=true;health.hull=health.max_hull;pose.origin=origin.duplicate()
func detonate() -> void:
 if state in [3,4]:return
 for actor in targets:
  if actor.health.enabled and within(actor.pose.origin,pose.origin,4200):actor.health.damage(25)
 health.hull=0;begin_destruction()
func begin_destruction() -> void:
 if state in [3,4]:return
 state=3;health.enabled=false;explosion_ms=0
 events.append("capsule_destroyed" if kind=="capsule" else "debris_destroyed" if kind=="debris" else "killed")
func capture(session) -> bool:
 if kind=="mine":detonate();return true
 if kind=="capsule" and state not in [3,4]:
  session.credits+=100;state=4;health.enabled=false;capturable=false;events.append("rescued");return true
 return false
func advance(delta_ms: int) -> void:
 if state==4:return
 if health.hull<=0:begin_destruction()
 if state==3:
  explosion_ms+=delta_ms
  if explosion_ms>=explosion_duration:state=4
  return
 timer+=delta_ms
 match kind:
  "mine":
   if state==0 and targets.any(func(actor):return actor.health.enabled and within(actor.pose.origin,pose.origin,5500)):
    state=1;timer=0;animation_range=[1,1]
   if state==1:
    pose.set_euler(0,roundi(timer*.3),0)
    if timer>=2000:detonate()
  "capsule":
   if not towing:pose.origin[1]+=roundi(delta_ms*.3)
   if pose.origin[1]-origin[1]>60000:health.hull=0;begin_destruction()
  "freighter":
   if moving and not towing:pose.advance(roundi(delta_ms*.7))
   for shape in shapes:shape.origin=pose.origin.duplicate()
func contains(point: Array) -> bool:
 return kind=="freighter" and state not in [3,4] and shapes.any(func(shape):return shape.contains(point))
