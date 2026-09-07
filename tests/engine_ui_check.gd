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
 app.open_cache(args[0]);await process_frame
 expect(not app.title_menu.new_button.disabled and app.title_menu.logo.texture!=null,"Imported content enables play and supplies original logo")
 expect(app.title_menu.continue_button.disabled,"No checkpoint disables load")
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440),Vector2i(5120,2880)]:
  root.size=dimensions;await process_frame;await process_frame
  for node in [app.title_menu.logo,app.title_menu.panel,app.title_menu.status,app.title_menu.footer,app.title_menu.edition]:
   expect(root.get_visible_rect().encloses(node.get_global_rect()),"Menu fits %s: %s"%[dimensions,node.name])
  app.title_menu.toggle_help();await process_frame
  expect(root.get_visible_rect().encloses(app.title_menu.help.get_global_rect()),"Help fits %s"%dimensions)
  app.title_menu.toggle_help();app.show_settings();await process_frame;await process_frame
  expect(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Options fit %s"%dimensions)
  app.close_modal()
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
 game.set_graphics_mode(true);expect(not game.view.library.station_smoothing,"Quality lighting keeps pixelated station textures")
 game.graphics.station_smoothing=true;game.apply_graphics();expect(game.view.library.station_smoothing,"Station smoothing can be enabled independently")
 game.graphics.station_smoothing=false;game.apply_graphics()
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
 game.show_controls()
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
 expect(game.objective_label.bbcode_enabled and game.objective_label.text.contains("CURRENT OBJECTIVE"),"Quest panel distinguishes title, body, progress and navigation hint")
 check_music_transitions(game)
 await check_dock_navigation(game)
 await check_departure(game)
 await check_enemy_cues(game)
 check_oblique_portals(game)
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
  game.begin_stream_transit()
  var ticks:=0
  while ticks<1000 and game.session.station_id==0:
   game.world.advance(.04);ticks+=1
  expect(game.session.station_id!=0 and not game.stream_armed,"Oblique STREAM entry crosses the aperture from side %d"%side)
  var exit: Transform3D=game.view.gate_nodes[game.world.region.gate_index(1)].global_transform
  expect(exit.origin.distance_to(game.world.region.player.pose.godot_transform().origin)<60,"STREAM emerges at the visible exit aperture")

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
 var before:int=game.session.credits;var payment:int=game.session.make_goods(0,3).total_price()
 game.session.arrive();game.show_station()
 expect(game.session.ship.cargo_used==0 and game.session.credits==before+payment,"Colonist docking sells fish immediately")
 var receipt=game.column.find_child("CargoReceipt",true,false)
 expect(receipt!=null and receipt.text.contains("Fish automatically sold") and receipt.text.contains(str(payment)),"Sale receipt is part of the dock UI, not a flight toast")
 game.show_hangar();game.show_station()
 expect(game.column.find_child("CargoReceipt",true,false)!=null,"Sale receipt remains after returning from another dock service")
 game.session.docked=true;game.depart()
 expect(game.page=="departure" and not game.session.docked,"Depart starts an exterior sequence before the briefing")
 expect(game.view.departure_hangar!=null and int(game.view.departure_hangar.record.id)==3308,"Departure selects the blue-lit hangar")
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
 game.session.docked=true;game.show_map();game.select_station(game.session.station_id)
 for action in game.column.find_children("*","Button",true,false):
  if action.text=="Set station autopilot":action.pressed.emit();break
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
