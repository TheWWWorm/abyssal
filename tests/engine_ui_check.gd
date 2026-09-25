extends SceneTree
class MusicProbe extends "res://native/presentation/dive_audio.gd":
 var transitions: Array = []
 func apply_music_pause(paused: bool) -> void:transitions.append(paused)
var failures := 0
func expect(ok: bool, why: String) -> void:
 if not ok:failures+=1;push_error(why)
func _initialize():call_deferred("run")
func run():
 var args := OS.get_cmdline_user_args()
 var app=load("res://scenes/native_main.tscn").instantiate()
 app.save_path="user://engine-ui-check.json";app.settings_path="user://engine-ui-check.cfg"
 DirAccess.remove_absolute(app.settings_path)
 root.add_child(app);await process_frame;await process_frame
 expect(app.content.root.is_empty() and app.title_menu.new_button.disabled,"Empty engine never reads a parent JAR or starts without content")
 expect(not app.title_menu.logo.visible,"Original logo is absent before import")
 expect(app.title_dock.abyss.lamps.all(func(lamp):return not lamp.visible) and app.title_dock.abyss.beams.all(func(beam):return not beam.visible),"The empty title has no orphaned submarine headlights or beam cones")
 app.open_cache(args[0]);await process_frame
 expect(not app.title_menu.new_button.disabled and app.title_menu.logo.texture!=null,"Imported content enables play and supplies original logo")
 expect(app.title_menu.continue_button.disabled,"No checkpoint disables load")
 # A window that ignores a dropped game file looks broken, so a drop it cannot
 # use has to say so rather than do nothing at all.
 app.status.text=""
 app.dropped_files(PackedStringArray(["/tmp/not-a-game.txt"]))
 expect(app.status.text.contains(".jar"),"A dropped file of the wrong kind says what would have worked")
 app.import_busy=true;app.status.text="unchanged"
 app.dropped_files(PackedStringArray(["/tmp/whatever.jar"]))
 expect(app.status.text=="unchanged","A drop during an import is ignored rather than starting a second one")
 app.import_busy=false
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440),Vector2i(5120,2880)]:
  root.size=dimensions;await process_frame;await process_frame
  for node in [app.title_menu.logo,app.title_menu.panel,app.title_menu.status,app.title_menu.footer,app.title_menu.edition]:
   expect(root.get_visible_rect().encloses(node.get_global_rect()),"Menu fits %s: %s"%[dimensions,node.name])
  app.title_menu.toggle_help();await process_frame
  expect(root.get_visible_rect().encloses(app.title_menu.help.get_global_rect()),"Help fits %s"%dimensions)
  app.title_menu.toggle_help();app.show_settings();await process_frame;await process_frame
  expect(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Options fit %s"%dimensions)
  app.close_modal()
 app.show_settings();await process_frame
 var title_hints=app.modal.find_children("*","CheckButton",true,false).filter(func(node):return node.text=="Gameplay tips and control hints")
 expect(title_hints.size()==1 and title_hints[0].button_pressed,"Title options expose enabled gameplay hints")
 title_hints[0].set_pressed_no_signal(false);title_hints[0].toggled.emit(false)
 var title_config:=ConfigFile.new();title_config.load(app.settings_path)
 expect(not bool(title_config.get_value("interface","hints",true)) and app.loading_hint(1).is_empty(),"Turning hints off at the title also removes loading tips")
 title_hints[0].set_pressed_no_signal(true);title_hints[0].toggled.emit(true);app.close_modal()
 root.size=Vector2i(1280,720);app.show_start();await process_frame
 expect(app.face_preview.texture!=null,"Portrait creator reads local JAR art")
 app.close_modal();app.launch_game(false,"Engine test");await process_frame;await process_frame
 var game=current_scene
 expect(game!=null and not game.view.pack.enabled,"Native gameplay needs no material pack")
 game.set_process(false)
 game.close_page();game.show_dialogue([{"speaker":"Test","text":"Departure briefing"}],game.close_page)
 await process_frame;await process_frame
 expect(game.page=="dialogue" and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"A briefing opened after closing a menu retains the visible cursor")
 game.close_page();await process_frame
 expect(not game.suppress_fire_until_release,"Closing with no held buttons does not suppress the first shot")
 var hook=game.world.region.loadout.all_weapons().filter(func(weapon):return weapon.fishing)[0]
 expect(hook.request_fire(game.world.region.player.pose,40),"Freshly loaded fishing gear fires on the first request")
 game.world.region.events=[];game.world.region.active_transmission=null;game.world.region.pending_mission=null
 hook.remaining.fill(-1);hook.elapsed=hook.cooldown
 var launched: int=hook.launch_serial
 var right_click:=InputEventMouseButton.new();right_click.button_index=MOUSE_BUTTON_RIGHT;right_click.pressed=true
 game._input(right_click);right_click.pressed=false;game._input(right_click)
 game.world.accumulator=0;game.world.advance(.001,game.flight_input())
 expect(hook.launch_serial==launched,"Short click waits for a fixed simulation tick")
 game.world.advance(.04,game.flight_input())
 expect(hook.launch_serial==launched+1,"A quick hook click survives release and a render frame with no simulation step")
 game.show_pause();expect(game.weapon_presses.is_empty() and game.world.weapon_pending.is_empty(),"Opening a menu clears pending weapon presses")
 game.set_process(true)
 game.close_page();game.world.depart();game.view._process(0);game._process(0);await process_frame
 expect(game.instruments.visible and not game.dashboard.visible,"Classic instruments with enhanced lighting")
 game.set_graphics_mode(false);game._process(0);await process_frame
 expect(game.instruments.visible and not game.dashboard.visible,"Classic instruments with classic lighting")
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(3440,1440)]:
  root.size=dimensions;await process_frame;game.layout();await process_frame
  var gauge: Rect2=game.instruments.gauge_rect()
  expect(gauge.size.y>gauge.size.x*8 and gauge.position.x>game.ui.size.x*.8,"Depth instrument is a right-hand vertical column")
  expect(Rect2(Vector2.ZERO,game.ui.size).encloses(gauge),"Depth column fits the viewport")
  expect(not game.condition.get_global_rect().intersects(gauge),"Depth and ship status do not overlap")
  expect(game.classic_frame.imported_art.image("i_weight")!=null,"Cargo instrument uses owner-imported original icon")
 root.size=Vector2i(1280,720);await process_frame
 expect(game.camera.far==10000,"Open ocean retains 10 km visibility")
 expect(not game.graphics.station_smoothing,"Station smoothing defaults off")
 for modern in [false,true]:
  game.set_graphics_mode(modern);game.view._process(0)
  expect(not game.view.library.station_smoothing,"Lighting mode keeps the independent pixelated station setting")
  var station=game.view.station_nodes[0]
  var station_mesh: MeshInstance3D=station.figure.get_node("Mesh")
  var geometry: Mesh=station_mesh.mesh
  var collision_bodies: Array=station_mesh.find_children("*","StaticBody3D",false,false)
  expect(not collision_bodies.is_empty(),"Detailed station has ray collision bodies before filtering")
  var revision: int=game.view.revision
  var neighbor_root:=Node3D.new();game.view.add_child(neighbor_root)
  var neighbor=game.view.model(int(station.record.id),32,neighbor_root,false)
  neighbor.set_stream_visibility(.35)
  for smoothing in [true,false,true,false]:
   game.graphics.station_smoothing=smoothing;game.apply_graphics()
   expect(game.view.revision==revision and game.view.station_nodes[0]==station,"Filtering leaves the ocean scene and station identity intact")
   expect(station.figure.get_node("Mesh")==station_mesh and station_mesh.mesh==geometry,"Station filtering preserves mesh nodes and geometry")
   expect(collision_bodies.all(func(body):return is_instance_valid(body) and body.get_parent()==station_mesh),"Filtering preserves the attached station ray collision bodies")
   var shadow: MeshInstance3D=station.figure.get_node_or_null("StationShadow")
   expect((shadow!=null and shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and station_mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) if modern else station_mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,"Filtering preserves the active station shadow caster")
   expect(neighbor.stream_visibility==.35 and neighbor.get_parent()==neighbor_root,"Filtering preserves a streamed station's fade and parent")
   for visual in [station,neighbor]:
    var mesh: MeshInstance3D=visual.figure.get_node("Mesh")
    var mat: ShaderMaterial=mesh.get_surface_override_material(0)
    expect(mat.shader.code.contains("albedo : source_color, filter_linear_mipmap_anisotropic" if smoothing else "albedo : source_color, filter_nearest_mipmap"),"Current and distant stations use the selected texture filter in either lighting mode")
  neighbor_root.queue_free()
 for pair in [[KEY_P,KEY_T],[KEY_T,KEY_Y]]:
  game.key_bindings.autopilot=pair[0];game.key_bindings.time=pair[1];game.migrate_travel_bindings()
  expect(game.key_bindings.autopilot==KEY_R and game.key_bindings.time==KEY_T,"Previous default bindings migrate to R/T")
 game.key_bindings.autopilot=KEY_T;game.key_bindings.time=KEY_Y;game.key_bindings.dock=KEY_R;game.migrate_travel_bindings()
 expect(game.key_bindings.dock==KEY_R and game.key_bindings.autopilot==KEY_T,"Migration preserves an existing custom R binding")
 game.key_bindings.dock=KEY_E;game.migrate_travel_bindings()
 game.message.text="Time · 1×";game.notification_time=7;game.world.speed=2;game._process(0)
 expect(game.message.text=="Time · 2×","Time notice follows live simulation speed")
 game.notice("Time · 1×");game.notice("Time · 2×")
 expect(not game.pending_notices.any(func(value):return value.begins_with("Time ·")),"Repeated speed changes do not queue stale time notices")
 expect(game.key_bindings.autopilot==KEY_R and game.key_bindings.time==KEY_T,"Autopilot R and time T defaults")
 game.session.campaign.primary.kind=8;game.session.campaign.primary.destination=game.session.station_id
 game.show_destinations()
 for i in 6:await process_frame
 expect(not game.sheet_bar.visible and game.sheet_pages.is_empty(),"Autopilot is one page")
 expect(game.column.find_children("*","Label",true,false).any(func(node):return node.text.contains("Hold R")),"Quest destination includes hold-R navigation guidance")
 expect(not game.column.find_children("*","Button",true,false).any(func(node):return node.text=="Back to flight"),"No redundant return-to-flight action")
 game.close_page()
 var key:=InputEventKey.new();key.physical_keycode=KEY_R;key.pressed=true;game._unhandled_input(key)
 expect(game.page.is_empty(),"T waits for tap versus hold")
 key.pressed=false;game._unhandled_input(key)
 expect(game.page=="destinations","R release opens autopilot")
 game.close_page();key.pressed=true;game._unhandled_input(key);game.autopilot_pressed_at-=500;game._process(0)
 expect(game.world.autopilot and game.page.is_empty(),"Hold R navigates the current objective without opening a menu")
 key.pressed=false;game._unhandled_input(key);game.world.cancel_autopilot()
 game.show_controls("bindings")
 for i in 4:await process_frame
 expect(game.column.find_children("*","Button",true,false).any(func(node):return node.text.begins_with("Autopilot (tap / hold)") and node.is_visible_in_tree()),"Autopilot control is prominently visible")
 game.show_map();await process_frame
 expect(game.map_widget!=null,"Searchable route map retained")
 for direction in [Vector3(1,0,0),Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,1,-1)]:
  game.world.region.player.pose.face([direction.x*4096,direction.y*4096,direction.z*4096])
  expect(game.map_widget.heading().dot(Vector2(direction.x,direction.z).normalized())>.999,"Map heading follows actual planar ship orientation")
 game.world.region.player.pose.face([0,4096,0])
 expect(game.map_widget.heading()==Vector2.ZERO,"Vertical flight does not invent a north-facing map arrow")
 game.close_page();game._process(0)
 expect(not game.objective_label.get_parsed_text().contains("Time "),"Time acceleration is not mixed into mission instructions")
 expect(game.objective_label.bbcode_enabled and game.objective_label.get_parsed_text().contains("CURRENT OBJECTIVE"),"Quest panel distinguishes title, body, progress and navigation hint")
 check_music_transitions(game)
 await check_dock_navigation(game)
 await check_departure(game)
 await check_enemy_cues(game)
 check_oblique_portals(game)
 await check_save_feedback(game)
 await check_confirmations(game)
 await check_option_focus(game)
 await check_gameplay_hints(game)
 check_settings_sanitizing(game)
 check_display_ratios(game)
 check_damage_bearings(game)
 await check_action_freeze(game)
 check_save_transfer(game)
 await check_controls_sections(game)
 await check_trade_quantity(game)
 await check_travel_fade(game)
 check_motion_steering()
 check_touch_chase_and_gate_axis()
 check_free_look(game)
 check_gate_effects(game)
 await check_dock_notices(game)
 game.queue_free();await process_frame
 DirAccess.remove_absolute("user://engine-ui-check.json");DirAccess.remove_absolute("user://engine-ui-check.json.bak");DirAccess.remove_absolute("user://engine-ui-check.cfg")
 print("ENGINE_UI ",failures," failures")
 quit(1 if failures else 0)

