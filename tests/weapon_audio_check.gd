extends SceneTree
const Audio=preload("res://native/presentation/dive_audio.gd")
const Launch=preload("res://native/presentation/weapon_audio.gd")
var checks:=0
var failures:=0
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var audio:=Audio.new();root.add_child(audio);audio.set_process(false)
	audio.configure(null,"user://missing-content")
	var bytes:=0
	for kind in Launch.BANKS:
		var bank: Array=audio.launch_sounds[kind]
		expect(bank.size()==3 and Launch.path(kind).begins_with(Launch.DIRECTORY),"%s loads its three recorded variations"%kind)
		for variation in bank.size():
			var sound: AudioStreamWAV=bank[variation]
			expect(sound!=null,"%s sample is present in the exported resource set"%kind)
			if sound==null:continue
			bytes+=sound.data.size()
			var peak:=0.0;var sum:=0.0;var energy:=0.0;var end_energy:=0.0
			var count:=sound.data.size()/2
			for i in count:
				var value:=float(sound.data.decode_s16(i*2))/32768.0
				peak=maxf(peak,absf(value));sum+=value;energy+=value*value
				if i>=count-960:end_energy+=value*value
			expect(sound.mix_rate==48000 and sound.format==AudioStreamWAV.FORMAT_16_BITS and not sound.stereo and sound.loop_mode==AudioStreamWAV.LOOP_DISABLED,"%s uses full-rate, nonlooping mono PCM compatible with native and web playback"%kind)
			expect(peak<.80 and peak>.30 and sqrt(energy/count)>.025,"%s retains an attack and body with headroom"%kind)
			expect(absf(sum/count)<.001 and sqrt(end_energy/960)<.002,"%s has no DC offset and fades to a quiet tail"%kind)
			expect(sound.data.decode_s16(0)==0 and sound.data.decode_s16(sound.data.size()-2)==0,"%s meets silence without a boundary click"%kind)
			expect(sound.data==Launch.sample(kind,variation).data,"%s plays the prepared recording without runtime synthesis"%kind)
			if FileAccess.file_exists(Launch.path(kind,variation)):
				var source:=AudioStreamWAV.load_from_file(Launch.path(kind,variation))
				expect(source!=null and source.data==sound.data,"%s imported playback matches the current PCM source rather than a stale import"%kind)
			expect(sound.data!=bank[(variation+1)%bank.size()].data,"%s successive shots do not repeat the same sample"%kind)
	expect(bytes<6000000,"All forty-eight launch variants fit in a bounded PCM cache under 6 MB")
	var again:=Audio.new();root.add_child(again);again.set_process(false);again.configure(null,"user://missing-content")
	expect(again.launch_sounds.gun[0]==audio.launch_sounds.gun[0] and again.launch_sounds.torpedo[2]==audio.launch_sounds.torpedo[2],"Another audio controller reuses already loaded recordings")
	var weapon=preload("res://native/simulation/weapon.gd").new()
	for id in range(15):
		weapon.equipment_id=id;weapon.beam=id in [3,4,5];weapon.homing=id in [12,13,14]
		expect(Launch.family(weapon)==["gun","beam","plasma","mass","torpedo"][id/3],"Equipment %d has the matching launch family"%id)
		expect(Launch.bank(weapon)==Launch.BANKS[id],"Equipment %d selects its own authored bank"%id)
	weapon.homing=false;weapon.beam=false;weapon.equipment_id=-1;weapon.model_id=6764
	expect(Launch.family(weapon)=="mass" and Launch.bank(weapon)=="mass-ii","A shared NPC mass-driver model retains its individual cue without an equipment record")
	weapon.fishing=true
	expect(Launch.family(weapon)=="harpoon" and "harpoon" not in Launch.FAMILIES,"Fishing selects the original imported harpoon cue")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():await check_imported(args[0])
	again.queue_free()
	for i in 7:
		expect(audio.play_cue("gun",1,10000+i*100),"Each separated launch is admitted")
		expect(audio.played_log.back().variation==i%3,"Successive launches cycle through preloaded variations")
		expect(audio.played_log.back().source==Launch.path("gun",i%3),"The playback record names the sample actually selected")
		var sequence: int=audio.launch_variations.gun
		expect(not audio.play_cue("gun",1,10000+i*100+1) and audio.launch_variations.gun==sequence,"Coalescing a volley does not advance its sample variation")
	for voice in audio.voices:voice.stop()
	audio.last_played.clear();audio.priority_until=-1
	if DisplayServer.get_name()!="headless":
		audio.play_cue("pressure",1,20000)
		var alert: AudioStreamPlayer=audio.voices[0]
		var previous: AudioStreamPlayer
		for i in 8:
			audio.play_cue("gun",1,20001+i*100)
			var newest: AudioStreamPlayer
			var active:=0
			for voice in audio.voices:
				if voice.playing and voice.get_meta("cue","") in Audio.LAUNCH_CUES:
					active+=1
					if int(voice.get_meta("started",0))==20001+i*100:newest=voice
			expect(active==mini(i+1,Audio.LAUNCH_VOICES),"Rapid fire overlaps tails up to its fixed voice budget")
			if i>0:expect(previous.playing and previous!=newest,"The next shot preserves the preceding tail")
			expect(alert.playing and alert.get_meta("cue","")=="pressure","An overlapping volley cannot steal an alert")
			expect(is_equal_approx(newest.volume_db,-25.0),"Launches remain quieter under a priority alert")
			previous=newest
		audio.set_weapon_sounds_enabled(false)
		expect(audio.voices.filter(func(voice):return voice.get_meta("cue","") in Audio.LAUNCH_CUES).all(func(voice):return not voice.playing),"Disabling added sounds stops only the launch tails immediately")
		expect(alert.playing,"Disabling added sounds preserves the original alert")
		expect(not audio.play_cue("gun",1,21500),"Disabled launch sounds cannot allocate a voice")
		audio.set_weapon_sounds_enabled(true)
		# Saturating all eight voices with original cues blocks a launch rather
		# than stopping those sounds to make space.
		for voice in audio.voices:
			voice.stop();voice.stream=audio.sounds.pressure;voice.set_meta("cue","pressure");voice.play()
		var sequence: int=audio.launch_variations.gun
		expect(not audio.play_cue("gun",1,22000) and audio.launch_variations.gun==sequence,"No original cue is evicted when all voices are occupied")
		audio.set_enabled(false)
		expect(audio.voices.all(func(voice):return not voice.playing),"Muting stops all overlapping tails")
	expect(not audio.play_cue("plasma",0,23000),"Zero-gain fire cannot start a sample")
	audio.queue_free()
	for i in 4:await process_frame
	print("WEAPON_AUDIO ",checks," checks; ",failures," failures");quit(1 if failures else 0)

