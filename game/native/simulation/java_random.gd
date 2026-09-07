extends RefCounted
## Native engine RNG. Filename and state property preserve the save/API boundary;
## this deliberately does not reproduce java.util.Random sequences.
var generator:=RandomNumberGenerator.new()
var state: int:
 get:return generator.state
 set(value):generator.state=value
func seed_from(value: int) -> void:generator.seed=value
func next_int(bound: int) -> int:
 assert(bound>0)
 return generator.randi_range(0,bound-1)