func check_music_transitions(game) -> void:
 var music := MusicProbe.new();root.add_child(music);music.set_process(false)
 music.world=game.world
 for i in 300:music._process(1.0/60)
 expect(music.transitions.is_empty(),"Steady flight never recreates the browser music source")
 music.set_context("autopilot",false)
 for i in 300:music._process(1.0/60)
 expect(music.transitions==[true],"An open menu pauses music once, not once per frame")
 music.set_context("",false)
 for i in 300:music._process(1.0/60)
 expect(music.transitions==[true,false],"Closing a menu resumes music exactly once")
 music.music_gain=0;music._process(0);music._process(0)
 music.set_context("failure",false);music.music_gain=.65;music._process(0)
 expect(music.transitions==[true,false,true],"Mute and failure keep one paused source")
 music.set_context("dialogue",false);music._process(0);music._process(0)
 expect(music.transitions==[true,false,true,false],"Dialogue resumes the same music bed once")
 music.set_enabled(false);music.set_enabled(true);music.set_context("autopilot",false);music._process(0)
 expect(music.music_paused and music.transitions[-1],"Re-enabled music respects the current menu")
 music.queue_free()

func check_oblique_portals(game) -> void:
 game.set_process(false);game.view.set_process(false);game.close_page();game.session.docked=false
 while game.session.campaign.chapter<48:game.session.campaign.next_chapter(game.session.counters)
 game.session.campaign.primary.kind=-1
 for side in [1,-1]:
  game.world.enter_region(0);game.view.rebuild()
  for actor in game.world.region.enemies+game.world.region.friends:actor.health.hull=0;actor.health.enabled=false
  game.world.region.events=[];game.world.region.active_transmission=null
  var frame: Transform3D=game.view.gate_nodes[0].global_transform
  var point: Vector3=frame*Vector3(70,10,side*90)
  game.world.region.player.pose.origin=[roundi(point.x*100),roundi(-point.y*100),roundi(-point.z*100)]
  game.world.departure_gate=0;game.world.update_gates(1000)
  for station in game.session.stations:
   if station.id!=0 and game.world.stream_denial(station.id).is_empty():game.stream_selection=station.id;break
  var before: int=game.session.station_id
  # Reached the way a player reaches it: the chart opens at the gate and stops
  # the submarine, and that stop must not be what the far side hands back.
  game.world.region.player.set_throttle(75)
  game.show_stream_menu()
  expect(game.world.region.player.throttle_target==0,"The chart stops the submarine while it is open")
  game.begin_stream_transit()
  # Confirming a destination is the crossing. Nothing is flown into the
  # aperture, so the far side has to be there before another frame is drawn.
  expect(game.session.station_id!=before,"Confirming a destination crosses at once, from side %d"%side)
  expect(game.page.is_empty(),"The chart closes onto the far side rather than waiting for a run-up")
  expect(game.view.transit_progress>=0,"Coming out of the far gate is framed from outside")
  expect(game.view.transit_emerging,"The shot sits at the far aperture the submarine is leaving")
  # Thrown clear of the aperture, not drifting out of it.
  expect(game.world.region.player.speed_factor>4.0,"The submarine leaves the aperture faster than it flies")
  var exit: Transform3D=game.view.gate_nodes[game.world.region.gate_index(1)].global_transform
  expect(exit.origin.distance_to(game.world.region.player.pose.godot_transform().origin)<60,"STREAM emerges at the visible exit aperture")
  # Every region lies on one side of its gate. Entering from either side has to
  # put the submarine down on that side, heading into the region, or it arrives
  # facing open water with the gate between it and everything else.
  var arrived: Transform3D=game.world.region.player.pose.godot_transform()
  var local: Vector3=exit.affine_inverse()*arrived.origin
  var station: Array=game.world.region.station.parts
  var station_local: Vector3=exit.affine_inverse()*Vector3(station[0].origin[0]/100.0,-station[0].origin[1]/100.0,-station[0].origin[2]/100.0)
  var heading: Vector3=exit.basis.inverse()*(-arrived.basis.z)
  expect(signf(station_local.z)==signf(heading.z),"The submarine emerges heading into the region rather than away from it")
  expect(absf(local.z)<40,"The submarine emerges at the aperture, not somewhere beyond it")
  # The crossing is an animation, not a cut: the submarine is clipped against the
  # gate plane on the way in and against the exit plane on the way out, and stays
  # clipped until it has cleared. Anything painted over the view hides all of it.
  expect(game.view.player_model.portal_enabled and game.stream_exit_active,"The submarine emerges clipped against the exit aperture rather than appearing whole")
  var covering: Array=game.ui.get_children().filter(func(node):return node.get_script()==preload("res://native/presentation/travel_fade.gd"))
  expect(covering.is_empty(),"Nothing is painted over the gate transition")
  # Flying clear of the far gate hands the camera back; it must not hold.
  var exit_ticks:=0
  for i in 400:
   game.world.advance(.04);game.advance_transit_view(.04);exit_ticks+=1
   if game.view.transit_progress<0:break
  expect(game.view.transit_progress<0,"The shot hands the camera back once the submarine is clear")
  var exit_seconds := exit_ticks*.04
  expect(absf(exit_seconds-game.TRANSIT_EXIT_SECONDS)<.5,"The far side runs for its stated length, not a distance the submarine happens to cover")
  # The launch is a temporary multiplier. Leaving it on would make the rest of
  # the expedition fly at gate speed.
  expect(is_equal_approx(game.world.region.player.speed_factor,2.0),"Ordinary speed is handed back when the shot ends")
  expect(game.world.region.player.throttle_target==75,"The speed being flown before the chart is what the far side hands back")

