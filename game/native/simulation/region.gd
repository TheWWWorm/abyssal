extends RefCounted
const PRESSURE_GRACE_MS := 5000
## Native fixed-step flight, combat, fishing and mission event orchestration.
const Math = preload("res://native/simulation/fixed_math.gd")
const Player = preload("res://native/simulation/player.gd")
const Loadout = preload("res://native/simulation/weapon_loadout.gd")
const Weapon = preload("res://native/simulation/weapon.gd")
const Fishing = preload("res://native/simulation/fishing.gd")
const Station = preload("res://native/simulation/station_body.gd")
const Route = preload("res://native/simulation/route.gd")
const Timeline = preload("res://native/simulation/timeline.gd")
const Special = preload("res://native/simulation/special_actor.gd")
const Setup = preload("res://native/simulation/region_setup.gd")
var session
var mission
var sine: Array = []
var player := Player.new()
var station := Station.new()
var loadout := Loadout.new()
var creatures: Array = []
var enemies: Array = []
var friends: Array = []
var weapons: Array = []
var fishing: Array = []
var gates: Array = []
var route := Route.new()
var school_route = null
var success = null
var failure = null
var timeline: Array = []
var enemy_count := 0
var friendly_count := 0
var special_destroyed := 0
var elapsed_ms := 0
var time_limit := 0
var pressure_ms := 0
var pressure_damage_ms := 0
var events: Array = []
var visual_events: Array = []
var audio_events: Array = []
var audio_serial := 0
var pending_mission = null
var failed := false
var finale_stage := 0
var cinematic_camera: Array = []
var cinematic_target := ""
var finale_station_offset: Array = [0,0,0]
var active_transmission = null
var encounter_resolved := false
var hook_was_down := false
var story_departed := false
var finale_motion := 0
var finale_player_route = null
func configure(owner_session) -> void:
	session=owner_session; mission=session.campaign.active
	sine=session.data.constants.dt["a:[S"]
	var record: Dictionary = session.stations[session.station_id]
	player.configure(session.ship,record.depth,sine); player.pose.origin=[10,0,-30000]
	player.unbounded_world=true
	player.health.hull=session.hull; player.health.shield=session.shield; player.health.armor=session.armor
	station.configure(record,session.is_colonist_station(),sine,session.data.get("station_geometry",{}))
	player.collision_groups=[[station]]
	gates=session.world_layout.clear_gates(session,record,gate_positions(record,sine),sine)
	var setup := Setup.new(); setup.configure(self); setup.populate()
	if mission.story:
		for record_event in session.data.timelines.get(str(session.campaign.chapter),[]): timeline.append(Timeline.new().configure(record_event))
		# The last chapter's calls about Raoul name him as the last of the
		# hostile list (cy: "aw_arr_a.length - 1"), an expression the import
		# reads as nought; here he is the last ship placed.
		if session.campaign.chapter==47 and not enemies.is_empty():
			for entry in timeline:
				if entry.kind in [1,17,19]:entry.values=[enemies.size()-1]
	loadout.configure(session.ship,session.data)
	for weapon in loadout.all_weapons():
		weapon.targets=enemies+creatures
		weapon.terrain_collision=station.contains
		if weapon.fishing:
			var hook := Fishing.new(); hook.weapon=weapon; hook.player=player; hook.session=session; hook.slow_percent=weapon.slow_percent
			hook.visible_to_camera=func(point): return Math.dot_long(player.pose.forward,Math.normalize_vector(Math.subtracted(point,player.pose.origin)))>1700
			fishing.append(hook)
		else: weapons.append(weapon)
	# Who fights whom, in the order the phone game's cy lists them: pirates
	# go for the player, then for the player's friends; in the missions that
	# guard something (the school, the capsules, the convoy) they go for the
	# charges first, and the player is listed again ahead of the friends,
	# which the original's random choice of target can be seen to favour.
	var charges: Array=creatures if mission.kind==6 else ([] if mission.kind in [11,4] else [player])
	var hostile_targets: Array=charges.duplicate()
	if mission.kind==6:hostile_targets.append(player)
	if not friends.is_empty() or mission.kind==12 and not mission.story:
		hostile_targets+=([] if mission.kind in [6,11,4] else [player])+friends
	for actor in enemies+friends:
		actor.obstacle_groups=[station]; actor.player=player
		if actor in enemies: actor.targets=hostile_targets
		else: actor.targets=enemies
	configure_npc_weapons(enemies,true)
	configure_npc_weapons(friends,false)
	recount()
	for entry in timeline:entry.poll(self)
