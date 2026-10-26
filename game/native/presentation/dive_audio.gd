extends AudioStreamPlayer
## Source cue meanings and priority windows; bounded desktop playback. Imported
## AMR/MIDI conversions stay in the owner's cache. Launches use the engine's
## credited prepared sample bank; missing original cues have code-authored fallbacks.
const SPECS := {
	"sonar":["echolot.amr",0,1300], "tow":["traktor.amr",95,2500],
	"message":["message.amr",100,1100], "gate":["gate.amr",100,3000],
	"pressure":["alert.amr",100,1400], "harpoon":["harpoon.amr",90,900],
	"explosion":["explosion.amr",100,2800], "boost":["turbo.amr",100,3200],
	"water":["water.amr",0,2800], "creature_death":["tiertot.amr",100,1000],
	"signal":["signal.amr",100,1000], "mine":["mine.amr",80,300],
	"ambient_a":["amb02.amr",80,1500], "ambient_b":["amb03.amr",80,1500],
	"harpoon_hit":["harpoon_hit.amr",90,150], "beep":["beep.amr",80,90],
	# These launches have no cue in the original's sound table.
	"gun":["",0,0], "plasma":["",0,0], "beam":["",0,0], "mass":["",0,0], "torpedo":["",0,0], "eclipse":["",0,0]
}
const VOICES := 8
const LAUNCH_VOICES := 4
## Recorded discharges sit below the imported cues; their tier gains still
## distinguish slow, powerful weapons without overwhelming ocean and alerts.
const LAUNCH_TRIM_DB := -8.0
const Launch = preload("res://native/presentation/weapon_audio.gd")
const LAUNCH_CUES := Launch.FAMILIES
const Mix = preload("res://native/presentation/audio_settings.gd")
const Mods = preload("res://native/presentation/mods.gd")
static var ambience: AudioStreamWAV
static var wave_cache := {}
var world
var sounds := {}
var launch_sounds := {}
var launch_variations := {}
var source_paths := {}
var station_music: AudioStream
## Imported MIDI conversions by track name ("intro", "station"), or the
## player's replacements from the mods folder.
var music_tracks := {}
## The mods file behind each replaced track; the browser decodes it itself.
var music_sources := {}
## A track the Mods page is playing in place of the title's own.
var preview_track := ""
## The title menu and opening track: 0 follows the JAR, 1 intro, 2 station.
const TITLE_CHOICES := ["Auto","Intro","Station"]
var title_choice := 0
## Track 0 of the JAR's own music table; 1.0.3 builds open with intro.mid.
var jar_title := "station"
## The opening plays the game's track over the water; set for its length.
var opening_music := false
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
var weapon_sounds_enabled := true
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
	if ambience==null: ambience=synthesize_ambience()
	Mix.ensure_buses()
	bus=Mix.MUSIC
	for i in VOICES:
		var voice := AudioStreamPlayer.new(); voice.bus=Mix.EFFECTS; add_child(voice); voices.append(voice)
	apply_levels()
	volume_db=-22
func configure(owner_world, directory: String) -> void:
	world=owner_world
	for kind in Launch.BANKS:
		var bank: Array[AudioStreamWAV]=[]
		for variation in Launch.VARIATIONS:
			var key: String=Launch.path(kind,variation)
			if not wave_cache.has(key):wave_cache[key]=Launch.sample(kind,variation)
			bank.append(wave_cache[key])
		launch_sounds[kind]=bank
	for cue in SPECS:
		if cue in LAUNCH_CUES:
			sounds[cue]=launch_sounds[cue][0];source_paths[cue]=Launch.path(cue)
			continue
		var filename: String = SPECS[cue][0]
		var path := directory.path_join("data/sound/"+filename+".wav") if not filename.is_empty() else ""
		var key: String = path if not path.is_empty() and FileAccess.file_exists(path) else "procedural:"+cue
		if not wave_cache.has(key):
			wave_cache[key]=AudioStreamWAV.load_from_file(path) if not key.begins_with("procedural:") else synthesize_cue(cue)
		if wave_cache[key]==null:
			key="procedural:"+cue
			if not wave_cache.has(key): wave_cache[key]=synthesize_cue(cue)
		sounds[cue]=wave_cache[key]; source_paths[cue]=key
	load_music(directory)
	# Upload once during content loading, never on the first shot in flight.
	if OS.has_feature("web"):
		var samples: Array=sounds.values()
		for bank in launch_sounds.values():samples.append_array(bank)
		for sound in samples:
			if sound!=null and not AudioServer.is_stream_registered_as_sample(sound):
				AudioServer.register_stream_as_sample(sound)
	prepare_web_music("ocean",ambience)
	for track in music_tracks:prepare_web_music(track,music_tracks[track])
	previous_bed=""
