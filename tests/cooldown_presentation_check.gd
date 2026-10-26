extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const Demo=preload("res://native/simulation/demo_session.gd")
const World=preload("res://native/simulation/world.gd")
const Instruments=preload("res://native/presentation/flight_instruments.gd")
var data: Dictionary
var checks:=0
var failures:=0
var samples: Array=[]

func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)

func fixture():
	var session:=Session.new();session.new_game(data,"Cooldown check",812)
	Demo.initialize(session);Demo.new().apply(session)
	var world:=World.new();world.configure(session);world.depart()
	# Accelerated time is deliberately unavailable near a live hostile.
	for actor in world.region.enemies:actor.state=999;actor.health.hull=0;actor.health.enabled=false
	return world

func _initialize() -> void:call_deferred("run")

func run() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	for fps in [30,60,120]:
		for speed in [1,2,4,8,16]:
			for charging in [false,true]:check_frames(fps,speed,charging)
	check_speed_changes()
	check_transitions()
	if OS.get_cmdline_user_args().size()>1:
		var file:=FileAccess.open(OS.get_cmdline_user_args()[1],FileAccess.WRITE)
		file.store_string(JSON.stringify(samples,"\t"))
	print("COOLDOWN_PRESENTATION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func check_frames(fps: int, speed: int, charging: bool) -> void:
	var world=fixture();var r=world.region;var player=r.player
	world.speed=speed
	if charging:player.boost_timer=-player.stats.boost_cooldown
	else:player.boost()
	# Keep every reload in progress for the short sampling window.
	for weapon in r.loadout.all_weapons():weapon.cooldown=8000;weapon.elapsed=0
	var elapsed:=0.0;var previous:=0.0;var raw_previous:=0.0
	var max_error:=0.0;var max_step:=0.0;var raw_max_step:=0.0;var raw_holds:=0
	var progresses:=true;var states_ok:=true;var readonly:=true
	for frame in ceili(.16*fps):
		elapsed+=1.0/fps;world.advance(1.0/fps)
		var raw: float=player.boost_timer+(player.stats.boost_cooldown if charging else 0)
		var before: Array=[player.boost_timer,r.loadout.all_weapons().map(func(w):return w.elapsed)]
		var boost:=Instruments.boost_state(player,world)
		var hook:=Instruments.harpoon_state(r,world);var guns:=Instruments.guns_state(r,world)
		var shown: float=(player.stats.boost_cooldown*boost.fraction) if charging else (player.stats.boost_duration-boost.seconds*1000.0)
		var expected:=maxf(0.0,elapsed*1000.0-World.STEP_MS)*speed
		max_error=maxf(max_error,absf(shown-expected))
		max_error=maxf(max_error,absf(hook.fraction*8000.0-expected))
		max_error=maxf(max_error,absf(guns.fraction*8000.0-expected))
		if elapsed*1000.0>World.STEP_MS:progresses=progresses and shown>previous
		if frame>0 and is_equal_approx(raw,raw_previous):raw_holds+=1
		max_step=maxf(max_step,shown-previous);raw_max_step=maxf(raw_max_step,raw-raw_previous)
		states_ok=states_ok and boost.mode==("charging" if charging else "active") and hook.mode=="reloading" and guns.mode=="reloading"
		readonly=readonly and before==[player.boost_timer,r.loadout.all_weapons().map(func(w):return w.elapsed)]
		previous=shown;raw_previous=raw
	var name:="%d FPS / %dx / %s"%[fps,speed,"charging" if charging else "active"]
	expect(world.speed==speed and states_ok,name+": genuine accelerated flight stays in the tested phase")
	expect(max_error<.001,name+": boost, gun and hook displays advance at the simulated rate between batches")
	expect(progresses and max_step<=speed*1000.0/fps+.001,name+": each rendered frame advances without a batch-sized jump")
	expect(fps==30 or raw_holds>0,name+": fixture reproduces the raw timer's repeated frames")
	expect(readonly,name+": HUD reads never change simulation timers")
	samples.append({"fps":fps,"speed":speed,"charging":charging,"raw_largest_step_ms":raw_max_step,"display_largest_step_ms":max_step,"raw_held_frames":raw_holds,"largest_rate_error_ms":max_error})
	world.dispose()

func check_speed_changes() -> void:
	var world=fixture();var player=world.region.player
	player.boost();world.speed=2;world.advance(.04);world.advance(.013)
	var previous: float=world.render_boost_timer()
	var continuous:=true;var monotonic:=true;var bounded:=true
	for speed in [4,8,2,8,4,2]:
		world.speed=speed
		continuous=continuous and is_equal_approx(previous,world.render_boost_timer())
		for frame in 7:
			world.advance(.008)
			var current: float=world.render_boost_timer()
			monotonic=monotonic and current>=previous
			bounded=bounded and current-previous<=64.001
			previous=current
	expect(continuous,"Changing time speed mid-batch does not move the displayed cooldown")
	expect(monotonic and bounded,"Repeated 2x/4x/8x changes keep boost progress continuous and forward")
	var actual: int=player.boost_timer
	world.region.active_transmission={};world.advance(.008)
	expect(is_equal_approx(world.render_boost_timer(),actual),"A blocking radio pause holds the actual timer when time debt is cleared")
	world.dispose()

func check_transitions() -> void:
	var world=fixture();var r=world.region;var player=r.player
	world.speed=2;player.boost();player.boost_timer=player.stats.boost_duration-40
	world.advance(.04)
	var state:=Instruments.boost_state(player,world)
	expect(state.mode=="charging" and is_zero_approx(state.fraction),"A finished boost immediately starts an empty charge bar")
	world.advance(.02);state=Instruments.boost_state(player,world)
	expect(state.fraction>0 and state.fraction<.01,"The new charge advances smoothly after the phase change")
	player.boost_timer=-40;world.advance(.04)
	expect(Instruments.boost_state(player,world).mode=="ready" and player.boost(),"Readiness is immediate and agrees with the real boost control")
	expect(is_equal_approx(Instruments.boost_state(player,world).fraction,1.0),"A new boost starts with a full duration bar")
	player.set_throttle(0);state=Instruments.boost_state(player,world)
	expect(state.mode=="charging" and is_zero_approx(state.fraction),"Cancelling a new boost cannot blend from the previous charge cycle")
	# At 8x a fast gun can fire within a batch and end above its old timer.
	var gun=r.weapons[0];gun.cooldown=200;gun.elapsed=40
	world.accumulator=0;world.speed=8;world.advance(.04,{"guns":true})
	expect(gun.launch_serial==1 and gun.elapsed==160,"The fast-gun fixture fires inside a batch")
	expect(is_zero_approx(Instruments.guns_state(r,world).fraction),"A new shot resets presentation even when its timer exceeds the previous sample")
	world.advance(.02)
	expect(is_equal_approx(Instruments.guns_state(r,world).fraction,.4),"The new gun reload advances from zero")
	gun.elapsed=gun.cooldown
	expect(Instruments.guns_state(r,world).mode=="ready" and gun.request_fire(player.pose,40),"Gun readiness and firing eligibility agree without waiting for interpolation")
	var hook=r.fishing[0];hook.weapon.elapsed=100;hook.weapon.hook_busy=true
	world.capture_cooldown_timers()
	expect(Instruments.harpoon_state(r,world).mode=="line","An attached line remains a line rather than a reload")
	hook.detach(false);hook.weapon.advance(320)
	expect(is_equal_approx(Instruments.harpoon_state(r,world).fraction,160.0/hook.weapon.cooldown),"Released hooks start a fresh reload even if the new timer exceeds the old one")
	var demo:=Demo.new();demo.quick_test=true;demo.quick_weapon=0;demo.refresh_weapons(world)
	var replacement=r.weapons[0];replacement.elapsed=32
	expect(is_equal_approx(world.render_reload_elapsed(replacement),32.0),"Changing test equipment cannot reuse the previous weapon's timer sample")
	world.depart();world.region.player.boost();world.region.player.boost_timer=120
	expect(is_equal_approx(world.render_boost_timer(),120.0),"A new dive cannot reuse the previous player's timer sample")
	world.dispose()
