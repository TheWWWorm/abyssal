extends SceneTree
## Menu boundaries and browsing the contract board during an accepted job.
const Focus=preload("res://native/presentation/focus_map.gd")
const Map=preload("res://native/presentation/overworld_map.gd")
var failures := 0
var checks := 0

func expect(ok: bool, message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)

func _initialize() -> void:call_deferred("run")
func settle() -> void:
 for i in 6:await process_frame

func press(action: String) -> void:
 for down in [true,false]:
  var event:=InputEventAction.new();event.action=action;event.pressed=down
  Focus.before_move(root,event);Input.parse_input_event(event)
  await process_frame
 await settle()

func test_button(parent: Node, title: String, position: Vector2, size: Vector2=Vector2(100,40)) -> Button:
 var node:=Button.new();node.text=title;node.position=position;node.size=size;parent.add_child(node)
 return node

func next(control: Control, side: int) -> Node:
 Focus.place(control)
 return control.get_node(control.get_focus_neighbor(side))

func check_focus() -> void:
 var scope:=Control.new();scope.set_meta(Focus.SCOPE_META,true);root.add_child(scope)
 var first:=test_button(scope,"First",Vector2(20,20))
 var middle:=test_button(scope,"Middle",Vector2(20,80))
 var last:=test_button(scope,"Last",Vector2(20,140))
 var disabled:=test_button(scope,"Disabled",Vector2(20,-40));disabled.disabled=true
 var hidden_parent:=Control.new();scope.add_child(hidden_parent);hidden_parent.hide()
 test_button(hidden_parent,"Hidden",Vector2(20,200))
 expect(next(last,SIDE_BOTTOM)==first and next(first,SIDE_TOP)==last,"List edges wrap past disabled controls and hidden groups")
 expect(next(middle,SIDE_BOTTOM)==last and next(middle,SIDE_TOP)==first,"List movement still follows adjacent rows")
 expect(next(middle,SIDE_LEFT)==middle and next(middle,SIDE_RIGHT)==middle,"A one-column list has no spurious horizontal jump")
 last.grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner()==first,"Down input actually wraps the final row to the first")
 await press("ui_up")
 expect(root.gui_get_focus_owner()==last,"Up input actually wraps the first row to the final row")
 # Page code may replace a generated link after layout has already run.
 middle.set_focus_neighbor(SIDE_TOP,middle.get_path_to(last))
 expect(next(middle,SIDE_TOP)==last,"Explicit neighbors remain authoritative after an automatic layout pass")
 scope.queue_free();await settle()

 scope=Control.new();scope.set_meta(Focus.SCOPE_META,true);root.add_child(scope)
 var a:=test_button(scope,"A",Vector2(20,20))
 var b:=test_button(scope,"B",Vector2(140,20))
 var c:=test_button(scope,"C",Vector2(20,80))
 var d:=test_button(scope,"D",Vector2(140,80))
 expect(next(a,SIDE_RIGHT)==b and next(c,SIDE_RIGHT)==d,"Grid movement crosses the current row")
 expect(next(b,SIDE_RIGHT)==a and next(d,SIDE_RIGHT)==c,"Horizontal wrapping stays in the grid row")
 expect(next(c,SIDE_BOTTOM)==a and next(d,SIDE_BOTTOM)==b,"Vertical wrapping stays in the grid column")
 var footer:=test_button(scope,"Footer",Vector2(20,140),Vector2(220,40))
 expect(next(d,SIDE_BOTTOM)==footer and next(footer,SIDE_BOTTOM)==a,"A full-width footer wraps to the first item in reading order")
 expect(next(a,SIDE_RIGHT)==b,"A full-width neighbor cannot steal a grid's horizontal navigation")
 scope.queue_free();await settle()

 scope=Control.new();scope.set_meta(Focus.SCOPE_META,true);root.add_child(scope)
 var scroll:=ScrollContainer.new();scroll.size=Vector2(240,120);scope.add_child(scroll)
 scroll.get_v_scroll_bar().focus_mode=Control.FOCUS_NONE
 var rows:=VBoxContainer.new();scroll.add_child(rows)
 var buttons: Array[Button]=[]
 for i in 6:
  var row:=Button.new();row.text="Row %d"%i;row.custom_minimum_size=Vector2(190,40);rows.add_child(row);buttons.append(row)
 await settle();scroll.scroll_vertical=1000;await settle()
 expect(next(buttons.back(),SIDE_BOTTOM)==buttons.front(),"A scrolled list wraps to its off-screen first row")
 buttons.back().grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner()==buttons.front(),"The wrapped row receives focus inside a scrolling list")
 scope.queue_free();await settle()

func buttons_named(parent: Node, title: String) -> Array:
 return parent.find_children("*","Button",true,false).filter(func(node):return node.text==title)