static func gate_positions(station: Dictionary,sine_table: Array) -> Array:
	var result: Array=[]
	for i in [1,2]:
		var transform=preload("res://native/simulation/ship_transform.gd").new();transform.math.sine_table=sine_table
		var yaw: int=(300 if station.tech>4 else -300)*i
		transform.set_euler(0,-yaw,0);result.append(transform.rotate_direction([0,0,(90000 if i==1 else 110000)+yaw*3]))
	consolidate_gate_pair(result)
	return result

func consolidate_gates() -> void:
	consolidate_gate_pair(gates)

static func consolidate_gate_pair(pair: Array) -> void:
	if pair.size()<2:return
	# A nearby arrival/departure pair shares one physical portal. Keep the two
	# logical slots for transit compatibility, but use one stable world position.
	var a: Array=pair[0];var b: Array=pair[1]
	if Vector3(a[0]-b[0],a[1]-b[1],a[2]-b[2]).length()<=60000.0:
		pair[1]=pair[0].duplicate()

func gate_index(index: int) -> int:
	return 0 if index==1 and gates[0]==gates[1] else index

func gate_yaw(index: int) -> int:
	# A relocated gate and its arriving ship still face the owning station.
	var point: Array=gates[gate_index(index)]
	return posmod(roundi(atan2(-float(point[0]),-float(point[2]))*4096.0/TAU),4096)

static func gate_yaw_for(station: Dictionary,index: int) -> int:
	return 2048-(300 if station.tech>4 else -300)*(index+1)

func configure_npc_weapons(actors: Array,hostile: bool) -> void:
	# One pool of shots for all the pirates and one for all the friends, as
	# the original allots them (cy.i): each side's guns grow with the pilot's
	# rank and the chapter, the friends' a little weaker and slower to
	# cycle. The aquar fire laser_aqua from their own deeper, slower pool.
	if actors.is_empty():return
	var power: int=int(float(session.counters.k)/1.5)+int(float(session.campaign.chapter)/5.0)
	var guns:=Weapon.new();guns.configure(3+power if hostile else 3+int(power*0.8),4 if hostile else 10,3000,500,16,[0,0,0])
	guns.model_id=int(session.data.constants.ah["a:[S"][8 if hostile else 2]);guns.special_kill=not hostile
	guns.targets=actors[0].targets;guns.terrain_collision=station.contains;weapons.append(guns)
	var bolts:=Weapon.new();bolts.configure(3+power if hostile else 5+power,6 if hostile else 10,3000,600,15,[0,0,0]);bolts.model_id=6767
	bolts.targets=guns.targets;bolts.terrain_collision=station.contains;weapons.append(bolts)
	for actor in actors:
		if actor is Special:continue
		actor.weapons=[bolts if actor.original_model_id==19 else guns]
func recount() -> void:
	enemy_count=enemies.filter(func(actor): return actor.health.hull>0 and not actor.health.special_kill).size()
	friendly_count=friends.filter(func(actor): return actor.health.hull>0).size()
func step_ambient(delta_ms: int, rng) -> void:
	"""The water seen from a berth: the wildlife and the station's own ships
	carry on while the submarine is docked, drawing on the given sequence
	rather than the game's. Nothing fights, nothing fires, nothing is
	scored; a ship that was fighting or sunk stays as it is."""
	elapsed_ms+=delta_ms
	for actor in creatures: actor.advance(delta_ms,rng,[0,0,0],[0,0,4096])
	for actor in friends:
		if actor is Special or actor.state in [3,4] or not actor.health.enabled: continue
		var own=actor.rng;actor.rng=rng;actor.weapons=[];actor.advance(delta_ms);actor.rng=own
		actor.events.clear()