func check_dock_notices(game) -> void:
 # Docking with a backlog of flight messages left the prompt that refused the
 # docking on screen, telling the player to approach a station they are inside,
 # and put anything the station had to say seven seconds a message behind it.
 game.close_page();game.session.docked=false
 game.world.enter_region(0);game.view.rebuild()
 game.world.region.events=[];game.world.region.active_transmission=null
 var berth: Array=[]
 for candidate in [[0,15000,0],[0,-15000,0],[15000,0,0],[-15000,0,0],[0,0,15000],[0,0,-15000]]:
  if game.world.region.station.can_dock(candidate): berth=candidate;break
 expect(not berth.is_empty(),"There is a point off the hull the submarine can dock from")
 game.world.region.player.pose.origin=berth.duplicate()
 expect(not game.world.at_gate(0),"The berth is not a gate")
 game.clear_notices()
 game.notice("Approach the station to dock (within 160 m).")
 game.notice("Route blocked by a station within safe depth")
 expect(game.pending_notices.size()==1 and not game.message.text.is_empty(),"Flight messages queue behind one another")
 game.perform("dock")
 await process_frame
 expect(game.session.docked,"Pressing dock at the berth docks")
 expect(game.pending_notices.is_empty(),"Docking drops the messages that were queued in flight")
 expect(not game.message.text.begins_with("Approach the station"),"A refused docking does not stay on screen while docked")
 # Docked, each answer replaces the last rather than waiting its turn: saving
 # must not report itself seven seconds after the key was pressed.
 game.notice("Berth secured")
 game.notice("Saved")
 expect(game.message.text=="Saved" and game.pending_notices.is_empty(),"A message while docked answers the press that caused it")
 game.session.docked=false;game.clear_notices();game.close_page()
 game.world.enter_region(0);game.view.rebuild()
 game.world.region.events=[];game.world.region.active_transmission=null
 game.world.region.player.pose.origin=berth.duplicate()
 expect(game.world.route_to(game.session.station_id),"Station autopilot engages from the docking approach")
 var arrival_time: int=game.world.region.elapsed_ms
 game._process(.25);await process_frame
 expect(game.session.docked and not game.world.autopilot,"Autopilot reaches the berth and disengages")
 expect(game.world.region.elapsed_ms-arrival_time==game.world.STEP_MS,"The simulator stops advancing in the frame where autopilot docks")
 # Medals won on the way in are announced first, one page each (ch.e), and
 # M.A.I.'s dock remarks after them.
 var announced := 0
 while game.page in ["medal","dialogue"] and announced<30:
  if game.page=="medal":expect(game.column.find_children("*","TextureRect",true,false).any(func(icon):return icon.texture!=null),"A new medal is shown with its sprite")
  game.dock_back();announced+=1
 expect(game.page=="station" and game.overlay.visible and game.column.find_children("*","Button",true,false).any(func(button):return button.text=="DEPART >"),"Autopilot docking opens the station services instead of leaving only the exterior view")
 game.session.docked=false;game.clear_notices();game.close_page()

