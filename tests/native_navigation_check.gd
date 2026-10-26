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
	check_stream_connections()
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
			# bb.b adds (course - heading)*dt*5/4096 a tick: at most about a
			# twentieth of a half turn in 40 ms.
			expect(moved and worst_step<=40.0*5.0/4096.0*PI+0.0007,"Each automatic turn stays within the original's blend")
	# The original's autopilot turn ignores hull handling and steering
	# equipment; those only change the pilot's own helm.
	var slow=pilot(0.67);var agile=pilot(1.82);var upgraded=pilot(0.67)
	upgraded.stats.steering_bonus=56
	for player in [slow,agile,upgraded]:player.autopilot_target=[100000,0,0]
	for _tick in 10:
		for player in [slow,agile,upgraded]:player.advance(40)
	var slow_angle:=Vector3.BACK.angle_to(Math.vector(slow.pose.forward).normalized())
	var agile_angle:=Vector3.BACK.angle_to(Math.vector(agile.pose.forward).normalized())
	var upgraded_angle:=Vector3.BACK.angle_to(Math.vector(upgraded.pose.forward).normalized())
	expect(absf(agile_angle-slow_angle)<.002 and absf(upgraded_angle-slow_angle)<.002,"Autopilot turns at the original's rate whatever the hull")
	# Even the least agile hull comes about in a few seconds instead of
	# flying a wide loop, and the turn eases out instead of stopping dead.
	var about=pilot(0.67);about.autopilot_target=[0,0,-100000]
	var rates: Array=[];var heading:=Vector3.BACK
	for _tick in 100:
		about.advance(40)
		var facing: Vector3=Math.vector(about.pose.forward).normalized()
		rates.append(heading.angle_to(facing));heading=facing
	expect(heading.angle_to(Vector3.FORWARD)<deg_to_rad(5),"Autopilot comes about within four seconds on the slowest hull")
	var fastest: float=rates.max()
	expect(rates[0]<fastest*.5 and rates[-1]<fastest*.1,"An automatic turn picks up and eases out rather than starting and stopping at full rate")
	var level=pilot(1.1);level.autopilot_target=[100000,30000,60000]
	var worst_tilt:=0.0
	for _tick in 60:
		level.advance(40)
		worst_tilt=maxf(worst_tilt,absf(Math.vector(level.pose.right).normalized().y))
	expect(worst_tilt<.01,"A climbing, turning autopilot course keeps the horizon level (%.4f)"%worst_tilt)
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
	world.objective_travel_mode=World.ObjectiveTravel.OPEN_WATER
	expect(world.route_to_objective(near_station) and world.destination==near_station and world.stream_destination<0 and not world.gate_navigation,"Open-water preference takes a reachable objective through the continuous ocean")
	expect(not world.resume_stream and world.resume_destination==near_station,"Open-water objective courses retain their route type for Resume")
	world.cancel_autopilot()
	expect(world.plan_stream(near_station) and world.gate_navigation,"An explicit transit plan is available with the open-water preference")
	world.cancel_autopilot()
	world.objective_travel_mode=World.ObjectiveTravel.STREAM
	expect(world.route_to(near_station) and not world.gate_navigation and world.destination==near_station,"An explicit ocean course is available with the STREAM preference")
	world.cancel_autopilot()
	world.objective_travel_mode=World.ObjectiveTravel.OPEN_WATER
	expect(world.route_to_objective(far_station) and world.destination==far_station and world.stream_destination<0,"Open-water objectives beyond engine reach retain continuous ocean travel")
	world.objective_travel_mode=World.ObjectiveTravel.STREAM
	world.cancel_autopilot()
	expect(world.route_to_objective(session.station_id) and world.destination==session.station_id and not world.gate_navigation,"Local station objectives remain local courses")
	world.cancel_autopilot()
	world.region.success={"kind":"no_enemies"}
	expect(not world.route_to_objective(near_station) and not world.autopilot,"An encounter denial is preserved instead of falling back to a forbidden direct course")
	world.objective_travel_mode=World.ObjectiveTravel.OPEN_WATER
	expect(not world.route_to_objective(near_station) and not world.autopilot,"The open-water preference preserves the same active-encounter exit lock")
	world.region.success=null
	expect(not world.route_to_objective(-1),"Invalid objective destinations are rejected")
	world.dispose()

func check_stream_connections() -> void:
	var session:=Session.new();session.new_game(data,"Connected gates",91)
	while session.campaign.chapter<48:session.campaign.next_chapter(session.counters)
	session.campaign.primary.kind=-1
	session.ship.minimum_depth=0;session.ship.maximum_depth=50000
	# A deterministic three-jump route plus a slightly longer alternative.
	# The rest of the imported atlas is isolated from this small network.
	for station in session.stations:station.x=65;station.y=65;station.depth=22500
	for id in 4:session.stations[id].x=id*15;session.stations[id].y=0
	for id in [4,5]:session.stations[id].x=(id-3)*15;session.stations[id].y=1
	session.prepare_station(0)
	var world:=World.new();world.configure(session);world.depart()
	expect(world.objective_stream_route(3)==[1,2,3],"Distant objectives choose the shortest of the fewest-jump routes")
	expect(world.route_to_objective(3) and world.stream_destination==1 and world.objective_destination==3,"A distant objective starts with its first reachable gate")
	expect(world.resume_destination==3 and world.resume_objective and world.resume_stream,"Resume retains the final objective and the STREAM route type")
	world.cancel_autopilot()
	expect(world.objective_destination<0 and not world.objective_route_pending and world.resume_destination==3,"Manual control cancels continuation but retains the final destination")
	expect(world.plan_objective_stream(world.resume_destination),"The complete objective course can be resumed")
	for target in [1,2,3]:
		world.region.player.pose.origin=world.region.gates[world.departure_gate].duplicate()
		world.update_gates(1000)
		expect(world.stream_transfer() and session.station_id==target,"Each planned jump uses a reachable gate and arrives at its next stop")
		expect(world.objective_route_pending and not world.autopilot,"The next course waits until the arrival shot ends")
		expect(world.continue_objective_route(),"The arrival hands back to the remaining objective course")
		if target!=3:expect(world.gate_navigation and world.stream_destination==target+1 and world.resume_destination==3,"Intermediate arrival keeps the final destination and chooses the next gate")
	expect(world.autopilot and world.destination==3 and not world.gate_navigation and world.objective_destination<0,"The last jump continues to the local destination")
	world.cancel_autopilot();world.enter_region(0)
	world.route_to_objective(3);world.region.player.pose.origin=world.region.gates[0].duplicate();world.update_gates(1000);world.stream_transfer()
	world.advance(.001,{"yaw":1.0})
	expect(not world.continue_objective_route() and not world.autopilot,"Steering during an arrival cancels automatic continuation")
	world.enter_region(0)
	# Neither unsafe water nor an unrelated active encounter is an automatic
	# intermediate stop. The requested endpoint can still be hazardous.
	for id in [2,5]:session.stations[id].depth=50001
	expect(world.objective_stream_route(3).is_empty(),"Unsafe intermediate depths are excluded")
	expect(world.route_to_objective(3) and world.destination==3 and world.message.contains("open water"),"An unreachable network explains its open-water fallback")
	session.stations[2].depth=22500
	session.campaign.secondary.kind=3;session.campaign.secondary.destination=2
	expect(world.objective_stream_route(3).is_empty(),"An unfinished side encounter is not used as an intermediate stop")
	session.campaign.secondary.kind=-1;session.stations[3].depth=50001
	expect(world.objective_stream_route(3)==[1,2,3],"The endpoint keeps the existing travel warning policy")
	world.dispose()
