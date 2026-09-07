extends SceneTree
const Math=preload("res://native/simulation/fixed_math.gd")
const Pose=preload("res://native/simulation/ship_transform.gd")
const Shape=preload("res://native/simulation/collision_shape.gd")
const Session=preload("res://native/simulation/session.gd")
const Economy=preload("res://native/simulation/economy.gd")
const Clock=preload("res://native/simulation/animation_clock.gd")
var failures:=0
var checks:=0
func expect(value: bool,reason: String) -> void:
 checks+=1
 if not value:failures+=1;push_error(reason)
func _initialize():call_deferred("run")
func run():
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
 expect(Math.normalize_vector([0,0,0])==[0,0,0],"Zero direction stays finite")
 expect(Math.length_of([30000,40000,0])==50000,"Length uses conventional vector math")
 var pose:=Pose.new();pose.face([0,4096,0]);expect(pose.basis().determinant()>.99,"Vertical look direction has a valid basis")
 for index in 500:pose.rotate_local("yaw",7);pose.rotate_local("pitch",3)
 expect(absf(pose.basis().determinant()-1)<.001,"Repeated rotations preserve an orthonormal basis")
 var shape:=Shape.new();shape.origin=[1000,0,0];shape.offset=[5000,0,0];shape.half_size=[1000,1000,1000]
 expect(shape.contains([6100,0,0]) and shape.avoidance_normal([6100,0,0])==[4096,0,0],"Collision normals honor translated mesh bounds")
 var clock:=Clock.new();clock.configure(4,100);clock.play(2);clock.advance(0);clock.advance(720)
 expect(clock.sample()==2,"Loop animation retains elapsed overshoot")
 var session:=Session.new();session.new_game(data,"Rules",621)
 var bubbles=preload("res://native/simulation/bubble_trail.gd").new();var before: int=session.rng.state
 for i in 50:bubbles.advance([0,0,0],40,session.rng)
 expect(session.rng.state==before,"Visual bubbles never consume simulation randomness")
 var economy:=Economy.new();economy.configure(session)
 var station: Dictionary=session.stations[0];economy.generate(station)
 expect(station.ships.size()==3 and station.equipment.size()<=10,"Market generation is bounded")
 # Synthetic recipe isolates numeric behavior from original content balance.
 var synthetic: Dictionary=data.duplicate(true)
 synthetic.tables.goods[0]=[0,0,0,0,100,2,4]
 synthetic.tables.goods[1]=[1,0,0,0,100,4,8,[0],[1]]
 session.data=synthetic;session.ship.base_cargo=1000;session.ship.set_cargo([session.make_goods(0,300)])
 var available: Array=economy.recipes(station).filter(func(recipe):return recipe.id==1)
 expect(available.size()==1 and available[0].owned==300,"Crafting counts above 127 do not overflow")
 expect(economy.manufacture(station,1,200),"Large craft commits when ingredients and capacity permit")
 expect(preload("res://native/simulation/goods.gd").contains(session.ship.cargo,0,100) and preload("res://native/simulation/goods.gd").contains(session.ship.cargo,1,200),"Crafting conserves inventory quantities")
 var used: int=session.ship.cargo_used
 expect(not economy.manufacture(station,1,101) and session.ship.cargo_used==used,"Insufficient ingredients leave inventory unchanged")
 var saves=preload("res://native/simulation/save_store.gd").new();session.prepare_station(0)
 var state: Dictionary=JSON.parse_string(JSON.stringify(saves.capture(session)))
 var restored=saves.restore(synthetic,state)
 expect(restored!=null and restored.rng.next_int(10000)==session.rng.next_int(10000),"Saved native RNG restores its next result")
 state.schema=1;state.erase("random_engine");state.random_state="12345"
 expect(saves.restore(synthetic,state)!=null,"Previous engine save migrates into native RNG")
 print("PROVENANCE_RULES ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