func check_free_look(game) -> void:
 # Alt or Ctrl with the mouse swings the chase camera round the hull instead
 # of steering, hides the reticle, and lets go when the key is released.
 game.close_page();game.session.docked=false;game.view.camera_mode=0
 game.view.look_offset=Vector2.ZERO;game.view.look_held=false;game.view._process(.04)
 var hull:Transform3D=game.view.player_model.global_transform
 var behind:Vector3=hull.affine_inverse()*game.view.camera.global_position
 expect(behind.z>0 and absf(behind.x)<1,"The chase camera starts behind the hull")
 game.view.look_held=true;game.view.turn_look(Vector2(PI/2,0));game.view._process(.04)
 var beside:Vector3=hull.affine_inverse()*game.view.camera.global_position
 expect(beside.x>10 and absf(beside.z)<10,"Mouse right swings the camera round to the hull's starboard side")
 expect(game.view.aim_point()==null,"Weapons fire straight ahead while looking around")
 game.view.turn_look(Vector2(0,-9));expect(game.view.look_offset.y>=-1.26,"The look pitch stops short of the pole")
 game.view.look_offset=Vector2(PI/2,0);game.view.look_held=false
 for i in 40:game.view._process(.05)
 var back:Vector3=hull.affine_inverse()*game.view.camera.global_position
 expect(not game.view.looking_around() and back.z>0 and absf(back.x)<1,"The camera eases back behind the hull once the key is released")

func check_gate_effects(game) -> void:
 # The gate model carries the original's own additive effects: the flare in the
 # aperture and the trails that stream off the arms as they swing out. They were
 # discarded for years by a rule written to hide the glow meshes on submarine
 # hulls, whose id range ran past the hulls and took the gate with it.
 game.world.enter_region(0);game.view.rebuild()
 var gate=game.view.gate_nodes[0]
 expect(int(gate.record.id)>=12,"The S.T.R.E.A.M. gate is not a submarine hull")
 game.view._process(.04)
 var mesh: MeshInstance3D=null
 var pending: Array[Node]=[gate]
 while not pending.is_empty():
  var part: Node=pending.pop_front()
  if part is MeshInstance3D and part.mesh!=null and part.material_override==null: mesh=part;break
  pending.append_array(part.get_children())
 expect(mesh!=null,"The gate figure is built from imported geometry")
 var additive:=0
 for i in mesh.mesh.get_surface_count():
  var applied=mesh.get_active_material(i)
  if applied is ShaderMaterial and applied.shader!=null and applied.shader.code.contains("blend_add"):
   additive+=1
   expect(bool(applied.get_shader_parameter("source_glow_visible")),"The gate's own effects are drawn rather than discarded as hull glow")
 expect(additive>0,"The gate model has additive effect geometry to draw")
 # Toned to the rest of the game's effects they are invisible, which is what
 # kept them unnoticed. The gate is the one place they are the point.
 gate.effect_boost=game.view.GATE_EFFECT_BOOST;gate.refresh()
 var boosted:=0
 for i in mesh.mesh.get_surface_count():
  var applied=mesh.get_active_material(i)
  if applied is ShaderMaterial and applied.shader!=null and applied.shader.code.contains("blend_add"):
   if float(applied.get_shader_parameter("effect_glow"))>game.view.library.effect_glow+1.0: boosted+=1
 expect(boosted>0,"A gate's effect level reaches the material that draws it")

func check_dock_navigation(game) -> void:
 game.session.docked=true;game.show_station()
 var services=game.column.find_child("Services",true,false)
 expect(services.get_children().map(func(node):return node.text)==["HANGAR","MISSIONS","MAP","TRADE","STATUS","SYSTEM"],"Dock separates hangar, missions, trade, status and system")
 var identity=game.column.find_child("StationIdentity",true,false)
 expect(identity.find_children("*","TextureRect",true,false)[0].texture!=null,"Station faction uses an imported emblem")
 var labels=identity.find_children("*","Label",true,false).map(func(node):return node.text)
 expect(labels[1].contains("Tech level %d"%game.session.stations[game.session.station_id].tech),"Station tech level comes from current station metadata")
 var owner: bool=game.session.campaign.rebel_stations[game.session.station_id]
 game.session.campaign.rebel_stations[game.session.station_id]=not owner;game.show_station()
 identity=game.column.find_child("StationIdentity",true,false)
 expect(identity.find_children("*","Label",true,false)[0].text==("Colonists" if owner else "Rebels"),"Dock ownership follows campaign control")
 game.session.campaign.rebel_stations[game.session.station_id]=owner
 # The yard stocks nought to three hulls by the session's draw; the dealer's
 # showroom is what is under test, so make sure there is a hull to show.
 var yard: Dictionary=game.session.stations[game.session.station_id]
 var economy=load("res://native/simulation/economy.gd").new();economy.configure(game.session)
 while yard.ships.is_empty(): yard.ships=economy.generate_ships(yard)
 game.show_hangar();game.show_market("ships")
 for i in 5:await process_frame
 var preview=game.column.find_child("ShipPreview",true,false)
 expect(preview!=null and preview.vessel!=null and preview.viewport.own_world_3d,"Ship dealer renders an isolated imported vessel in the central viewport")
 var station: Dictionary=game.session.stations[game.session.station_id]
 expect(preview.selected_id==station.ships[game.market_selection].id,"Dealer preview matches the selected sale hull")
 var phase: float=preview.elapsed;preview._process(.5)
 expect(preview.elapsed>phase and preview.wake.instance_count==32,"Preview animates its sea and wake while gameplay is paused")
 if station.ships.size()>1:
  game.market_selection=1;game.show_market("ships")
  var updated=game.column.find_child("ShipPreview",true,false)
  expect(updated.selected_id==station.ships[1].id,"Selecting a different ship updates the 3D preview")
 var old=weakref(preview);game.dock_back()
 for i in 3:await process_frame
 expect(game.page=="hangar" and old.get_ref()==null,"Back returns to Hangar and frees the old showroom")
 var back:=InputEventJoypadButton.new();back.pressed=true;back.button_index=JOY_BUTTON_B;game._input(back)
 expect(game.page=="station","Gamepad B returns from Hangar to the dock")
 game.show_ship_status()
 var ship=game.column.find_child("CurrentShip",true,false)
 expect(ship.find_children("*","TextureRect",true,false)[0].texture==game.imported_art.item(game.session.ship.id,"ships"),"Ship and cargo uses the current owned hull icon")
 game.show_system();game.show_controls();game.dock_back();expect(game.page=="system","Settings return to System at the dock")
 game.session.docked=false;game.close_page()

