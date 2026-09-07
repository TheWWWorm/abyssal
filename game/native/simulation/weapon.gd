extends RefCounted
## Bounded projectile pool with swept collision, real-time cooldown and homing.
const Math=preload("res://native/simulation/fixed_math.gd")
var damage := 0
var speed := 0.0
var lifetime := 0
var cooldown := 0
var elapsed := 0
var mount: Array=[0,0,0]
var positions: Array=[]
var velocities: Array=[]
var remaining: Array=[]
var targets: Array=[]
var impacts: Array=[]
var fired := false
var launch_serial := 0
var active := false
var special_kill := false
var equipment_kind := 0
var equipment_id := -1
var model_id := -1
var fishing := false
var fishing_radius := 0
var hooked_target = null
var hook_busy := false
var terrain_collision: Callable
var slow_percent := 0
var beam := false
var homing := false
var velocity_step_ms := 40
static func vector(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
static func coordinates(value: Vector3) -> Array:return [roundi(value.x),roundi(value.y),roundi(value.z)]
func configure(power: int,pool_size: int,life_ms: int,interval: int,units_per_ms: float,offset: Array) -> void:
 damage=maxi(0,power);lifetime=maxi(1,life_ms);cooldown=maxi(1,interval);speed=maxf(0,units_per_ms);mount=offset.duplicate()
 elapsed=cooldown # Newly equipped weapons are ready on the first press.
 positions.clear();velocities.clear();remaining.clear()
 for index in maxi(1,pool_size):positions.append([50000,50000,50000]);velocities.append([0,0,0]);remaining.append(-1)
func launch(pose,delta_ms: int,aim=null) -> bool:
 if fishing and hook_busy:return false
 for index in remaining.size():
  if remaining[index]>0:continue
  var start:=vector(pose.origin)+vector(pose.rotate_direction(mount))
  var direction:=vector(pose.forward) if aim==null else vector(aim if aim is Array else aim.pose.origin)-start
  # A chase-camera hit can be behind the muzzle when close to salvage, or
  # stale after a sharp turn. A forward-mounted hook cannot swivel sideways.
  if fishing and direction.normalized().dot(vector(pose.forward).normalized())<0.5:
   direction=vector(pose.forward)
  velocity_step_ms=maxi(1,delta_ms);positions[index]=coordinates(start);velocities[index]=launch_velocity(coordinates(direction),velocity_step_ms);remaining[index]=lifetime
  elapsed=0;fired=true;active=true;launch_serial+=1;return true
 return false
func launch_velocity(direction: Array,delta_ms: int) -> Array:
 return coordinates(vector(direction).normalized()*speed*maxi(1,delta_ms))
func request_fire(pose,delta_ms: int,aim=null) -> bool:
 return launch(pose,delta_ms,aim) if elapsed>=cooldown else false
func advance(delta_ms: int) -> void:
 elapsed+=maxi(0,delta_ms)
 if not active or hook_busy:return
 hooked_target=null
 for index in remaining.size():
  if remaining[index]<=0:continue
  var start:=vector(positions[index]);var direction:=vector(velocities[index]).normalized()
  if homing:
   var nearest=null;var squared:=45000.0*45000.0
   for actor in targets:
    if not actor.health.enabled or actor.health.hull<=0:continue
    var distance:=start.distance_squared_to(vector(actor.pose.origin))
    if distance<squared:squared=distance;nearest=actor
   if nearest!=null:direction=direction.lerp((vector(nearest.pose.origin)-start).normalized(),1.0-exp(-delta_ms*.0025)).normalized()
  var travel:=direction*speed*mini(delta_ms,remaining[index])
  var finish:=start+travel
  var hit=null;var hit_fraction:=1.0
  for actor in targets:
   if not actor.health.enabled or (fishing and not actor.capturable):continue
   var radius:=maxf(1,fishing_radius if fishing else actor.radius)
   var relative:=vector(actor.pose.origin)-start
   var closest:=clampf(relative.dot(travel)/maxf(.001,travel.length_squared()),0,1)
   if (relative-travel*closest).length_squared()<=radius*radius and (hit==null or closest<hit_fraction):hit=actor;hit_fraction=closest
  # Bounded segment samples prevent ordinary shots crossing station walls.
  var terrain_hit:=false
  if terrain_collision.is_valid():
   var samples:=clampi(ceili(travel.length()/800.0),1,64)
   for sample in range(1,samples+1):
    var fraction:=float(sample)/samples
    if fraction>hit_fraction:break
    if terrain_collision.call(coordinates(start+travel*fraction)):terrain_hit=true;hit=null;hit_fraction=fraction;break
  if hit!=null or terrain_hit:
   positions[index]=coordinates(start+travel*hit_fraction);remaining[index]=-1
   if hit!=null:
    if fishing:hooked_target=hit
    else:hit.health.damage(damage,"combined",special_kill)
   impacts.append({"target":hit,"position":positions[index].duplicate(),"direction":coordinates(direction*4096),"impulse":coordinates(-travel)})
  else:
   positions[index]=coordinates(finish);remaining[index]-=delta_ms
  velocities[index]=coordinates(direction*speed*velocity_step_ms)
 active=hooked_target!=null or remaining.any(func(value):return value>0)
func values() -> Array:return [elapsed,positions,velocities,remaining]
