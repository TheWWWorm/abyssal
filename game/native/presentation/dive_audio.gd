extends AudioStreamPlayer
## Source cue meanings and priority windows; bounded desktop playback. Imported
## AMR/MIDI conversions stay in the owner's cache. Fallback PCM is code-authored.
const SPECS := {
	"sonar":["echolot.amr",0,1300], "tow":["traktor.amr",95,2500],
	"message":["message.amr",100,1100], "gate":["gate.amr",100,3000],
	"pressure":["alert.amr",100,1400], "harpoon":["harpoon.amr",90,900],
	"explosion":["explosion.amr",100,2800], "boost":["turbo.amr",100,3200],
	"water":["water.amr",0,2800], "creature_death":["tiertot.amr",100,1000],
	"signal":["signal.amr",100,1000], "mine":["mine.amr",80,300],
	"ambient_a":["amb02.amr",80,1500], "ambient_b":["amb03.amr",80,1500],
	"harpoon_hit":["harpoon_hit.amr",90,150], "beep":["beep.amr",80,90],
	"shot":["",40,200], "beam":["",40,300], "torpedo":["",40,450], "impact":["",30,120]
}
const VOICES := 8
static var ambience: AudioStreamWAV
static var wave_cache := {}
var world
var sounds := {}
var source_paths := {}
var station_music: AudioStreamWAV
var flight_music: AudioStream
var music_gain := 0.65
var effects_gain := 0.75
var voices: Array[AudioStreamPlayer] = []
var observed_region := 0
var observed_launches := {}
var event_region := 0
var last_serial := 0
var pending: Array = []
var ui_requests: Array = []
var played_log: Array = []
var priority_until := -1
var last_priority := 0
var last_played := {}
var context := "flight"
var enabled := true
var previous_bed := ""
var ambience_at := 0
var ambience_index := 0
var music_paused := false
var web_music: JavaScriptObject
var web_bed := false
func _ready() -> void:
	# Browser-managed samples keep playing while the single-threaded game loads
	# meshes. Only send pause/resume on transitions (see update_music_pause).
	if OS.has_feature("web"):
		playback_type=AudioServer.PLAYBACK_TYPE_SAMPLE
		var factory=JavaScriptBridge.get_interface("AbyssalMusic")
		if factory!=null:web_music=factory.create()
	if ambience==null: ambience=synthesize(false)
	for i in VOICES:
		var voice := AudioStreamPlayer.new(); add_child(voice); voices.append(voice)
	volume_db=-22
func configure(owner_world, directory: String) -> void:
	world=owner_world
	for cue in SPECS:
		var filename: String = SPECS[cue][0]
		var path := directory.path_join("data/sound/"+filename+".wav") if not filename.is_empty() else ""
		var key: String = path if not path.is_empty() and FileAccess.file_exists(path) else "procedural:"+cue
		if not wave_cache.has(key):
			wave_cache[key]=AudioStreamWAV.load_from_file(path) if not key.begins_with("procedural:") else synthesize_cue(cue)
		if wave_cache[key]==null:
			key="procedural:"+cue
			if not wave_cache.has(key): wave_cache[key]=synthesize_cue(cue)
		sounds[cue]=wave_cache[key]; source_paths[cue]=key
	var music_path := directory.path_join("data/sound/station.mid.wav")
	if FileAccess.file_exists(music_path):
		if not wave_cache.has(music_path):
			var music := AudioStreamWAV.load_from_file(music_path)
			if music!=null:
				music.loop_mode=AudioStreamWAV.LOOP_FORWARD; music.loop_end=roundi(music.get_length()*music.mix_rate)
			wave_cache[music_path]=music
		station_music=wave_cache[music_path]
	# Upload once during content loading, never on the first shot in flight.
	if OS.has_feature("web"):
		for sound in sounds.values():
			if sound!=null and not AudioServer.is_stream_registered_as_sample(sound):
				AudioServer.register_stream_as_sample(sound)
	prepare_web_music("ocean",ambience)
	prepare_web_music("station",station_music)
func update_music_pause(paused: bool) -> void:
	if music_paused==paused:return
	music_paused=paused
	apply_music_pause(paused)
func apply_music_pause(paused: bool) -> void:
	stream_paused=paused
func prepare_web_music(key: String, sound: AudioStream) -> bool:
	if web_music==null or sound==null:return false
	if web_music.has(key):return true
	if not sound is AudioStreamWAV or sound.format!=AudioStreamWAV.FORMAT_16_BITS:return false
	web_music.prepare(key,Marshalls.raw_to_base64(sound.data),sound.mix_rate,sound.stereo)
	return true
