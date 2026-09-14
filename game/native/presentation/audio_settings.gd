extends RefCounted
## One mix point per group. Cue-relative levels stay on their own players, so a
## volume setting moves the whole group without rewriting every cue's gain, and
## a muted group is genuinely silent rather than merely very quiet.
const MUSIC := "Abyssal Music"
const EFFECTS := "Abyssal Effects"

static func ensure_buses() -> void:
	for name in [MUSIC,EFFECTS]:
		if AudioServer.get_bus_index(name)>=0: continue
		var index := AudioServer.bus_count
		if OS.has_feature("web"):
			# add_bus() normalizes an appended index to -1, which reorders the
			# Web sample buses. Growing the count keeps them in place.
			AudioServer.bus_count=index+1
		else:
			AudioServer.add_bus()
		AudioServer.set_bus_name(index,name)
		AudioServer.set_bus_send(index,"Master")

static func level(name: String, gain: float) -> void:
	ensure_buses()
	var index := AudioServer.get_bus_index(name)
	if index<0: return
	var amount := clampf(gain,0.0,1.0) if is_finite(gain) else 1.0
	AudioServer.set_bus_mute(index,amount<=0.0)
	AudioServer.set_bus_volume_db(index,linear_to_db(amount) if amount>0.0 else 0.0)

static func apply(music_gain: float, effects_gain: float, enabled: bool=true) -> void:
	level(MUSIC,music_gain if enabled else 0.0)
	level(EFFECTS,effects_gain if enabled else 0.0)