func step(delta_ms: int, input: Dictionary={}) -> void:
	if session.docked or failed or pending_mission!=null: return
	if cinematic(): input={}
	elapsed_ms+=delta_ms; session.elapsed_ms+=delta_ms
	audio_events=audio_events.filter(func(event): return elapsed_ms-event.time<2000)
	visual_events=visual_events.filter(func(event): return elapsed_ms-event.time<event.duration)
	player.adjust_throttle(int(input.get("throttle",0)),delta_ms)
	player.steer(float(input.get("yaw",0)),float(input.get("pitch",0)),delta_ms)
	player.set_strafe(float(input.get("strafe",0)))
	player.mouse_steer(float(input.get("mouse_x",0)),float(input.get("mouse_y",0)))
	if input.get("boost",false) and player.boost(): audio_event("boost")
	if input.get("fire",false): loadout.fire(player.pose,delta_ms,input.get("aim_point"))
	if input.get("guns",false): loadout.fire_kind(player.pose,delta_ms,false,input.get("aim_point"))
	var hook_down: bool=input.get("hook",false)
	if hook_down and not hook_was_down and fishing.any(func(line):return line.hooked):
		for line in fishing:
			if line.hooked:line.release()
	elif hook_down:loadout.fire_kind(player.pose,delta_ms,true,input.get("aim_point"))
	hook_was_down=hook_down
	player.events.clear()
	player.advance(delta_ms)
	if player.depth>int(session.counters.t): session.counters.t=player.depth
	elif player.depth<int(session.counters.u): session.counters.u=player.depth
	for actor in creatures:
		actor.advance(delta_ms,session.rng,player.pose.origin,player.pose.forward)
		if actor.constrained and school_route!=null and actor.health.enabled:
			var path=school_route.current()
			if path!=null:
				actor.pose.face(Math.normalize_vector(Math.subtracted(path,actor.pose.origin)))
	for actor in enemies+friends:
		var mine_idle: bool = actor is Special and actor.kind=="mine" and actor.state!=1
		actor.advance(delta_ms)
		if mine_idle and actor.state==1: audio_event("mine",actor.pose.origin)
	for weapon in weapons: weapon.advance(delta_ms)
	for hook in fishing:
		hook.advance(delta_ms)
		for cue in hook.audio_events: audio_event(cue.kind,cue.position)
		hook.audio_events.clear()
		for feedback in hook.feedback:events.append({"kind":"notice","text":feedback})
		hook.feedback.clear()
	route.advance(player.pose.origin)
	if school_route!=null and not creatures.is_empty(): school_route.advance(creatures[0].pose.origin)
	for actor in creatures+enemies+friends:
		for event in actor.events:
			if event in ["killed","capsule_destroyed","debris_destroyed"]:
				# The aquar (19) is a ship that dies as a fish: one burst, fischtod, tiertot.
				var as_creature: bool=actor.is_creature or actor.model_id==19
				visual_event({"kind":"explosion","position":actor.pose.origin.duplicate(),"creature":as_creature,"delays":[0] if as_creature else actor.explosion_delays.duplicate(),"offsets":[[0,0,0]] if as_creature else actor.explosion_offsets.duplicate(true),"duration":4000 if as_creature else actor.explosion_duration})
			if event=="killed" and actor in enemies and actor.model_id!=13 and not actor.health.special_kill:
				session.counters.f+=1; session.medals.kills+=1
				if actor.faction==2: session.counters.o+=1; session.medals.pirates+=1
			if event=="killed" and actor.is_creature: session.counters.g+=1
			if event=="capsule_destroyed": special_destroyed+=1
			if event in ["caught","cargo_full","salvaged","rescued","meat_collected"]: events.append({"kind":"notice","text":"Cannot collect catch · cargo hold is full. Make room at a station." if event=="cargo_full" else event.replace("_"," ").capitalize()})
		actor.events.clear()
	var all_weapons: Array = weapons.duplicate()
	for weapon in loadout.all_weapons():
		if not weapon in all_weapons: all_weapons.append(weapon)
	for weapon in all_weapons:
		for impact in weapon.impacts:
			# A held harpoon rechecks its attachment each tick. It is not a
			# new impact: repeated flashes made a white trail behind the catch.
			if not weapon.fishing:
				# Presentation reads who was hit; the shot itself is unchanged.
				visual_event({"kind":"impact","position":impact.position.duplicate(),"duration":400,"player":impact.target==player})
				audio_event("impact",impact.position)
		weapon.impacts.clear()
	pressure(delta_ms)
	recount(); session.update_rank()
	session.hull=player.health.hull; session.shield=player.health.shield; session.armor=player.health.armor
	if player.health.hull<=0:
		visual_event({"kind":"explosion","position":player.pose.origin.duplicate(),"creature":false,"delays":[0],"offsets":[[0,0,0]],"duration":4000})
		failed=true; events.append({"kind":"death","text":"Hull lost. Reload your last station save."}); return
	if failure!=null and failure.evaluate(self,elapsed_ms) or time_limit>0 and elapsed_ms>time_limit:
		mission.failed=true;failed=true;events.append({"kind":"mission_failed","text":"Mission failed."});return
	encounter_resolved=success!=null and success.evaluate(self,elapsed_ms)
	update_radio()
	scripted_events(delta_ms)
	# The last chapter's encounter ends only through its staged finale.
	if session.campaign.chapter==47 and mission.story and finale_stage<10:return
	# Persistent milestones can complete while a side encounter stays active.
	var persistent=session.campaign.completion(false,elapsed_ms,session.station_id,session.ship,session.counters)
	if persistent!=null and persistent!=mission:pending_mission=persistent
	elif (encounter_resolved or persistent==mission) and active_transmission==null:
		# Deliver any now-satisfied dialogue chain before resolving the encounter.
		if not update_radio():pending_mission=mission
	if pending_mission!=null:pending_mission.completed=true;events.append({"kind":"mission_complete","mission":pending_mission})