func check_board(game) -> void:
 game.close_page();game.set_process(false);game.gameplay_hints=false
 game.session.docked=true;game.session.notices.clear();game.session.campaign.chapter=12
 var station: Dictionary=game.session.stations[game.session.station_id]
 var generator=preload("res://native/simulation/contracts.gd").new();generator.session=game.session
 var offers: Array=generator.generate(station)
 if offers.size()<2:offers.append_array(generator.generate(station))
 station.missions=offers
 game.session.credits=1000000
 var accepted=offers[0]
 expect(game.session.accept_contract(accepted),"An empty contract slot accepts a posted offer")
 var pending=station.missions[0]
 var credits: int=game.session.credits
 var remaining: Array=station.missions.duplicate()
 expect(not game.session.accept_contract(pending),"A second acceptance is refused at the session boundary")
 expect(game.session.campaign.secondary==accepted and game.session.credits==credits and station.missions==remaining,"A refused second acceptance preserves the job, credits and board")
 expect(game.station_service_reason("missions").is_empty(),"An accepted job does not make the board unavailable")
 game.show_market("missions",true);await settle()
 var accepts:=buttons_named(game.column,"Accept contract")
 var previews:=buttons_named(game.column,game.session.text(251))
 expect(accepts.size()==remaining.size() and previews.size()==remaining.size(),"Every remaining offer stays on the board with its location preview")
 expect(accepts.all(func(node):return node.disabled) and previews.all(func(node):return not node.disabled),"Only acceptance is disabled while another job is active")
 # Calling a stale UI callback must still be harmless.
 accepts[0].pressed.emit();await settle()
 expect(game.session.campaign.secondary==accepted and game.session.credits==credits and station.missions==remaining,"A replayed acceptance callback cannot replace the job or charge a deposit")
 previews[0].pressed.emit();await settle()
 expect(game.page=="map" and Map.preview_mission==pending,"Check location previews the browsed offer during an active contract")
 buttons_named(game.overlay,"BACK")[0].pressed.emit();await settle()
 expect(game.page=="market" and Map.preview_mission==null and game.session.campaign.secondary==accepted,"Returning from preview restores the board without changing the active job")
 game.session.abandon_contract();game.show_market("missions");await settle()
 accepts=buttons_named(game.column,"Accept contract")
 expect(accepts.all(func(node):return not node.disabled),"Releasing the active slot re-enables offer acceptance")
 accepts[0].pressed.emit();await settle()
 expect(game.session.campaign.secondary==pending and game.session.credits==credits-pending.deposit and not pending in station.missions,"Accepting after abandonment charges exactly one deposit and removes that offer")
 game.show_station();await settle()
 var depart: Button=buttons_named(game.column,"DEPART")[0]
 var hangar: Button=buttons_named(game.column,"HANGAR")[0]
 expect(next(depart,SIDE_BOTTOM)==hangar,"Depart wraps to Hangar in the station service grid")
 depart.grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner()==hangar,"The station menu wraps with a real Down input")
 game.show_pause();await settle()
 buttons_named(game.column,"Return to main menu")[0].grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner()==buttons_named(game.column,"Resume")[0],"The pause menu wraps from its final action to Resume")
 game.show_settings("bindings");await settle()
 var settings_rows: Array[Control]=[]
 Focus.collect(game.settings_panel.column,null,settings_rows)
 settings_rows.back().grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner().get_meta("option","")=="key_time","The settings binding grid wraps the final right-hand binding to its top-right binding")
 game.close_page()

func run() -> void:
 preload("decline_reconstruction.gd").attach(self)
 root.size=Vector2i(1280,720);Focus.attach(root)
 await check_focus()
 var app=load("res://scenes/native_main.tscn").instantiate()
 app.settings_path="user://menu-feedback-check.cfg";app.save_path="user://menu-feedback-check.json"
 for path in [app.settings_path,app.save_path,app.save_path+".bak"]:DirAccess.remove_absolute(path)
 root.add_child(app);await settle()
 await app.open_cache(OS.get_cmdline_user_args()[0]);await settle()
 app.title_menu.footer.grab_focus();await press("ui_down")
 expect(root.gui_get_focus_owner()==app.title_menu.new_button,"The title menu wraps from its footer to Start")
 app.launch_game(false,"Menu check");await settle()
 if current_scene==null:
  expect(false,"The menu check starts a playable scene");quit(1);return
 await check_board(current_scene)
 current_scene.queue_free();await settle()
 for name in ["menu-feedback-check.cfg","menu-feedback-check.json","menu-feedback-check.json.bak"]:DirAccess.remove_absolute("user://"+name)
 print("Menu feedback checks: %d passed, %d failed"%[checks-failures,failures])
 quit(1 if failures else 0)