func check_departure(game) -> void:
 game.session.campaign.rebel_stations[game.session.station_id]=false
 game.session.ship.set_cargo([game.session.make_goods(0,3)])
 var before:int=game.session.credits;var payment:int=3*game.session.make_goods(0,3).minimum_price
 game.session.arrive();game.show_station()
 expect(game.session.ship.cargo_used==0 and game.session.credits==before+payment,"Colonist docking takes the fish at the floor price at once")
 var receipt=game.column.find_child("CargoReceipt",true,false)
 expect(receipt!=null and receipt.text.contains("Fish") and receipt.text.contains(str(payment)),"Sale receipt is part of the dock UI, not a flight toast")
 game.show_hangar();game.show_station()
 expect(game.column.find_child("CargoReceipt",true,false)!=null,"Sale receipt remains after returning from another dock service")
 # Preserve a visible approach bank in the interpolation state. Departure
 # replaces the flight actor, and must replace this old rendered angle too.
 game.world.region.player.visual_bank=384;game.world.previous_render_bank=384
 game.session.docked=true;game.depart()
 expect(game.page=="departure" and not game.session.docked,"Depart starts an exterior sequence before the briefing")
 expect(game.world.region.player.visual_bank==0 and game.world.previous_render_bank==0,"Departure does not retain the angled docking approach")
 expect(game.view.departure_hangar!=null and game.view.departure_hangar.is_hangar(),"Departure selects the station's hangar")
 expect(game.view.departure_frame.basis.y.dot(Vector3.UP)>.99,"The departure shot keeps the station's upright frame, so its camera sits above the berth")
 game.view.place_departure(.1);game.view._process(.016);game.abyss._process(.016)
 expect(game.view.player_clip_enabled and game.abyss.lamps.all(func(lamp):return not lamp.visible),"While the hull waits behind the door its lamps are behind the sill and off: no light before the ship")
 game.view.place_departure(.6);game.view._process(.016);game.abyss._process(.016)
 expect(game.view.player_clip_enabled and game.abyss.lamps.all(func(lamp):return lamp.visible) and game.abyss.beams[0].material_override.get_shader_parameter("clip_enabled")==true,"Once the nose crosses the sill the lamps are on and the beams are clipped by the door plane")
 game.view.place_departure(0)
 var elapsed: int=game.world.region.elapsed_ms
 var previous: Array=game.world.region.player.pose.origin.duplicate()
 for i in 12:
  game._process(.1);game.view._process(.1)
  var port:Transform3D=game.view.departure_frame
  var local:Vector3=port.affine_inverse()*game.view.Library.point(game.world.region.player.pose.origin)
  expect(absf(local.x)<.01 and absf(local.y)<.01,"Departure stays centered on the blue-lit hangar aperture")
 expect(game.world.region.player.pose.origin!=previous and game.world.region.elapsed_ms==elapsed,"Ship leaves the berth while encounter simulation remains paused")
 expect(game.view.combat.player_wake.size()>0,"Departure has a visible movement wake")
 game.view.place_departure(1);game.view._process(0)
 expect(not game.world.region.station.contains(game.world.region.player.pose.origin) and game.view.departure_hangar.hangar_open==0,"Departure clears station and closes the hangar")
 var camera: Transform3D=game.camera.global_transform
 game.view.departure_progress=-1;game.view._process(0)
 expect(camera.origin.distance_to(game.camera.global_position)<.01,"Departure camera joins the selected flight camera continuously")
 var skip:=InputEventKey.new();skip.pressed=true;skip.keycode=KEY_ENTER;game._input(skip)
 expect(game.page in ["dialogue",""] and game.view.departure_progress<0,"Skip completes the departure and opens its pending briefing")
 if game.page=="dialogue":expect(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Post-departure briefing keeps the cursor visible")
 game.close_page()
 # The chart opens at the dock from the seventh chapter.
 var chapter_before: int=game.session.campaign.chapter;game.session.campaign.chapter=maxi(chapter_before,7)
 game.session.docked=true;game.show_map();game.select_station(game.session.station_id)
 for action in game.column.find_children("*","Button",true,false):
  if action.text=="Set station autopilot":action.pressed.emit();break
 game.session.campaign.chapter=chapter_before
 expect(game.page=="departure" and game.departure_destination==game.map_destination,"Map autopilot queues its destination through departure")
 game.finish_departure()
 expect(game.world.autopilot and game.view.departure_progress<0,"Queued map navigation begins after the departure camera releases control")
 game.world.cancel_autopilot();game.close_page()

func check_enemy_cues(game) -> void:
 var marker=load("res://native/presentation/contact_marker.gd").new();game.ui.add_child(marker)
 await process_frame
 marker.position=Vector2(230,220);marker.display("Enemy · ","150 m","",Color.CORAL,75)
 marker.track_enemy(Vector2(200,200),24,false)
 expect(marker.enemy_ring and not marker.edge_square and marker.ring_center+marker.position==Vector2(200,200),"Enemy ring remains anchored to the projected ship, independently of its label")
 marker.track_enemy(Vector2(1250,300),24,true)
 expect(marker.edge_square and not marker.enemy_ring and not marker.label.visible and marker.size==Vector2(14,14),"Offscreen enemy becomes a compact square without a floating label")
 marker.display("Station · ","300 m","",Color.CYAN,-1)
 expect(not marker.enemy_ring and not marker.edge_square and marker.label.visible,"Reused contact controls restore the normal station marker")
 var scanner=load("res://native/presentation/scanner.gd")
 expect(scanner.edge_position(Vector2(3000,360),Vector2(1280,720),false,true).x==1260,"Offscreen threat square reaches the right screen margin")
 marker.queue_free();await process_frame

func named_button(game, caption: String) -> Button:
 for node in game.column.find_children("*","Button",true,false):
  if str(node.text).begins_with(caption):return node
 return null

func check_confirmations(game) -> void:
 # Losing a dive is the sort of thing a menu should ask about first.
 game.session.docked=false;game.show_pause();await process_frame
 named_button(game,"Return to main menu").pressed.emit();await process_frame
 expect(game.page=="confirm","Returning to the menu asks before discarding the dive")
 expect(game.overlay.get_combined_minimum_size().y>0 and named_button(game,"Cancel")!=null,"The confirmation offers a way back")
 named_button(game,"Cancel").pressed.emit();await process_frame
 expect(game.page=="pause","Cancelling a confirmation returns to the menu it came from")
 named_button(game,"Reload station checkpoint").pressed.emit();await process_frame
 expect(game.page=="confirm","Reloading a checkpoint asks before discarding progress")
 named_button(game,"Cancel").pressed.emit();await process_frame
 expect(game.page=="pause","Declining a reload leaves the dive untouched")
 game.close_page()

func check_option_focus(game) -> void:
 # A long settings list that jumps back to the top on every toggle is unusable
 # on a pad. Focus has to stay on the row the player just changed.
 game.show_controls("steering");await process_frame;await process_frame
 var before: bool=game.invert_mouse
 var row := named_button(game,"Invert vertical mouse")
 expect(row!=null and row.get_meta("option","")=="invert_mouse","Settings rows carry the key focus returns to")
 row.pressed.emit();await process_frame;await process_frame
 expect(game.invert_mouse!=before,"The row still performs its setting")
 var focused := root.gui_get_focus_owner()
 expect(focused!=null and focused.get_meta("option","")=="invert_mouse","Focus stays on the toggled row instead of the top of the list")
 expect(game.controls_section=="steering","A setting rebuilds its own section rather than dropping to the section list")
 row=named_button(game,"Invert vertical mouse");row.pressed.emit();await process_frame;await process_frame
 expect(game.invert_mouse==before,"Toggling back restores the original setting")
 game.close_page()

func check_gameplay_hints(game) -> void:
 game.close_page();game.gameplay_hints=true
 game.session.hints_said.erase("regression_hint")
 expect(game.say_hint("regression_hint","One-time guidance"),"An enabled unseen hint is shown")
 expect(game.session.hints_said.has("regression_hint") and game.page=="dialogue","Showing a hint records it in the expedition")
 game.close_page()
 expect(not game.say_hint("regression_hint","One-time guidance"),"A recorded hint is not repeated in the same expedition")
 game.session.hints_said.erase("disabled_hint");game.gameplay_hints=false
 expect(not game.say_hint("disabled_hint","Suppressed guidance") and not game.session.hints_said.has("disabled_hint"),"Disabled hints neither interrupt play nor consume unseen guidance")
 game.hints.show();game.session.docked=false;game._process(0)
 expect(not game.hints.visible,"Disabling hints hides the flight control reminder")
 game.save_settings()
 var config:=ConfigFile.new();config.load(game.settings_path)
 expect(not bool(config.get_value("interface","hints",true)),"The in-game hint preference is saved")
 game.show_controls("");await process_frame;await process_frame
 var toggle:=named_button(game,"Gameplay tips & control hints")
 expect(toggle!=null and toggle.text.ends_with("Off"),"Controls expose the gameplay hint switch")
 toggle.pressed.emit();await process_frame;await process_frame
 expect(game.gameplay_hints,"The in-game switch can restore hints")
 game.close_page()

func check_settings_sanitizing(game) -> void:
 # A settings file is text a player can edit, and older builds wrote other shapes.
 var config := ConfigFile.new()
 config.set_value("audio","music","loud")
 config.set_value("audio","effects",INF)
 config.set_value("keys","mouse_sensitivity",NAN)
 config.set_value("view","resolution_v5",99)
 config.set_value("view","camera",-4)
 config.set_value("keys","fire",-1)
 expect(game.setting_number(config,"audio","music",0.65,0,1)==0.65,"A non-numeric volume falls back to the default")
 expect(game.setting_number(config,"audio","effects",0.75,0,1)==0.75,"An infinite volume falls back rather than reaching the mixer")
 expect(game.setting_number(config,"keys","mouse_sensitivity",0.8,0.2,2.0)==0.8,"A NAN sensitivity never becomes a steering multiplier")
 expect(game.setting_index(config,"view","resolution_v5",2,2)==2,"An out-of-range resolution is clamped to a real option")
 expect(game.setting_index(config,"view","camera",0,3)==0,"A negative camera index is clamped")
 expect(game.setting_keycode(config,"fire",KEY_SPACE)==KEY_SPACE,"An impossible keycode keeps the action reachable")
 expect(game.setting_number(config,"audio","missing",0.4,0,1)==0.4,"A missing value uses its default")

func check_display_ratios(game) -> void:
 var display=preload("res://native/presentation/display_settings.gd")
 expect(display.valid("nonsense")=="auto","An unknown picture ratio falls back to filling the window")
 var window := root.get_window()
 var previous: String=game.aspect_ratio
 game.aspect_ratio="4:3";game.update_render_resolution()
 expect(window.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP and window.content_scale_size==display.RATIOS["4:3"],"A fixed ratio pins the picture shape")
 game.aspect_ratio="auto";game.update_render_resolution()
 expect(window.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND,"Auto returns the picture to the window")
 game.aspect_ratio=previous;game.update_render_resolution()

func check_damage_bearings(game) -> void:
 var feedback=game.damage_feedback
 feedback.clear()
 var here: Vector3=game.camera.global_transform.origin
 feedback.record(game.camera,here-game.camera.global_transform.basis.z*60,here)
 expect(feedback.marks.size()==1,"A hit leaves a bearing to read")
 var ahead: float=feedback.marks[0].angle
 feedback.record(game.camera,here-game.camera.global_transform.basis.z*62,here)
 expect(feedback.marks.size()==1,"A second hit from the same bearing reinforces the first")
 feedback.record(game.camera,here+game.camera.global_transform.basis.z*60,here)
 expect(feedback.marks.size()==2,"A hit from behind is a separate bearing")
 expect(absf(angle_difference(feedback.marks[1].angle,ahead))>1.5,"Front and rear hits do not share a direction")
 feedback.advance(10.0)
 expect(feedback.marks.is_empty(),"Bearings fade instead of accumulating")
 feedback.record(null,here,here)
 expect(feedback.marks.is_empty(),"No camera means no invented bearing")

func toolbar_button(node: Node, caption: String) -> Button:
 for child in node.find_children("*","Button",true,false):
  if str(child.text)==caption:return child
 return null

func check_action_freeze(game) -> void:
 game.session.docked=false;game.close_page()
 var before: Transform3D=game.camera.global_transform
 var elapsed: int=game.world.region.elapsed_ms
 game.show_action_freeze();await process_frame;await process_frame
 expect(game.page=="freeze" and is_instance_valid(game.freeze_view),"Action freeze takes over from the flight view")
 # Without a visible way out, a touch player is stranded in the frozen scene.
 var bar: Control=game.freeze_view.toolbar
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2000,1175)]:
  root.size=dimensions;await process_frame;await process_frame
  expect(Rect2(Vector2.ZERO,game.freeze_view.size).encloses(bar.get_global_rect()),"Action freeze controls stay on screen at %s"%dimensions)
 root.size=Vector2i(1280,720);await process_frame;await process_frame
 expect(toolbar_button(bar,"Resume dive")!=null and toolbar_button(bar,"Back to pause")!=null,"Action freeze offers a way out that needs no keyboard")
 expect(game.view.process_mode==Node.PROCESS_MODE_DISABLED,"The flight view stops driving the camera while frozen")
 game.freeze_view.orbit(Vector2(120,0));game.freeze_view.zoom(1.4)
 expect(game.camera.global_transform!=before,"The frozen camera actually moves")
 game._process(0.2)
 expect(game.world.region.elapsed_ms==elapsed,"Nothing is simulated while the dive is frozen")
 # Escape has to leave the freeze without reaching the dive or the scene behind it.
 var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;escape.physical_keycode=KEY_ESCAPE
 game.freeze_view._input(escape);await process_frame;await process_frame
 expect(game.page=="pause" and game.freeze_view==null,"Escape leaves the freeze and returns to the pause menu")
 expect(game.view.process_mode==Node.PROCESS_MODE_INHERIT,"The flight view takes the camera back")
 expect(game.camera.global_transform.is_equal_approx(before),"Leaving restores the flight camera exactly")
 # And the on-screen button does the same thing, for players with no keyboard.
 game.close_page();game.show_action_freeze();await process_frame;await process_frame
 toolbar_button(game.freeze_view.toolbar,"Resume dive").pressed.emit();await process_frame;await process_frame
 expect(game.page=="" and game.freeze_view==null,"The Resume control returns to the dive")
 expect(game.camera.global_transform.is_equal_approx(before),"Resuming restores the flight camera exactly")

