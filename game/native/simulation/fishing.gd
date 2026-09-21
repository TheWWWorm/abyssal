extends RefCounted
## The harpoon line, as the phone game runs it (cx): a hit hooks the catch
## and sets it running; the creature's own fight decides when it is subdued,
## and it is lost the moment it is hurt or the helm turns away from it.
## Subdued, dead or wrecked, it is drawn in at ten units a millisecond and
## taken aboard at four metres. A second press of the hook lets a catch go.
const Math=preload("res://native/simulation/fixed_math.gd")
const SpecialActor=preload("res://native/simulation/special_actor.gd")
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
var capture_distance := 400
var tow_speed := 10
var feedback: Array[String]=[]

func detach(count_miss: bool) -> void:
	if target!=null:target.release();target.towing=false
	# Every catch that gets away, let go or lost, is one the log counts.
	if count_miss:session.counters.i+=1
	target=null;hooked=false;towing=false;tow_sound_started=false
	weapon.hooked_target=null;weapon.hook_busy=false;weapon.active=false;weapon.fired=false
	for index in weapon.remaining.size():weapon.remaining[index]=-1

func release() -> void:detach(true)

func attach(actor) -> void:
	target=actor;hooked=true;weapon.hook_busy=true;weapon.fired=false
	original_hull=actor.health.hull
	if actor.is_creature and actor.state!=4:actor.hook(slow_percent)
	audio_event("harpoon_hit",actor.pose.origin)

func ready_to_tow() -> bool:
	if target.is_creature:return target.subdued or target.state==4
	if target.model_id==13:return true
	if target is SpecialActor and target.kind=="capsule":return target.capturable
	return target.capturable and target.state in [3,4]

func advance(delta_ms: int) -> void:
	if not hooked:
		weapon.advance(delta_ms)
		if weapon.hooked_target!=null:attach(weapon.hooked_target)
		return
	if weapon.fired:release();return
	if target==null:detach(false);return
	# The shot has become a line; it neither flies on nor strikes again.
	weapon.elapsed+=delta_ms
	weapon.positions[0]=target.pose.origin.duplicate()
	var visible: bool=not visible_to_camera.is_valid() or visible_to_camera.call(target.pose.origin)
	if target.health.hull<original_hull:
		feedback.append("Catch lost · target was damaged.");release();return
	if target.is_creature and not target.subdued and not visible:
		feedback.append("Catch lost · keep the target in view until subdued.");release();return
	var ready := ready_to_tow()
	towing=ready;target.towing=ready
	if not ready:return
	if not tow_sound_started:audio_event("tow",target.pose.origin);tow_sound_started=true
	var line: Array=Math.subtracted(player.pose.origin,target.pose.origin)
	var distance: int=Math.length_of(line)
	if distance<=capture_distance:
		var collected: bool=target.capture(session)
		if not collected:feedback.append("Cannot collect catch · cargo hold is full.")
		# A wreck or a mine is spent by the attempt either way; a creature that
		# would not fit stays on the water, off the line.
		detach(false);return
	target.pose.origin=Math.added(target.pose.origin,Math.scaled(Math.normalize_vector(line),mini(maxi(0,distance-capture_distance),delta_ms*tow_speed)))
	if target.is_creature:
		# Re-pose the tail on the moved body. Then the catch is drawn into the
		# hull: cx shrinks it with the line's length over its last 2048 units,
		# a fifth of its size by the time it is taken.
		target.animate()
		var swallow:=clampf((distance-capture_distance+400)*2.0/4096.0,0.0,1.0)
		for axis in 3:target.render_scale[axis]=roundi(target.render_scale[axis]*swallow);target.secondary_scale[axis]=roundi(target.secondary_scale[axis]*swallow)
	weapon.positions[0]=target.pose.origin.duplicate()

func audio_event(kind: String, position: Array) -> void:
	if audio_events.size()>=8:audio_events.pop_front()
	audio_events.append({"kind":kind,"position":position.duplicate()})