func update_radio() -> bool:
	for entry in timeline:entry.poll(self)
	if active_transmission!=null:return true
	for entry in timeline:
		if entry.evaluate(self):
			active_transmission=entry;events.append({"kind":"transmission","entry":entry});return true
	return false

func audio_event(kind: String, position: Array=[], delay_ms: int=0) -> void:
	audio_serial+=1
	if audio_events.size()>=256: audio_events.pop_front()
	audio_events.append({"serial":audio_serial,"kind":kind,"position":position.duplicate(),"time":elapsed_ms+delay_ms})
func visual_event(event: Dictionary) -> void:
	if event.kind=="explosion":
		for delay in event.delays: audio_event("creature_death" if event.creature else "explosion",event.position,int(delay))
	event.time=elapsed_ms
	if visual_events.size()>=256: visual_events.pop_front()
	visual_events.append(event)
func pressure(delta_ms: int) -> void:
	var depth: int = player.depth
	if depth>=session.ship.minimum_depth and depth<=session.ship.maximum_depth:
		pressure_ms=0; pressure_damage_ms=0; return
	if pressure_ms==0: audio_event("pressure")
	pressure_ms+=delta_ms; pressure_damage_ms+=delta_ms
	if pressure_ms>PRESSURE_GRACE_MS and pressure_damage_ms>250:
		pressure_damage_ms=0
		var deep: bool = depth>session.ship.maximum_depth
		player.health.damage(2+maxi(0,(depth-30000 if deep else 15000-depth)/2000),"shield" if deep else "armor")
func cinematic() -> bool:
	return mission.story and session.campaign.chapter==47 and finale_stage>=2 and finale_stage<8
func scripted_events(delta_ms: int) -> void:
	# The story's own stage directions (br/cy): the companion of chapter 21
	# sets off at once; Ayumi's ship in chapter 25 runs for it after the
	# fourth call and is gone at the end of its route; the reinforcements of
	# chapter 43 wake on the first call; and chapter 47 plays its finale.
	if not mission.story:return
	match session.campaign.chapter:
		21:
			if not story_departed and not friends.is_empty():friends[0].activate();story_departed=true
		25:
			if friends.is_empty():return
			if timeline.size()>3 and timeline[3].fired:friends[0].set_speed(10);friends[0].targets=[]
			if friends[0].route!=null and friends[0].route.complete():friends[0].health.enabled=false
		43:
			if not timeline.is_empty() and timeline[0].fired and not timeline[0].acknowledged:
				for actor in friends:actor.activate()
		47:advance_finale(delta_ms)