func check_save_transfer(game) -> void:
 var transfer=preload("res://native/simulation/save_transfer.gd").new()
 var path := "user://engine-ui-transfer.json"
 var export_path := "user://engine-ui-transfer.abyssave"
 game.session.docked=true
 expect(game.store.write(path,game.session),"A checkpoint can be written for export")
 var record: Dictionary=transfer.collect(game.content.data,path)
 expect(not record.is_empty() and record.format=="abyssal-native-save","An expedition exports as a data-only record")
 expect(record.content_id==game.content.data.jar_sha256,"An export names the content it was played on")
 expect(transfer.write(export_path,record),"The export reaches a file")
 var reread: Dictionary=transfer.read_export(game.content.data,export_path)
 expect(not reread.is_empty() and reread.save.name==game.session.name,"An export reads back as the same expedition")
 var foreign: Dictionary=record.duplicate(true);foreign.content_id="0".repeat(64)
 expect(transfer.validate(game.content.data,foreign).is_empty(),"An export from other game content is refused")
 expect(transfer.validate(game.content.data,{"format":"something-else","version":1}).is_empty(),"An unrelated file is refused")
 var damaged: Dictionary=record.duplicate(true);damaged.save=damaged.save.duplicate(true);damaged.save.erase("ship")
 expect(transfer.validate(game.content.data,damaged).is_empty(),"An incomplete expedition is refused")
 # Importing replaces the local expedition and keeps the displaced one.
 var displaced := "user://engine-ui-displaced.json"
 game.store.write(displaced,game.session)
 expect(transfer.install(game.content.data,displaced,record),"An import installs over the local expedition")
 expect(FileAccess.file_exists(displaced+".bak"),"The replaced expedition is kept as the backup")
 # The backup is what an unreadable save falls through to.
 var broken := FileAccess.open(displaced,FileAccess.WRITE);broken.store_string("{ not json");broken.close()
 var store=preload("res://native/simulation/save_store.gd").new()
 var recovered=store.read(displaced,game.content.data)
 expect(recovered!=null and store.recovered,"An unreadable save falls back to the checkpoint beside it")
 expect(store.failure.is_empty(),"A successful recovery reports no failure")
 for name in [path,path+".bak",export_path,displaced,displaced+".bak"]:DirAccess.remove_absolute(name)

