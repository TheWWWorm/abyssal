extends SceneTree
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
const Info=preload("res://native/presentation/mission_info.gd")
var checks:=0
var failures:=0
var data: Dictionary
func expect(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func fixture():
	var session=Session.new();session.new_game(data,"Rendezvous",27)
	while session.campaign.chapter<27:session.campaign.next_chapter(session.counters)
	session.prepare_station(12)
	var world=World.new();world.configure(session);world.depart()
	return world
func settle_radio(region) -> Array:
	var spoken: Array=[]
	for i in 12:
		if region.active_transmission==null:region.update_radio()
		if region.active_transmission==null:break
		spoken.append(region.active_transmission.text_id)
		region.acknowledge_transmission()
	region.events.clear()
	return spoken
func enter_encounter(world) -> void:
	world.enter_region(11)
	var r=world.region
	expect(r.events.any(func(e):return e.kind=="briefing"),"Arrival queues the original rendezvous introduction")
	expect(world.session.dialogue(r.mission,0).map(func(e):return e.text_id)==[851],"Arrival uses the meeting introduction, without the kidnapping reveal")
	r.events.clear() # Acknowledge the arrival introduction, as its UI does.
	r.player.health.configure(100000,100000,100000);r.player.health.vulnerable=false
	r.player.set_throttle(0);r.player.pose.origin=Math.added(r.enemies[0].pose.origin,[0,0,-80000])
	world.advance(.04)
	expect(r.active_transmission==null,"Confrontation waits while Raymond is outside activation range")
	expect(Info.encounter_progress(r).is_empty(),"No recovery counter spoils the rendezvous")
	r.player.pose.origin=Math.added(r.enemies[0].pose.origin,[0,0,-40000])
	var before: int=r.elapsed_ms
	world.speed=8;world.advance(.04)
	expect(r.events.filter(func(e):return e.kind=="encounter_dialogue").size()==1,"Raymond's activation queues one confrontation")
	expect(r.active_transmission!=null and r.elapsed_ms==before+40,"Confrontation interrupts accelerated time in its first simulation step")
	world.advance(.2)
	expect(r.elapsed_ms==before+40,"The confrontation holds simulation until acknowledged")
	var dialogue: Array=world.session.dialogue(r.mission,3)
	expect(dialogue.size()==21 and dialogue[0].text_id==852 and dialogue[-1].text_id==872,"All original confrontation lines play before combat")
	r.acknowledge_transmission();r.events.clear()
	expect("Disable" in Info.instruction(r.mission,r),"Recovery objective is revealed after the confrontation")
	r.enemies[0].weapons=[]
func _initialize() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var world=fixture()
	expect("meeting point" in Info.instruction(world.session.campaign.primary,world.region),"Travel HUD describes the meeting without revealing the rescue")
	enter_encounter(world)
	var r=world.region;var raymond=r.enemies[0]
	expect(world.session.dialogue(r.mission,1).is_empty(),"Mission completion does not replay the pre-battle confrontation")
	raymond.health.damage(raymond.health.max_hull/2+1)
	r.step(40)
	expect(settle_radio(r)==[873,874],"Half-hull taunt and player reply retain their original order")
	raymond.health.damage(100000);r.step(40)
	expect(settle_radio(r)==[875],"Destroying the ship asks for recovery without directing the player away")
	expect("before it sinks" in Info.instruction(r.mission,r),"Wreck HUD explains the harpoon recovery and sinking deadline")
	for i in 100:r.step(40)
	expect(r.pending_mission==null and not r.timeline[3].fired and not r.timeline[4].fired,"Waiting beside an uncollected crate neither completes nor plays recovery dialogue")
	r.player.pose.origin=Math.added(raymond.pose.origin,[0,0,-8000]);r.player.pose.face([0,0,4096])
	var hook=r.fishing[0];hook.attach(raymond)
	for i in 100:
		r.step(40)
		if raymond.rescued():break
	expect(raymond.rescued(),"The fitted harpoon tows the protected container aboard")
	expect(settle_radio(r)==[876,877],"Best-catch praise and next-station instruction follow actual recovery in order")
	for i in 100:
		r.step(40)
		if r.pending_mission!=null:break
	expect(r.pending_mission==r.mission and not r.failed,"Collected container completes the rescue after dialogue")
	r.acknowledge_completion()
	expect(world.session.campaign.chapter==28 and world.session.campaign.primary.destination==12,"Rescue advances once to the Pecibel journey")
	world.dispose()
	# Losing the crate is a failure, not an alternative completion path.
	world=fixture();enter_encounter(world);r=world.region;raymond=r.enemies[0]
	raymond.health.damage(100000);r.step(40);settle_radio(r)
	for i in 1800:
		r.step(40)
		if r.failed:break
	expect(raymond.escaped and r.failed and r.mission.failed,"An untowed crate sinking out of reach fails the rescue")
	expect(not raymond.rescued() and r.pending_mission==null and world.session.campaign.chapter==27,"Sinking never counts as collection or advances the chapter")
	expect(not r.timeline[3].fired and not r.timeline[4].fired,"No catch praise or travel instruction plays after the crate is lost")
	world.dispose()
	print("STORY_RENDEZVOUS ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