func set_context(page: String, docked: bool) -> void:
	context="station" if docked else "flight" if page.is_empty() else page if page in ["dialogue","failure"] else "paused"
func set_enabled(value: bool) -> void:
	if enabled==value: return
	enabled=value; pending.clear(); ui_requests.clear(); priority_until=-1; last_played.clear()
	if world!=null and world.region!=null:
		last_serial=world.region.audio_serial; event_region=world.region.get_instance_id(); collect_launches(world.region)
		if value: pending=world.region.audio_events.filter(func(event): return event.time>world.region.elapsed_ms)
	if not enabled:
		if web_music!=null:web_music.stop()
		stop()
		for voice in voices: voice.stop()
	previous_bed=""
func cue(kind: String) -> void:
	if not enabled or not SPECS.has(kind): return
	if ui_requests.size()>=16: ui_requests.pop_front()
	ui_requests.append({"kind":kind,"gain":1.0})
func collect_launches(region) -> Array:
	if region.get_instance_id()!=observed_region:
		observed_region=region.get_instance_id(); observed_launches.clear()
	var current := {}; var result: Array = []
	for weapon in region.loadout.all_weapons():
		var id: int = weapon.get_instance_id()
		var count: int = maxi(0,weapon.launch_serial-int(observed_launches.get(id,weapon.launch_serial)))
		if count>0:
			result.append({"kind":"harpoon" if weapon.fishing else "torpedo" if weapon.homing else "beam" if weapon.beam else "shot","count":count,"gain":1.0})
		current[id]=weapon.launch_serial
	observed_launches=current
	return result
func collect_shots(region) -> int:
	var count := 0
	for event in collect_launches(region): count+=event.count
	return count
func collect_events(region) -> Array:
	if event_region!=region.get_instance_id():
		event_region=region.get_instance_id(); last_serial=0; pending.clear(); priority_until=-1; last_played.clear()
	for event in region.audio_events:
		if event.serial<=last_serial: continue
		last_serial=event.serial
		if pending.size()>=256: pending.pop_front()
		pending.append(event)
	var result: Array = []; var later: Array = []
	for event in pending:
		if event.time>region.elapsed_ms: later.append(event); continue
		if region.elapsed_ms-event.time>2000: continue
		var gain := 1.0
		if not event.position.is_empty():
			var delta: Array = preload("res://native/simulation/fixed_math.gd").subtracted(event.position,region.player.pose.origin)
			gain=clampf(1.0-Vector3(delta[0],delta[1],delta[2]).length()/40000.0,0.0,1.0)
		if gain>0.005: result.append({"kind":event.kind,"gain":gain})
	pending=later
	return result
func admit(kind: String, now_ms: int) -> bool:
	if not SPECS.has(kind): return false
	var priority: int = SPECS[kind][1]
	if now_ms<=priority_until and priority<last_priority: return false
	last_priority=priority; priority_until=now_ms+int(SPECS[kind][2]); return true
func play_cue(kind: String, gain: float, now_ms: int) -> bool:
	if not enabled or not sounds.has(kind) or sounds[kind]==null or voices.is_empty() or gain<=0: return false
	if now_ms-int(last_played.get(kind,-10000))<80 or not admit(kind,now_ms): return false
	var selected: AudioStreamPlayer
	for voice in voices:
		if voice.get_meta("cue","")==kind: selected=voice; break
	if selected==null:
		for voice in voices:
			if not voice.playing: selected=voice; break
	if selected==null:
		for voice in voices:
			if selected==null or int(voice.get_meta("started",0))<int(selected.get_meta("started",0)): selected=voice
	selected.stop(); selected.stream=sounds[kind]
	selected.volume_db=-12+linear_to_db(maxf(effects_gain,0.0001))+linear_to_db(maxf(gain,0.0001))+(4.0 if kind in ["pressure","message","gate","signal"] else 0.0)
	selected.set_meta("cue",kind); selected.set_meta("started",now_ms)
	if DisplayServer.get_name()!="headless": selected.play()
	last_played[kind]=now_ms
	if played_log.size()>=64: played_log.pop_front()
	played_log.append({"kind":kind,"gain":gain,"source":source_paths[kind],"time":now_ms})
	return true