func check_save_feedback(game) -> void:
 # Saving from a menu has to answer where the player is looking. The notice
 # draws above everything, so an open panel must be given room rather than
 # drawn through: a confirmation landing on a menu row reads as a fault.
 # Only the docked flag matters here; rebuilding the docked view would replace
 # a live region the earlier checks are still using.
 game.session.docked=true
 for i in 3:await process_frame
 for dimensions in [Vector2i(1280,720),Vector2i(1280,560),Vector2i(1920,1080),Vector2i(2000,919)]:
  root.size=dimensions
  for i in 4:await process_frame
  game.show_system()
  for i in 3:await process_frame
  game.message.text="";game.notification_time=0
  game.save_game(true)
  for i in 2:await process_frame
  expect(game.message.text==game.session.text(32),"Saving an expedition says so at %s"%dimensions)
  expect(game.message.visible,"The save confirmation is actually shown at %s"%dimensions)
  var notice_rect := Rect2(game.message.position,game.message.size)
  expect(Rect2(Vector2.ZERO,game.ui.size).encloses(notice_rect),"The confirmation stays on screen at %s"%dimensions)
  var covered: Array = []
  for row in game.column.find_children("*","Button",true,false):
   if row.is_visible_in_tree() and row.get_global_rect().intersects(notice_rect): covered.append(row.text)
  expect(covered.is_empty(),"The confirmation covers no menu row at %s: %s"%[dimensions,covered])
  game.close_page();await process_frame
 root.size=Vector2i(1280,720)
 for i in 3:await process_frame
 # Away from a station there is nothing to save, and that has to be said too.
 game.session.docked=false;game.message.text="";game.notification_time=0
 game.save_game(true)
 expect(game.message.text.begins_with("Dock at a station"),"Saving away from a station explains why it cannot")

func check_controls_sections(game) -> void:
 # Every control on one page was longer than a pad could comfortably walk, and
 # the sliders sat at the bottom of it.
 game.session.docked=false;game.show_controls();await process_frame;await process_frame
 expect(game.controls_section.is_empty(),"Controls opens on its list of sections")
 for key in ["steering","gamepad","touch","bindings","reference"]:
  expect(game.find_option(game.column,key)!=null,"Controls lists the %s section"%key)
 expect(game.column.find_children("*","HSlider",true,false).is_empty(),"The section list carries no settings of its own")
 game.find_option(game.column,"touch").pressed.emit();await process_frame;await process_frame
 expect(game.controls_section=="touch" and game.page=="controls","A section row opens that section")
 expect(named_button(game,"Touch controls ·")!=null,"The touch section carries the touch settings")
 game.dock_back();await process_frame;await process_frame
 expect(game.controls_section.is_empty(),"Back inside Controls returns to the section list, not out of settings")
 var focused := root.gui_get_focus_owner()
 expect(focused!=null and focused.get_meta("option","")=="touch","Leaving a section puts focus back on the row that opened it")
 game.show_controls("steering");await process_frame;await process_frame
 expect(named_button(game,"Steer by tilting")!=null,"Tilt steering is offered beside the other steering settings")
 expect(named_button(game,"Tilt sensitivity")==null,"Tilt settings stay hidden until tilt steering is on")
 game.close_page()