func load_music(directory: String) -> void:
	"""The converted MIDI tracks, then any replacement in the mods folder,
	which is read afresh each time so a new one plays at once."""
	music_tracks.clear();music_sources.clear()
	for track in ["intro","station"]:
		var music_path := directory.path_join("data/sound/%s.mid.wav"%track)
		if not FileAccess.file_exists(music_path):continue
		if not wave_cache.has(music_path):
			var music := AudioStreamWAV.load_from_file(music_path)
			if music!=null:
				music.loop_mode=AudioStreamWAV.LOOP_FORWARD; music.loop_end=roundi(music.get_length()*music.mix_rate)
			wave_cache[music_path]=music
		if wave_cache[music_path]!=null:music_tracks[track]=wave_cache[music_path]
	for track in ["intro","station"]:
		var replacement := Mods.music_path(track)
		if replacement.is_empty():continue
		var music := Mods.load_music(replacement)
		if music==null:push_warning("Could not read replacement music: "+replacement);continue
		music_tracks[track]=music;music_sources[track]=replacement
	station_music=music_tracks.get("station")
func reload_music(directory: String) -> void:
	"""After the Mods page changes a track: the new one plays from the start."""
	load_music(directory)
	if web_music!=null:
		web_music.stop()
		for track in ["intro","station"]:web_music.forget(track)
		for track in music_tracks:prepare_web_music(track,music_tracks[track])
	previous_bed=""
func read_title_track(data: Dictionary) -> void:
	"""Imports that predate the recorded music table keep the 1.0.8 track."""
	var table=data.get("music",[])
	jar_title="station"
	if table is Array and not table.is_empty() and table[0] is String and table[0].ends_with(".mid"):
		jar_title=table[0].get_basename()
func title_choice_text() -> String:
	"""Auto names the track it resolves to, so the choice is never a guess."""
	if title_choice==0:
		match title_track():
			"intro":return tr("Auto · Intro")
			"station":return tr("Auto · Station")
		return "Auto · "+title_track().capitalize()
	return title_choice_names()[title_choice]
func title_choice_names() -> Array:
	"""TITLE_CHOICES in the engine's language."""
	return [tr("Auto"),tr("Intro"),tr("Station")]
func title_track() -> String:
	"""The chosen menu track, or the station track where this JAR has none."""
	var wanted: String=jar_title if title_choice==0 else "intro" if title_choice==1 else "station"
	return wanted if music_tracks.has(wanted) else "station"
func update_music_pause(paused: bool) -> void:
	if music_paused==paused:return
	music_paused=paused
	apply_music_pause(paused)
func apply_music_pause(paused: bool) -> void:
	stream_paused=paused
func prepare_web_music(key: String, sound: AudioStream) -> bool:
	if web_music==null or sound==null:return false
	if web_music.has(key):return true
	# A replacement that is not 16-bit PCM goes to the browser as the file
	# itself, which it decodes; playback starts once that has finished.
	if music_sources.has(key) and not (sound is AudioStreamWAV and sound.format==AudioStreamWAV.FORMAT_16_BITS):
		var encoded := FileAccess.get_file_as_bytes(music_sources[key])
		if encoded.is_empty():return false
		web_music.prepareEncoded(key,Marshalls.raw_to_base64(encoded));return true
	if not sound is AudioStreamWAV or sound.format!=AudioStreamWAV.FORMAT_16_BITS:return false
	web_music.prepare(key,Marshalls.raw_to_base64(sound.data),sound.mix_rate,sound.stereo)
	return true
func set_context(page: String, docked: bool) -> void:
	context="title" if page=="title" else "station" if docked else "flight" if page.is_empty() else page if page in ["dialogue","failure","opening"] else "paused"
func set_weapon_sounds_enabled(value: bool) -> void:
	weapon_sounds_enabled=value
	if not value:
		for voice in voices:
			if voice.get_meta("cue","") in LAUNCH_CUES:voice.stop()
		# Observe even while disabled, so enabling never replays earlier shots.
		if world!=null and world.region!=null:collect_launches(world.region)

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
	apply_levels()
	previous_bed=""
func apply_levels() -> void:
	"""One place decides what each group is worth, including silence."""
	Mix.apply(music_gain,effects_gain,enabled)
func cue(kind: String) -> void:
	if not enabled or not SPECS.has(kind): return
	if ui_requests.size()>=16: ui_requests.pop_front()
	ui_requests.append({"kind":kind,"gain":1.0})
