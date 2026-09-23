extends SceneTree
## Check physical directions after conversion to the visible ocean frame.
const Session=preload("res://native/simulation/session.gd")
const Region=preload("res://native/simulation/region.gd")
const NPC=preload("res://native/simulation/npc.gd")
const Special=preload("res://native/simulation/special_actor.gd")
const Creature=preload("res://native/simulation/creature.gd")
const Player=preload("res://native/simulation/player.gd")
const Pose=preload("res://native/simulation/ship_transform.gd")
const Library=preload("res://scripts/model_library.gd")
var data: Dictionary
var checks:=0
var failures:=0
func expect(ok: bool,why: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(why)
func fixture(chapter: int,contract: int=-1):
 var session:=Session.new();session.new_game(data,"Coordinate check",812)
 while session.campaign.chapter<chapter:session.campaign.next_chapter(session.counters)
 if contract>=0:
  session.campaign.primary.kind=-1
  var job=preload("res://native/simulation/mission.gd").new();job.kind=contract;job.destination=0;job.total=10;job.minimum=5;job.difficulty=2;job.target_kind=0
  session.campaign.secondary=job;session.prepare_station(0)
 else:session.prepare_station(session.campaign.primary.destination)
 session.docked=false
 var region:=Region.new();region.configure(session);return region
func _initialize():call_deferred("run")
func run():
 data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
 check_vertical_motion()
 check_formations()
 check_gates()
 check_finale()
 print("NATIVE_COORDINATES %d checks; %d failures"%[checks,failures])
 quit(1 if failures else 0)

func check_vertical_motion() -> void:
 var region=fixture(1);var session=region.session
 var player:=Player.new();player.configure(session.ship,22500,data.constants.dt["a:[S"]);player.set_throttle(0);player.throttle=0
 player.pose.origin=[0,-800,0];player.advance(40)
 expect(player.pose.godot_transform().origin.y>0 and player.depth==22400,"A standalone player above the station reads a shallower depth")
 player.pose.origin=[0,800,0];player.advance(40)
 expect(player.pose.godot_transform().origin.y<0 and player.depth==22600,"A standalone player below the station reads a deeper depth")
 var wreck:=NPC.new();wreck.configure(0,2,true,[3000,4000,5000],data,1,session.rng);wreck.health.configure(20,0,0);wreck.has_explosion=false
 wreck.health.damage(20);wreck.advance(40)
 var at: Vector3=wreck.pose.godot_transform().origin
 wreck.advance(40)
 expect(wreck.state==4 and wreck.pose.godot_transform().origin.y<at.y and wreck.capturable,"A destroyed ship sinks while remaining salvageable")
 at=wreck.pose.godot_transform().origin;wreck.towing=true;wreck.advance(40)
 expect(wreck.pose.godot_transform().origin==at,"Towing suspends wreck sinking")
 wreck.towing=false;wreck.pose.origin[1]=wreck.origin[1]+30000;wreck.advance(0)
 expect(not wreck.escaped and wreck.health.enabled,"A wreck is recoverable at the 300-metre sinking boundary")
 wreck.advance(2)
 expect(wreck.escaped and not wreck.health.enabled,"A wreck escapes only after sinking past its recovery limit")
 var fish:=Creature.new();fish.configure(4422,data.tables.creatures[0],session.rng,data.constants.dt["a:[S"]);fish.pose.origin=[0,0,0]
 fish.speed=fish.cruise_speed()*5.0;fish.release()
 expect(is_equal_approx(fish.speed,fish.cruise_speed()),"A released fish returns to cruising speed after a struggle")
 fish.pose.origin=[0,0,41000];fish.pose.set_euler(0,0,0);fish.fresh=false
 fish.advance(40,session.rng,[0,0,0],[0,0,4096])
 expect(fish.pose.origin[2]>40000 and not fish.fresh,"A fish still ahead of the camera does not jump to a random spawn")
 fish.pose.origin=[0,0,-41000];fish.advance(40,session.rng,[0,0,0],[0,0,4096])
 expect(fish.fresh and preload("res://native/simulation/fixed_math.gd").length_of(fish.pose.origin)<=30100,"A fish that leaves behind the camera recycles into the far water")
 fish.pose.origin=[0,0,0]
 fish.health.hull=0;fish.advance(40,session.rng,[0,0,0]);at=fish.pose.godot_transform().origin
 fish.advance(60,session.rng,[0,0,0])
 expect(fish.state==4 and fish.meat and fish.pose.godot_transform().origin.y>at.y,"A dead fish floats upward as collectible meat")
 at=fish.pose.godot_transform().origin;fish.hooked=true;fish.advance(60,session.rng,[0,0,0])
 expect(fish.pose.godot_transform().origin==at,"A hooked carcass leaves vertical movement to the tow")
 var mine:=Special.new();mine.configure_special("mine",13,true,[4000,5000,6000],data,session.rng);mine.health.configure(4,0,0)
 at=mine.pose.godot_transform().origin;mine.advance(2048)
 expect(mine.pose.godot_transform().origin.y>at.y and mine.pose.origin[0]==4000 and mine.pose.origin[2]==6000,"A mine bobs upward above its mooring")
 mine.advance(2048)
 expect(mine.pose.godot_transform().origin==at,"The mine returns to its mooring after a full bob")
 var bubbles=preload("res://native/simulation/bubble_trail.gd").new();bubbles.advance([0,0,0],120,session.rng);bubbles.advance([0,0,0],40,session.rng)
 expect(Library.point(bubbles.position[0]).y>0,"Native bubbles still rise without a second conversion")
 # Native aiming follows the ship through both upward and downward pitches.
 for pitch in [-1024,-512,512,1024]:
  var pose:=Pose.new();pose.set_euler(pitch,300,0)
  var weapon=preload("res://native/simulation/weapon.gd").new();weapon.configure(1,1,3000,100,10,[0,0,0]);weapon.request_fire(pose,40)
  expect(Library.point(weapon.velocities[0]).normalized().dot(-pose.godot_transform().basis.z)>.999,"Shots follow the rendered bow at pitch %d"%pitch)
 region.dispose()

func check_formations() -> void:
 var below=fixture(45)
 expect(Library.point(below.school_route.points[0]).y<0,"Chapter 45 reinforcements approach from below the station")
 for actor in below.friends.slice(4):
  expect(actor.pose.godot_transform().origin.y<0 and actor.route.points==below.school_route.points,"Deep reinforcements spawn on the same side as their converted route")
 below.dispose()
 var escorts=fixture(25)
 var offset: Vector3=escorts.friends[0].pose.godot_transform().origin-escorts.player.pose.godot_transform().origin
 expect(offset.is_equal_approx(Vector3(-8,3.4,-7)),"The chapter 25 companion starts on the authored side and above the player")
 expect(escorts.friends[0].route.current()[0]>0,"The companion's escape route uses the station's horizontal frame")
 expect(escorts.enemies[0].pose.godot_transform().origin.y<0 and escorts.enemies[-1].pose.godot_transform().origin.y>0,"The chapter 25 guard formation rises across its authored depth range")
 escorts.dispose()
 var recovery=fixture(31)
 offset=recovery.friends[0].pose.godot_transform().origin-recovery.player.pose.godot_transform().origin
 expect(offset.is_equal_approx(Vector3(-4,.4,-4)),"Recovery escorts convert offsets without mirroring the player's position")
 expect(recovery.friends[0].route.points==recovery.route.points and recovery.route.current()[0]>0,"Copying a native mission route does not convert it twice")
 recovery.dispose()
 var convoy=fixture(29)
 expect(convoy.friends[0].pose.godot_transform().origin.y<0 and convoy.friends[1].pose.godot_transform().origin.y>0,"Convoy ships retain their authored below/above ordering")
 expect(convoy.friends.all(func(actor):return actor.pose.origin[0]>0) and convoy.enemies.all(func(actor):return actor.pose.origin[0]>0),"Convoy guards and freighters occupy the same converted side of the station")
 expect(convoy.friends[0].shapes[0].offset[1]<0,"Freighter collision offset remains above its origin")
 expect(Library.point(convoy.friends[0].explosion_offsets[0]).y>0 and Library.point(convoy.friends[0].explosion_offsets[1]).y<0,"Freighter bursts use converted world offsets")
 convoy.dispose()
 for chapter in [19,23,27,35,42,43]:
  var region=fixture(chapter)
  var group: Array=region.enemies if chapter!=43 else region.friends.slice(2)
  expect(group.all(func(actor):return actor.pose.origin[0]>0 if chapter==19 else actor.pose.origin[0]<0),"Chapter %d actors use the authored station-relative side"%chapter)
  region.dispose()
 for kind in [1,2,3,4,5,6]:
  var region=fixture(12,kind)
  if kind in [1,2,3]:
   expect(region.route.points.all(func(point):return point[0]<0),"Contract %d patrol points use the converted horizontal frame"%kind)
  elif kind==4:
   expect(region.friends[0].pose.origin[1]>0 and region.friends[1].pose.origin[1]<0,"Escort-contract freighters use the authored depth ordering")
  elif kind==5:
   var mark: Vector3=Library.point(region.route.points[1])
   var targets: Array=region.enemies.filter(func(actor):return actor is Special and actor.kind=="freighter")
   expect(not targets.is_empty() and targets.all(func(actor):return actor.pose.godot_transform().origin.distance_to(mark)<350),"Intercept targets scatter about a native route point only once")
  else:
   expect(region.school_route.points[0][0]<0 and region.creatures.all(func(actor):return actor.pose.origin[0]<0),"Protected fish and their route share the converted side")
  region.dispose()

func check_gates() -> void:
 var region=fixture(1);var session=region.session;region.dispose()
 for tech in [2,8]:
  session.stations[session.station_id].tech=tech
  region=Region.new();region.configure(session)
  expect(region.gates[0][0]<0 if tech>4 else region.gates[0][0]>0,"Gate placement uses the same horizontal frame as the station at tech %d"%tech)
  var rounds=preload("res://native/simulation/region_setup.gd").new();rounds.configure(region);rounds.station_rounds()
  expect(region.school_route.points[0][0]==region.gates[0][0] and region.school_route.points[1][0]==region.gates[1][0],"Station patrols retain native gate coordinates without double conversion")
  region.dispose()

func check_finale() -> void:
 var region=fixture(47);region.finale_stage=2
 var actor=region.enemies[-1];actor.route=preload("res://native/simulation/route.gd").new();actor.route.configure([0,0,0]);actor.route.advance([0,0,0])
 region.advance_finale(40)
 expect(region.finale_player_route.points[0][1]>0 and region.friends[0].route.points[1][1]>0,"Finale holding routes remain below the station")
 region.timeline[10].fired=true;region.advance_finale(40)
 var height: float=Library.point(region.finale_station_offset).y
 expect(height>0 and Library.point(region.cinematic_camera).y>0,"The station lifts upward while the establishing camera starts above it")
 region.advance_finale(40)
 expect(Library.point(region.finale_station_offset).y>height,"The finale station continues ascending")
 region.timeline[12].acknowledged=true;region.advance_finale(40)
 expect(region.player.pose.godot_transform().origin.y<0 and Library.point(region.cinematic_camera).y>region.player.pose.godot_transform().origin.y,"The player stays below the departing station with the camera above the ship")
 region.timeline[15].acknowledged=true;region.advance_finale(40)
 expect(Library.point(region.cinematic_camera).y<region.friends[0].pose.godot_transform().origin.y,"The first companion shot retains its low camera angle")
 region.timeline[17].acknowledged=true;region.advance_finale(40)
 expect(Library.point(region.cinematic_camera).y>region.friends[1].pose.godot_transform().origin.y,"The second companion shot retains its high camera angle")
 region.dispose()
