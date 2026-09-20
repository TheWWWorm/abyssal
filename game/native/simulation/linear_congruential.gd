extends RefCounted
## The 48-bit linear congruential generator of java.util.Random. Stations grow
## from a seed the original derives from the station record, and their shape
## is the sequence this generator produces from it; the rest of the simulation
## uses the engine's own generator (java_random.gd).
var state: int = 0
const MASK := (1 << 48)-1

func seed_from(value: int) -> void:
	state = (value ^ 0x5deece66d) & MASK

func next_bits(bits: int) -> int:
	# Split the multiplication so a signed 64-bit product cannot overflow
	# before the mask is applied.
	var low := (state & 0xffffff)*0x5deece66d+11
	var high := ((state >> 24)*0x5deece66d) & 0xffffff
	state = (low+(high << 24)) & MASK
	return state >> (48-bits)

func next_int(bound: int) -> int:
	assert(bound > 0)
	if (bound & -bound) == bound: return (bound*next_bits(31)) >> 31
	while true:
		var bits := next_bits(31)
		var value := bits % bound
		if bits-value+(bound-1) <= 2147483647: return value
	return 0