func collect_launches(region) -> Array:
	if region.get_instance_id()!=observed_region:
		observed_region=region.get_instance_id(); observed_launches.clear()
	var current := {}; var result: Array = []
	var player_weapons: Array=region.loadout.all_weapons()
	var weapons: Array=player_weapons.duplicate()
	for weapon in region.weapons:
		if weapon not in weapons:weapons.append(weapon)
	for weapon in weapons:
		var id: int = weapon.get_instance_id()
		var previous: int=int(observed_launches.get(id,weapon.launch_serial))
		var count: int = maxi(0,weapon.launch_serial-previous)
		# A launch gets one short prepared report. Held fire during cooldown
		# emits nothing, and identical simultaneous guns share one sample voice.
		if count>0:
			var kind: String=Launch.family(weapon)
			var gain:=1.0
			if weapon not in player_weapons:
				gain=0.0
				for i in weapon.launch_serials.size():
					if weapon.launch_serials[i]<=previous:continue
					var delta: Array=preload("res://native/simulation/fixed_math.gd").subtracted(weapon.launch_positions[i],region.player.pose.origin)
					gain=maxf(gain,.65*clampf(1.0-Vector3(delta[0],delta[1],delta[2]).length()/40000.0,0,1))
			if gain>.005:result.append({"kind":kind,"count":count,"gain":gain,"profile":Launch.profile(weapon)})
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
func play_cue(kind: String, gain: float, now_ms: int, profile: Dictionary={}) -> bool:
	if not enabled or not sounds.has(kind) or sounds[kind]==null or voices.is_empty() or gain<=0: return false
	var launch: bool=kind in LAUNCH_CUES
	if launch and not weapon_sounds_enabled:return false
	var bank: String=String(profile.get("bank",kind)) if launch else kind
	if launch and not launch_sounds.has(bank):bank=kind
	if now_ms-int(last_played.get(bank,-10000))<80:return false
	# Launch feedback sits underneath the original priority channel. Ambient
	# water or a boost must not silence it for seconds; alerts still stand out.
	if not launch and not admit(kind,now_ms):return false
	var selected: AudioStreamPlayer
	if launch:
		# Let successive shots finish naturally. Cap their overlap so pressure,
		# mission messages and attachment cues still have spare voices.
		var active: Array[AudioStreamPlayer]=[]
		for voice in voices:
			if voice.playing and voice.get_meta("cue","") in LAUNCH_CUES:active.append(voice)
		if active.size()>=LAUNCH_VOICES:
			for voice in active:
				if selected==null or int(voice.get_meta("started",0))<int(selected.get_meta("started",0)):selected=voice
	else:
		for voice in voices:
			if voice.get_meta("cue","")==kind: selected=voice; break
	if selected==null:
		for voice in voices:
			if not voice.playing: selected=voice; break
	if selected==null:
		for voice in voices:
			if launch and voice.get_meta("cue","") not in LAUNCH_CUES:continue
			if selected==null or int(voice.get_meta("started",0))<int(selected.get_meta("started",0)): selected=voice
	if selected==null:return false
	var variation:=0
	selected.stop()
	if launch and launch_sounds.has(bank):
		variation=int(launch_variations.get(bank,0))
		selected.stream=launch_sounds[bank][variation]
		launch_variations[bank]=(variation+1)%Launch.VARIATIONS
	else:selected.stream=sounds[kind]
	selected.pitch_scale=clampf(float(profile.get("pitch",1.0)),.78,1.12) if launch else 1.0
	selected.volume_db=-12+linear_to_db(maxf(gain,0.0001))+(4.0 if kind in ["pressure","message","gate","signal"] else 0.0)
	if launch:selected.volume_db+=clampf(float(profile.get("db",0.0)),-2.0,3.0)+LAUNCH_TRIM_DB-(5.0 if now_ms<=priority_until and last_priority>=90 else 0.0)
	selected.set_meta("cue",kind); selected.set_meta("started",now_ms)
	if DisplayServer.get_name()!="headless": selected.play()
	last_played[bank]=now_ms
	if played_log.size()>=64: played_log.pop_front()
	played_log.append({"kind":kind,"gain":gain,"source":Launch.path(bank,variation) if launch else source_paths[kind],"bank":bank,"time":now_ms,"variation":variation,"volume_db":selected.volume_db,"pitch":selected.pitch_scale})
	return true
