extends SceneTree
## Course selection and handling checks using the supplied compatible content.
const Session=preload("res://native/simulation/session.gd")
const World=preload("res://native/simulation/world.gd")
const Player=preload("res://native/simulation/player.gd")
const Stats=preload("res://native/simulation/ship_stats.gd")
const Math=preload("res://native/simulation/fixed_math.gd")
var data: Dictionary
var checks:=0
var failures:=0
func expect(ok: bool,why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	check_handling()
	check_objective_routes()
	print("NATIVE_NAVIGATION %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
func pilot(handling: float):
	var stats:=Stats.new();stats.hull=75;stats.base_steering=handling
	var player:=Player.new();player.configure(stats,22500,data.constants.dt["a:[S"])
	player.manual_roll=true;player.set_throttle(0);player.throttle=0
	return player
func check_handling() -> void:
	for handling in [0.67,1.1,1.82]:
		for target in [[100000,0,0],[0,0,-100000],[0,100000,0]]:
			var player=pilot(handling);player.autopilot_target=target
			var previous:=Vector3.BACK
			var desired: Vector3=Math.vector(target).normalized()
			var previous_error:=previous.angle_to(desired)
			var worst_step:=0.0
			var moved:=false
			for _tick in 12:
				player.advance(40)
				var facing: Vector3=Math.vector(player.pose.forward).normalized()
				var step:=previous.angle_to(facing)
				var error:=facing.angle_to(desired)
				worst_step=maxf(worst_step,step)
				moved=moved or step>0.001
				expect(error<previous_error,"Autopilot makes steady progress, including a destination directly astern")
				previous=facing;previous_error=error
			expect(moved and worst_step<=handling*40.0/3.0*TAU/4096.0+0.0007,"Each automatic turn stays within the hull's steering rate")
	var slow=pilot(0.67);var agile=pilot(1.82);var upgraded=pilot(0.67)
	upgraded.stats.steering_bonus=56
	for player in [slow,agile,upgraded]:player.autopilot_target=[100000,0,0];player.advance(40)
	var slow_angle:=Vector3.BACK.angle_to(Math.vector(slow.pose.forward).normalized())
	var agile_angle:=Vector3.BACK.angle_to(Math.vector(agile.pose.forward).normalized())
	var upgraded_angle:=Vector3.BACK.angle_to(Math.vector(upgraded.pose.forward).normalized())
	expect(agile_angle>slow_angle*2.5 and upgraded_angle>slow_angle*1.7,"Hull handling and steering upgrades both improve autopilot turns")
	var aligned=pilot(1.1);aligned.autopilot_target=[0,50,100000]
	aligned.advance(40)
	expect(aligned.pose.forward[0]==0 and aligned.pose.forward[1]>0,"A nearly aligned vertical course corrects pitch without adding an unrelated yaw")
	var banked=pilot(1.1);banked.pose.rotate_local("roll",1024);banked.autopilot_target=[100000,0,100000]
	var original_bank:=Vector3.UP.angle_to(Math.vector(banked.pose.up).normalized())
	banked.advance(40)
	var first_bank:=Vector3.UP.angle_to(Math.vector(banked.pose.up).normalized())
	expect(first_bank<original_bank and first_bank>original_bank-0.04,"An autopilot course rights a manually rolled hull gradually instead of snapping it level")
	for _tick in 60:banked.advance(40)
	expect(Vector3.UP.angle_to(Math.vector(banked.pose.up).normalized())<0.04,"Autopilot returns a manually rolled hull to level while steering to its destination")
	var rolling=pilot(1.1);var turning=pilot(1.1)
	for _tick in 15:rolling.set_roll(1);rolling.advance(40);turning.steer(1,0,40);turning.advance(40)
	var roll_angle:=Vector3.RIGHT.angle_to(Math.vector(rolling.pose.right).normalized())
	var yaw_angle:=Vector3.BACK.angle_to(Math.vector(turning.pose.forward).normalized())
	expect(roll_angle>yaw_angle*1.4 and roll_angle<yaw_angle*1.6,"Manual roll is moderately faster while retaining hull handling")
func check_objective_routes() -> void:
	var session:=Session.new();session.new_game(data,"Navigation checks",91)
	while session.campaign.chapter<48:session.campaign.next_chapter(session.counters)
	session.campaign.primary.kind=-1;session.prepare_station(0)
	var world:=World.new();world.configure(session);world.depart()
	var near_station:=-1
	var far_station:=-1
	for station in session.stations:
		if station.id==session.station_id:continue
		if world.stream_distance(station.id)<world.stream_range():near_station=station.id
		else:far_station=station.id
	expect(near_station>=0 and far_station>=0,"Imported atlas provides near and far destinations")
	expect(world.route_to_objective(near_station) and world.stream_destination==near_station and world.gate_navigation,"Reachable remote objectives use the departure gate")
	expect(world.resume_stream and world.resume_destination==near_station,"An objective transit route can be resumed")
	world.cancel_autopilot()
	expect(world.route_to_objective(far_station) and world.destination==far_station and world.stream_destination<0,"Objectives beyond engine reach retain continuous ocean travel")
	world.cancel_autopilot()
	expect(world.route_to_objective(session.station_id) and world.destination==session.station_id and not world.gate_navigation,"Local station objectives remain local courses")
	world.cancel_autopilot()
	world.region.success={"kind":"no_enemies"}
	expect(not world.route_to_objective(near_station) and not world.autopilot,"An encounter denial is preserved instead of falling back to a forbidden direct course")
	world.region.success=null
	expect(not world.route_to_objective(-1),"Invalid objective destinations are rejected")
	world.dispose()