func advance_finale(delta_ms: int) -> void:
	# Raoul's ship is beaten down to a hundred on the third call; after the
	# seventh it turns into the capsule that runs for the station with the
	# camera on it; the station lifts away on the eleventh; then the shots
	# of the player and each friend in turn, and the credits after the
	# twenty-fifth. Each acknowledged call moves the stage on.
	if enemies.is_empty() or timeline.size()<25:return
	var actor=enemies[-1]
	if timeline[2].fired and finale_stage==0:
		actor.health.configure(100,0,0);finale_stage=1
	elif timeline[6].acknowledged and finale_stage==1:
		actor.model_id=9994;actor.health.set_hull(32000);actor.targets=[];actor.weapons=[];actor.route=Route.new();actor.route.configure([0,0,0]);actor.following=true;actor.activate();actor.set_speed(6)
		for escort in friends:
			escort.targets=[];escort.weapons=[];escort.route=Route.new();escort.route.configure([0,0,0])
		cinematic_camera=Math.added(actor.pose.origin,[0,0,-4000]);cinematic_target="capsule";finale_stage=2
	elif timeline[10].fired and finale_stage==2:
		cinematic_camera=Math.from_source([15000,8000,28000]);cinematic_target="station";finale_stage=3
	elif finale_stage==2 and actor.route.complete():
		actor.set_position([0,0,0]);actor.dormant();actor.health.set_hull(0)
		for escort in friends:
			escort.route=Route.new();escort.route.configure_source([40000,0,0,36000,-3000,4000],true)
		finale_player_route=Route.new();finale_player_route.configure_source([42000,-2000,3000,30000,-1000,-5000],true)
		player.autopilot_target=finale_player_route.points[-1]
	if finale_stage==3:
		finale_motion+=delta_ms/4
		finale_station_offset[1]-=delta_ms*2+finale_motion
		if timeline[12].acknowledged:
			player.pose.origin=Math.from_source([44000,-5000,1000]);cinematic_camera=Math.from_source([33000,-4000,2000]);cinematic_target="player";finale_stage=4
	if finale_stage==4 and timeline[15].acknowledged:
		cinematic_camera=Math.added(friends[0].pose.origin,Math.from_source([5000,-2000,0]));cinematic_target="friend0";finale_stage=5
	if finale_stage==5 and timeline[17].acknowledged:
		cinematic_camera=Math.added(friends[1].pose.origin,Math.from_source([-5000,2000,0]));cinematic_target="friend1";finale_stage=6
	if finale_stage==6 and timeline[19].acknowledged:
		cinematic_camera=Math.added(friends[1].pose.origin,Math.from_source([0,1000,8000]));cinematic_target="friend1";finale_stage=7
	if finale_stage==7 and timeline[24].acknowledged:
		player.pose.origin=Math.from_source([44000,-5000,1000]);cinematic_camera=[];cinematic_target="";finale_stage=8
		events.append({"kind":"credits"})
func acknowledge_credits() -> void:
	if finale_stage!=8:return
	finale_stage=10;pending_mission=mission;mission.completed=true
	enemies[-1].state=4;enemies[-1].health.enabled=false
	player.autopilot_target=null;finale_player_route=null
	events.append({"kind":"mission_complete","mission":mission})
func acknowledge_transmission() -> void:
	if active_transmission!=null: active_transmission.acknowledged=true; active_transmission=null
func acknowledge_completion() -> void:
	if pending_mission==null: return
	var closes_encounter: bool = pending_mission==mission
	session.complete_mission(pending_mission); pending_mission=null
	# A global milestone must not replace the player's active local contract.
	if not closes_encounter: return
	success=null; failure=null; time_limit=0
	route=Route.new()
	if finale_stage==10:timeline=[];active_transmission=null
	mission=preload("res://native/simulation/mission.gd").new(); session.campaign.active=mission
func danger() -> bool:
	if failed or pending_mission!=null or active_transmission!=null or cinematic() or player.outside_depth_limits or player.contact: return true
	# Pressure starts at the equipment limit, before bb's wider visual margin.
	if player.depth<player.stats.minimum_depth or player.depth>player.stats.maximum_depth: return true
	for hook in fishing:
		if hook.hooked: return true
	for actor in enemies:
		if actor.state not in [3,4,999] and actor.health.hull>0 and preload("res://native/simulation/npc.gd").within(actor.pose.origin,player.pose.origin,55000): return true
	return false
func dispose() -> void:
	for actor in enemies+friends:
		actor.targets=[]; actor.player=null; actor.weapons=[]; actor.obstacle_groups=[]; actor.target=null
	for weapon in weapons+loadout.all_weapons(): weapon.targets=[]; weapon.terrain_collision=Callable(); weapon.hooked_target=null
	for hook in fishing: hook.target=null; hook.player=null; hook.session=null; hook.visible_to_camera=Callable()
	player.autopilot_target=null; player.collision_groups=[]
