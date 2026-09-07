extends RefCounted
## Cosmetic particles have their own random stream and elapsed-time movement.
var timer:=0
var life: Array=[]
var position: Array=[]
var rise: Array=[]
var scale: Array=[]
var visual_rng:=RandomNumberGenerator.new()
func _init() -> void:
 visual_rng.seed=811
 for index in 20:life.append(0);position.append([0,0,0]);rise.append(0);scale.append(0)
func advance(origin: Array,delta_ms: int,_gameplay_rng) -> void:
 timer+=delta_ms
 for index in life.size():
  if life[index]>0:
   life[index]=maxi(0,life[index]-delta_ms)
   position[index][1]-=roundi(rise[index]*delta_ms/1000.0)
   scale[index]=roundi(4096.0*life[index]/1800.0)
 if timer<120:return
 timer%=120
 var slot:=life.find(0)
 if slot<0:return
 life[slot]=1800;position[slot]=origin.duplicate();rise[slot]=visual_rng.randi_range(400,900);scale[slot]=4096