func _process(_delta: float) -> void:
	if world==null or world.region==null: return
	var events: Array = collect_events(world.region)+collect_launches(world.region)
	var ui: Array = ui_requests; ui_requests=[]
	if not enabled: pending.clear(); return
	# The phone game plays its one track in the menu, docked and during the
	# opening (l, ch, br.a); br.void_a stops it on the way out into the water,
	# where the only sound is the ocean's own cue every ten seconds. Without
	# imported content the code-authored ocean bed stands in for that track.
	# The menu and opening play the JAR's first track (intro.mid in 1.0.3,
	# station.mid in 1.0.8) unless the player picked one; docking plays station.
	var bed := title_track() if context=="title" or opening_music else "station" if context=="station" else ""
	if context=="title" and music_tracks.has(preview_track):bed=preview_track
	if not bed.is_empty() and not music_tracks.has(bed):bed="ocean"
	if previous_bed!=bed:
		if web_music!=null and not previous_bed.is_empty():web_music.stop()
		stream=music_tracks.get(bed) if music_tracks.has(bed) else ambience if bed=="ocean" else null
		previous_bed=bed
		music_paused=false
		web_bed=not bed.is_empty() and prepare_web_music(bed,stream)
		if web_bed or bed.is_empty():stop()
		elif DisplayServer.get_name()!="headless":play()
	volume_db=-12
	apply_levels()
	var paused: bool=music_gain<=0 or context=="paused" or context=="failure"
	if web_bed:
		music_paused=paused
		web_music.update(bed,db_to_linear(-12.0)*music_gain,paused)
	else:update_music_pause(paused)
	if context=="paused":
		for voice in voices: voice.stop()
		return
	if context in ["station","title"]: events=[]; pending.clear()
	var now := Time.get_ticks_msec()
	# br.a: every ten seconds in the water one of the four ocean cues, chosen
	# at random, at a volume drawn between six tenths and the full level.
	if context=="flight" and now>ambience_at+10000 and not opening_music:
		events.append({"kind":["sonar","water","ambient_a","ambient_b"][randi()%4],"gain":maxf(0.6,randf())})
		ambience_index+=1; ambience_at=now
	events.append_array(ui)
	var combined := {}
	var profiles := {}
	var cue_kinds := {}
	for event in events:
		if not SPECS.has(event.kind):continue
		var profile: Dictionary=event.get("profile",{})
		var key: String=String(profile.get("bank",event.kind)) if event.kind in LAUNCH_CUES else event.kind
		var previous: Dictionary=profiles.get(key,{})
		if not combined.has(key) or event.gain>combined[key] or (is_equal_approx(event.gain,combined[key]) and float(profile.get("db",0))>float(previous.get("db",0))):
			combined[key]=event.gain;profiles[key]=profile;cue_kinds[key]=event.kind
	var kinds: Array = combined.keys()
	kinds.sort_custom(func(a,b): return int(SPECS[cue_kinds[a]][1])>int(SPECS[cue_kinds[b]][1]))
	for key in kinds: play_cue(cue_kinds[key],combined[key],now,profiles[key])
func _exit_tree() -> void:
	if web_music!=null:web_music.dispose();web_music=null
	stop()
	for voice in voices: voice.stop()
static func synthesize_ambience() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new(); sound.mix_rate=22050; sound.format=AudioStreamWAV.FORMAT_16_BITS
	var count := 44100
	var bytes := PackedByteArray(); bytes.resize(count*2)
	for i in count:
		var time := float(i)/22050.0
		var value := sin(time*TAU*43)*0.13+sin(time*TAU*64.5)*0.05
		value*=minf(1.0,minf(i,count-1-i)/110.0)
		bytes.encode_s16(i*2,int(value*32767))
	sound.data=bytes
	sound.loop_mode=AudioStreamWAV.LOOP_FORWARD; sound.loop_end=count
	return sound

static func synthesize_cue(kind: String) -> AudioStreamWAV:
	if kind in LAUNCH_CUES:return Launch.sample(kind)
	var seconds: float = {"sonar":1.3,"tow":1.5,"message":0.4,"gate":1.5,"pressure":0.8,"harpoon":0.2,"explosion":0.8,"boost":1.0,"water":2.0,"creature_death":0.5,"signal":0.5,"mine":0.1,"ambient_a":1.5,"ambient_b":1.5,"harpoon_hit":0.08,"beep":0.06}.get(kind,0.2)
	var sound := AudioStreamWAV.new(); sound.mix_rate=22050; sound.format=AudioStreamWAV.FORMAT_16_BITS
	var count := roundi(seconds*sound.mix_rate); var bytes := PackedByteArray(); bytes.resize(count*2)
	var rng := RandomNumberGenerator.new(); rng.seed=64718+absi(kind.hash()); var low := 0.0
	for i in count:
		var time := float(i)/sound.mix_rate; var phase := float(i)/count
		var noise := rng.randf_range(-1,1); low=lerpf(low,noise,0.08)
		var value := 0.0
		match kind:
			"explosion": value=low*1.3+sin(TAU*65*time)*0.2
			"harpoon_hit": value=noise*0.3+sin(TAU*1200*time)*0.12
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