func check_imported(directory: String) -> void:
	var content=preload("res://native/content.gd").new()
	expect(content.load_cache(directory),"The audio gameplay check loads compatible imported stats")
	if content.data.is_empty():return
	var session=preload("res://native/simulation/session.gd").new();session.new_game(content.data,"Audio check",123)
	preload("res://native/simulation/demo_session.gd").initialize(session)
	var draft=preload("res://native/simulation/demo_session.gd").new();draft.equipment=[5,-1,18,22,35,39];draft.apply(session)
	var world=preload("res://native/simulation/world.gd").new();world.configure(session);world.depart()
	var controller:=Audio.new();root.add_child(controller);controller.set_process(false);controller.configure(world,directory)
	var original:=AudioStreamWAV.load_from_file(directory.path_join("data/sound/harpoon.amr.wav"))
	expect(controller.source_paths.harpoon.ends_with("/harpoon.amr.wav") and controller.sounds.harpoon.data==original.data,"Harpoon playback preserves the original imported audio bytes")
	controller.collect_launches(world.region)
	world.region.step(40,{"guns":true});controller._process(.04)
	var report: Dictionary=controller.played_log.filter(func(e):return e.kind=="beam").back()
	var gun=world.region.loadout.all_weapons()[0]
	var heavy: Dictionary=Launch.profile(gun)
	expect(is_equal_approx(report.pitch,heavy.pitch) and is_equal_approx(report.volume_db,-20.0+heavy.db),"The real launch event carries imported power/cadence through coalescing into playback")
	var loadout=preload("res://native/simulation/weapon_loadout.gd")
	var light=loadout.create(session.make_equipment(3),content.data)
	expect(heavy.bank=="beam-iii" and Launch.profile(light).bank=="beam" and is_equal_approx(heavy.pitch,1.0),"The heavy coil uses its own source design, preserving the authored pitch")
	expect(Launch.sample(heavy.bank).get_length()>Launch.sample(Launch.bank(light)).get_length(),"The heavy coil sustains its field body longer than the light coil")
	for id in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,42]:
		var w=loadout.create(session.make_equipment(id),content.data)
		var seconds:=Launch.sample(Launch.bank(w)).get_length()/float(Launch.profile(w).pitch)
		var sample: AudioStreamWAV=Launch.sample(Launch.bank(w))
		var total:=0.0;var tail:=0.0
		for i in sample.data.size()/2:
			var value:=float(sample.data.decode_s16(i*2))/32768.0
			total+=value*value
			if float(i)/sample.mix_rate>float(w.cooldown)/1000.0:tail+=value*value
		expect(tail/maxf(total,.001)<.38,"Equipment %d leaves only a declining tail over its next launch"%id)
		expect(seconds<2.5,"Equipment %d has a bounded report duration"%id)
	# Two different rail models in one real loadout must both reach playback;
	# identical copies still coalesce to protect mix headroom.
	draft.equipment=[0,1,18,22,35,39];draft.apply(session)
	world.dispose();world=preload("res://native/simulation/world.gd").new();world.configure(session);world.depart()
	controller.world=world;controller.played_log.clear();controller.last_played.clear();controller.collect_launches(world.region)
	world.region.step(40,{"guns":true});controller._process(.04)
	var rails: Array=controller.played_log.filter(func(e):return e.kind=="gun")
	expect(rails.size()==2 and rails.any(func(e):return e.bank=="gun") and rails.any(func(e):return e.bank=="gun-ii"),"A simultaneous mixed rail volley preserves both equipment identities")
	controller.played_log.clear();controller.last_played.clear()
	expect(controller.play_cue("gun",1,30000,{"bank":"gun"}) and controller.play_cue("gun",1,30000,{"bank":"gun-ii"}),"The per-bank debounce accepts different rail models at the same instant")
	expect(not controller.play_cue("gun",1,30000,{"bank":"gun-ii"}),"Identical simultaneous rail copies still coalesce")
	controller.play_cue("harpoon",1,Time.get_ticks_msec()+10000)
	expect(controller.played_log.back().source.ends_with("/harpoon.amr.wav") and is_equal_approx(controller.played_log.back().pitch,1.0),"Returning from a heavy launch resets voice pitch for the original harpoon")
	controller.set_weapon_sounds_enabled(false)
	controller.played_log.clear();controller.last_played.clear();controller.priority_until=-1
	for i in 40:world.region.step(40,{"guns":true});controller._process(.04)
	expect(controller.played_log.all(func(e):return e.kind not in Audio.LAUNCH_CUES),"Real launches remain silent while added sounds are off")
	expect(controller.play_cue("harpoon",1,Time.get_ticks_msec()+20000),"Original harpoon audio remains available with added sounds off")
	controller.set_weapon_sounds_enabled(true);controller.played_log.clear();controller._process(.04)
	expect(controller.played_log.all(func(e):return e.kind not in Audio.LAUNCH_CUES),"Enabling added sounds never catches up on muted shots")
	controller.set_enabled(false);controller.world=null;controller.queue_free();world.dispose()
	for i in 4:await process_frame