func _process(_delta: float) -> void:
	if world==null or world.region==null: return
	var events: Array = collect_events(world.region)+collect_launches(world.region)
	var ui: Array = ui_requests; ui_requests=[]
	if not enabled: pending.clear(); return
	var bed := "station" if context=="station" and station_music!=null else "score" if flight_music!=null else "station" if station_music!=null else "ocean"
	if previous_bed!=bed:
		stream=station_music if bed=="station" else flight_music if bed=="score" else ambience
		previous_bed=bed
		music_paused=false
		web_bed=prepare_web_music(bed,stream)
		if web_bed:stop()
		elif DisplayServer.get_name()!="headless":play()
	volume_db=-12+linear_to_db(maxf(music_gain,0.0001))
	var paused: bool=music_gain<=0 or context=="paused" or context=="failure"
	if web_bed:
		music_paused=paused
		web_music.update(bed,db_to_linear(-12.0)*music_gain,paused)
	else:update_music_pause(paused)
	if context=="paused":
		for voice in voices: voice.stop()
		return
	if context=="station": events=[]; pending.clear()
	var now := Time.get_ticks_msec()
	if context=="flight" and now>ambience_at+10000:
		events.append({"kind":"sonar","gain":0.12})
		ambience_index+=1; ambience_at=now
	events.append_array(ui)
	var combined := {}
	for event in events:
		if SPECS.has(event.kind): combined[event.kind]=maxf(float(combined.get(event.kind,0)),event.gain)
	var kinds: Array = combined.keys()
	kinds.sort_custom(func(a,b): return int(SPECS[a][1])>int(SPECS[b][1]))
	for kind in kinds: play_cue(kind,combined[kind],now)
func _exit_tree() -> void:
	if web_music!=null:web_music.dispose();web_music=null
	stop()
	for voice in voices: voice.stop()
static func synthesize(is_shot: bool) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new(); sound.mix_rate=22050; sound.format=AudioStreamWAV.FORMAT_16_BITS
	var count := 4410 if is_shot else 44100
	var bytes := PackedByteArray(); bytes.resize(count*2)
	var rng := RandomNumberGenerator.new(); rng.seed=64718
	for i in count:
		var time := float(i)/22050.0
		var value := sin(time*TAU*43)*0.13+sin(time*TAU*64.5)*0.05
		if is_shot: value=sin(TAU*(390*time-500*time*time))*0.4*pow(1.0-float(i)/count,3)
		else: value*=minf(1.0,minf(i,count-1-i)/110.0)
		bytes.encode_s16(i*2,int(value*32767))
	sound.data=bytes
	if not is_shot: sound.loop_mode=AudioStreamWAV.LOOP_FORWARD; sound.loop_end=count
	return sound

static func synthesize_cue(kind: String) -> AudioStreamWAV:
	if kind=="shot": return synthesize(true)
	var seconds: float = {"beam":0.3,"torpedo":0.45,"impact":0.12,"sonar":1.3,"tow":1.5,"message":0.4,"gate":1.5,"pressure":0.8,"harpoon":0.2,"explosion":0.8,"boost":1.0,"water":2.0,"creature_death":0.5,"signal":0.5,"mine":0.1,"ambient_a":1.5,"ambient_b":1.5,"harpoon_hit":0.08,"beep":0.06}.get(kind,0.2)
	var sound := AudioStreamWAV.new(); sound.mix_rate=22050; sound.format=AudioStreamWAV.FORMAT_16_BITS
	var count := roundi(seconds*sound.mix_rate); var bytes := PackedByteArray(); bytes.resize(count*2)
	var rng := RandomNumberGenerator.new(); rng.seed=64718+absi(kind.hash()); var low := 0.0
	for i in count:
		var time := float(i)/sound.mix_rate; var phase := float(i)/count
		var noise := rng.randf_range(-1,1); low=lerpf(low,noise,0.08)
		var value := 0.0
		match kind:
			"beam": value=sin(TAU*(500*time-300*time*time))*0.27+sin(TAU*1030*time)*0.08
			"torpedo","explosion": value=low*1.3+sin(TAU*65*time)*0.2
			"impact","harpoon_hit": value=noise*0.3+sin(TAU*1200*time)*0.12
			"sonar": value=sin(TAU*1180*time)*0.35*exp(-phase*5)
			"tow","gate","boost": value=low*0.6+sin(TAU*(80*time+120*time*time))*0.22
			"water","ambient_a","ambient_b": value=low*(0.4+sin(TAU*time*1.2)*0.2)
			"pressure": value=sin(TAU*780*time)*0.3*(0.5+0.5*sin(TAU*4*time))
			"message","signal": value=sin(TAU*(660 if phase<0.5 else 880)*time)*0.28
			"creature_death": value=sin(TAU*(700*time-500*time*time))*0.27
			"mine","beep": value=sin(TAU*(1800 if kind=="mine" else 640)*time)*0.25
			"harpoon": value=low*0.9+sin(TAU*(260*time-500*time*time))*0.25
		value*=minf(1.0,float(i)/110.0)*pow(1.0-phase,1.5)
		bytes.encode_s16(i*2,clampi(roundi(value*32767),-32767,32767))
	sound.data=bytes
	return sound