func check_trade_quantity(game) -> void:
 # Filling a hold one tonne per press was the longest chore in the game.
 game.session.docked=true
 # Trade is a rebel service, and a shelf may be empty: stock one line.
 game.session.campaign.rebel_stations[game.session.station_id]=true
 var station: Dictionary=game.session.stations[game.session.station_id]
 if station.cargo.is_empty():station.cargo=[game.session.make_goods(33,10)]
 var stocked: Array=game.economy.market(station).filter(func(entry):return entry.stock>0 and entry.price>0)
 if stocked.is_empty():
  expect(false,"The station offers cargo to trade")
  return
 var item=stocked[0]
 game.session.credits=1000000
 var space: int=game.session.ship.capacity()-game.session.ship.cargo_used
 expect(game.buy_limit(item)==mini(int(item.stock),mini(game.session.credits/int(item.price),space)),"The buy limit is whichever of purse, hold and shelf runs out first")
 var carried: int=game.session.ship.cargo_used
 var wanted: int=mini(3,game.buy_limit(item))
 expect(wanted>1,"The station stocks enough to test a bulk purchase")
 game.trade_amount(station,item,true,wanted)
 expect(game.session.ship.cargo_used==carried+wanted,"Buying an amount moves that many tonnes from one press")
 var held=game.economy.market(station).filter(func(entry):return entry.id==item.id)[0]
 game.trade_amount(station,held,false,int(held.owned))
 expect(game.session.ship.cargo_used==carried,"Selling what is held empties it again")
 # An order the purse cannot start must not report a purchase it did not make.
 game.session.credits=0
 game.trade_amount(station,item,true,4)
 expect(game.session.ship.cargo_used==carried,"A trade that cannot start moves nothing")
 expect(game.buy_limit(item)==0,"No credits means no buy limit")
 game.session.credits=1000000
 game.market_category="";game.show_market("trade");await process_frame;await process_frame
 expect(named_button(game,"Buy ")!=null and named_button(game,"Sell ")!=null,"Trade offers an amount to buy and to sell")
 var most:=named_button(game,"Max")
 expect(most!=null,"Trade reaches its maximum in one press")
 most.pressed.emit();await process_frame;await process_frame
 var ceiling: int=game.market_quantity
 expect(ceiling>1,"Max raises the amount past a single tonne")
 named_button(game,"+").pressed.emit();await process_frame;await process_frame
 expect(game.market_quantity==ceiling,"The amount stops at what that row can actually move")
 named_button(game,"−").pressed.emit();await process_frame;await process_frame
 expect(game.market_quantity==maxi(1,ceiling-1),"The step lowers the amount again")
 game.market_quantity=1;game.close_page();game.session.docked=false

func check_travel_fade(game) -> void:
 # A stream crossing swaps every piece of scenery on a single frame.
 var Fade=load("res://native/presentation/travel_fade.gd")
 var before: int=game.ui.get_child_count()
 Fade.uncover(game.ui,.05)
 expect(game.ui.get_child_count()==before+1,"The cover is placed over the view it hides")
 var cover=game.ui.get_child(game.ui.get_child_count()-1)
 expect(cover.color.a==1.0,"The cover starts opaque, on the frame the swap landed")
 expect(cover.mouse_filter==Control.MOUSE_FILTER_IGNORE,"The cover never takes a press from a player who is still flying")
 expect(cover.size==game.ui.size,"The cover reaches the whole view")
 var lifted:=false
 for i in 300:
  await process_frame
  if game.ui.get_child_count()==before:lifted=true;break
 expect(lifted,"The cover fades out and frees itself rather than staying over the dive")

func check_motion_steering() -> void:
 # None of this can be held in a hand here, so the arithmetic is what gets checked.
 var Motion=load("res://native/input/motion_steering.gd")
 var tilt=Motion.new()
 for reading in [
  Motion.screen_gravity(Vector3(0,9.8,0),0),
  Motion.screen_gravity(Vector3(9.8,0,0),90),
  Motion.screen_gravity(Vector3(-9.8,0,0),-90)]:
  expect(reading.distance_to(Vector3(0,-9.8,0))<.01,"Portrait and both iPhone landscape orientations share screen-space neutral")
 expect(Motion.angles(Motion.screen_gravity(Vector3(9,-4,0),90)).x<0,"Landscape-left sensor roll steers left")
 expect(Motion.angles(Motion.screen_gravity(Vector3(-9,4,0),-90)).x<0,"Landscape-right sensor roll steers left")
 expect(Motion.angles(Vector3(0,-9.8,0)).is_zero_approx(),"A device held level reads as centred")
 expect(Motion.angles(Vector3(-4,-9,0)).x<0,"Rolling left steers left, like a stick pushed left")
 expect(tilt.sample(Vector3.ZERO,.1,.5)==Vector2.ZERO,"A sensor with nothing to say steers nothing")
 tilt.sample(Vector3(0,-9.8,0),1.0,.5)
 expect(tilt.calibrated,"The first reading becomes the centre, so an uncalibrated player still steers")
 expect(tilt.sample(Vector3(0,-9.8,0),1.0,.5).length()<.01,"Held where it was centred, it steers nothing")
 var deflection: Vector2=Vector2.ZERO
 for i in 40: deflection=tilt.sample(Vector3(-6,-8,0),.05,.5)
 expect(deflection.x<-.2,"Tilting away from centre steers, and goes on steering")
 expect(absf(deflection.x)<=1.0 and absf(deflection.y)<=1.0,"Deflection stays inside the range a stick reports")
 tilt.filtered=Vector2.ZERO
 expect(tilt.sample(Vector3(0,-9.8,0).rotated(Vector3(0,0,1),deg_to_rad(1.0)),.05,.5).is_zero_approx(),"A wobble smaller than the deadband is a hand, not an instruction")

func check_touch_chase_and_gate_axis() -> void:
 var View=load("res://native/presentation/world_view.gd")
 var ship=load("res://native/simulation/ship_transform.gd").new()
 # Sustained diagonal thumb input adds genuine simulation roll even without
 # gyro. The touch camera should preserve heading and pitch without passing
 # that roll to every station and gate in the picture.
 for i in 100:
  ship.rotate_local("yaw",8);ship.rotate_local("pitch",5)
 var hull: Basis=ship.godot_transform().basis
 var chase: Basis=View.touch_chase_basis(hull)
 var up: Vector3=(Vector3.UP-hull.z*Vector3.UP.dot(hull.z)).normalized()
 expect(hull.y.dot(up)<.9,"Diagonal steering reproduces the large flight camera roll")
 expect(chase.y.dot(up)>.999 and chase.z.dot(hull.z)>.999,"Touch chase preserves the horizon and travel direction during diagonal steering")
 for angle in [deg_to_rad(80),deg_to_rad(90),deg_to_rad(100)]:
  var loop: Basis=Basis(Vector3.RIGHT,angle)
  var frame: Basis=View.touch_chase_basis(loop)
  expect(frame.is_finite() and absf(frame.determinant()-1.0)<.001 and frame.z.dot(loop.z)>.999,"Touch chase remains a valid frame through a vertical loop")
 var rest:=Transform3D(Basis(Vector3.UP,deg_to_rad(42)),Vector3(12,3,-5))
 var spun: Transform3D=View.gate_idle_transform(rest,512)
 var relative: Basis=rest.basis.inverse()*spun.basis
 expect(spun.origin==rest.origin and relative.z.dot(Vector3.BACK)>.999,"The gate spins in its own plane without orbiting or tumbling")
 expect(relative.x.y<0,"Gate idle spin follows the imported source's positive Z rotation after axis conversion")
