extends RefCounted
## Tether fishing: steady focus builds progress; losing sight has a grace period.
## Collection is a transaction. Full holds preserve the target instead of eating it.
const Math=preload("res://native/simulation/fixed_math.gd")
const SpecialActor=preload("res://native/simulation/special_actor.gd")
const SIGHT_GRACE_MS := 1500
const BREAK_AFTER_MS := 5000
const MAX_LINE_LENGTH := 65000
var weapon
var player
var session
var target = null
var hooked := false
var towing := false
var original_hull := 0
var slow_percent := 0
var visible_to_camera: Callable
var audio_events: Array=[]
var tow_sound_started := false
var capture_distance := 900
var tow_speed := 12
var feedback: Array[String]=[]
var out_of_view_ms := 0
var progress_ms := 0.0

func detach(count_miss: bool) -> void:
 if target!=null:target.release();target.towing=false
 if count_miss:session.counters.i+=1
 target=null;hooked=false;towing=false;tow_sound_started=false;out_of_view_ms=0;progress_ms=0
 weapon.hooked_target=null;weapon.hook_busy=false;weapon.active=false;weapon.fired=false
 for index in weapon.remaining.size():weapon.remaining[index]=-1
func release() -> void:detach(true)
func attach(actor) -> void:
 target=actor;hooked=true;weapon.hook_busy=true;weapon.fired=false
 original_hull=actor.health.hull;out_of_view_ms=0;progress_ms=0
 if actor.is_creature and actor.state!=4:actor.hook(slow_percent)
 audio_event("harpoon_hit",actor.pose.origin)
func advance(delta_ms: int) -> void:
 if not hooked:
  weapon.advance(delta_ms)
  if weapon.hooked_target!=null:attach(weapon.hooked_target)
  return
 if weapon.fired:release();return
 if target==null:detach(false);return
 # The projectile has become a tether; don't re-run hit detection or damage.
 weapon.elapsed+=delta_ms
 var delta:=Vector3(player.pose.origin[0]-target.pose.origin[0],player.pose.origin[1]-target.pose.origin[1],player.pose.origin[2]-target.pose.origin[2])
 var distance:=delta.length()
 if distance>MAX_LINE_LENGTH:
  feedback.append("Line released · target out of range.");release();return
 var visible: bool=not visible_to_camera.is_valid() or visible_to_camera.call(target.pose.origin)
 out_of_view_ms=0 if visible else out_of_view_ms+delta_ms
 if out_of_view_ms>BREAK_AFTER_MS:
  feedback.append("Catch lost · keep the target in view.");release();return
 if target.is_creature and target.state!=4 and not target.subdued:
  if visible or out_of_view_ms<=SIGHT_GRACE_MS:
   var control_bonus:=1.0+clampf(float(slow_percent)/100.0,0,1)*.6
   progress_ms+=delta_ms*control_bonus
  target.struggle_remaining=maxi(0,target.struggle_total-roundi(progress_ms))
  if target.struggle_remaining==0:target.subdued=true
 var ready: bool=(target.is_creature and (target.subdued or target.state==4)) or (not target.is_creature and target.capturable and target.health.hull<=0)
 if target is SpecialActor and target.kind=="capsule" and target.capturable:ready=true
 if target.model_id==13:ready=true
 towing=ready;target.towing=ready
 weapon.positions[0]=target.pose.origin.duplicate()
 if not ready:return
 if not tow_sound_started:audio_event("tow",target.pose.origin);tow_sound_started=true
 if distance<=capture_distance:
  var collected: bool=target.capture(session)
  if not collected:feedback.append("Cannot collect catch · cargo hold is full.")
  detach(false);return
 var movement:=delta.normalized()*minf(distance,float(delta_ms*tow_speed))
 for axis in 3:target.pose.origin[axis]+=roundi(movement[axis])
 if target.is_creature:target.secondary_pose=target.pose.copy_pose()
 weapon.positions[0]=target.pose.origin.duplicate()
func audio_event(kind: String, position: Array) -> void:
 if audio_events.size()>=8:audio_events.pop_front()
 audio_events.append({"kind":kind,"position":position.duplicate()})
