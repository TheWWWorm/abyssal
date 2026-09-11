extends SceneTree
var failures:=0
var checks:=0
func expect(ok: bool, message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func press(pad, id: int, down: bool=true, device: int=0) -> void:
 var event:=InputEventJoypadButton.new();event.device=device;event.button_index=id;event.pressed=down;pad.accept(event)
func axis(pad, id: int, value: float, device: int=0) -> void:
 var event:=InputEventJoypadMotion.new();event.device=device;event.axis=id;event.axis_value=value;pad.accept(event)
func finger(touch, id: int, position: Vector2, down: bool, cancel: bool=false) -> void:
 var event:=InputEventScreenTouch.new();event.index=id;event.position=position;event.pressed=down;event.canceled=cancel;touch.handle(event)
func drag(touch, id: int, position: Vector2, relative: Vector2) -> void:
 var event:=InputEventScreenDrag.new();event.index=id;event.position=position;event.relative=relative;touch.handle(event)
func run() -> void:
 var pad=preload("res://native/input/flight_controls.gd").new()
 axis(pad,JOY_AXIS_LEFT_X,.1);expect(pad.snapshot().yaw==0,"Controller drift stays inside deadzone")
 axis(pad,JOY_AXIS_LEFT_X,.5);expect(pad.snapshot().yaw>0 and pad.snapshot().yaw<.5,"Analog steering retains partial deflection")
 axis(pad,JOY_AXIS_LEFT_Y,-1);expect(pad.snapshot().pitch>0,"Forward stick pitches upward")
 pad.invert=true;expect(pad.snapshot().pitch<0,"Invert setting applies to controller")
 pad.invert=false
 axis(pad,JOY_AXIS_RIGHT_X,.9);axis(pad,JOY_AXIS_RIGHT_Y,-.9)
 expect(pad.snapshot().look.x>.6 and pad.snapshot().look.y>.6,"Right stick aims independently of the left stick")
 pad.invert=true;expect(pad.snapshot().look.y<0,"Invert setting reaches the right stick as well")
 axis(pad,JOY_AXIS_RIGHT_X,0);axis(pad,JOY_AXIS_RIGHT_Y,0)
 expect(pad.snapshot().look==Vector2.ZERO,"A centred right stick contributes nothing")
 axis(pad,JOY_AXIS_TRIGGER_RIGHT,.8);axis(pad,JOY_AXIS_TRIGGER_LEFT,.8)
 expect(pad.snapshot().guns and pad.snapshot().hook,"Independent triggers can fire both banks")
 pad.blocked=true;expect(not pad.snapshot().guns,"Menu closure suppresses held weapons")
 axis(pad,JOY_AXIS_TRIGGER_RIGHT,0);axis(pad,JOY_AXIS_TRIGGER_LEFT,0);pad.snapshot()
 press(pad,JOY_BUTTON_A);expect(pad.snapshot().fire,"Selected weapon rearms after release")
 axis(pad,JOY_AXIS_LEFT_X,.7,1);expect(not pad.snapshot().fire and pad.device==1,"Taking over from another controller clears prior buttons")
 press(pad,JOY_BUTTON_DPAD_UP);expect(pad.snapshot().throttle==1,"Controller can accelerate")
 press(pad,JOY_BUTTON_DPAD_DOWN);expect(pad.snapshot().throttle==0,"Opposing throttle inputs cancel")
 pad.reset();expect(pad.snapshot().yaw==0 and pad.snapshot().throttle==0,"Disconnect/focus reset clears movement")
 var touch=preload("res://native/input/touch_controls.gd").new();root.add_child(touch);touch.mode=1;touch.set_active(true)
 await process_frame
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
  touch.size=dimensions;touch.arrange()
  for name in touch.zones:expect(Rect2(Vector2.ZERO,dimensions).encloses(touch.zones[name]),"Touch target fits: "+name)
 touch.size=Vector2(1280,720);touch.arrange()
 expect(touch.zones.has("full"),"Touch row offers a fullscreen control")
 touch.show_fullscreen=false;touch.arrange()
 expect(not touch.zones.has("full"),"Browsers without a fullscreen control lose the button")
 for name in touch.zones:expect(Rect2(Vector2.ZERO,touch.size).encloses(touch.zones[name]),"Shortened row still fits: "+name)
 touch.show_fullscreen=true;touch.arrange()
 expect(Rect2(Vector2.ZERO,touch.size).encloses(touch.steer_region),"Steering surface fits the screen")
 var landing: Vector2 = touch.steer_region.get_center()
 finger(touch,0,landing,true)
 expect(touch.stick_center.is_equal_approx(touch.clamp_stick(landing)),"Stick appears where the thumb lands")
 drag(touch,0,landing+Vector2(40,-30),Vector2(40,-30))
 finger(touch,1,touch.zones.guns.get_center(),true)
 finger(touch,2,touch.zones.throttle_up.get_center(),true)
 var combined:=touch.snapshot()
 expect(combined.yaw>0 and combined.pitch>0 and combined.guns and combined.throttle==1,"Three fingers steer, fire and accelerate simultaneously")
 finger(touch,1,touch.zones.guns.get_center(),false,true);expect(not touch.snapshot().guns and touch.snapshot().yaw>0,"Canceled finger releases only its own control")
 var free: Vector2 = Vector2(touch.size.x*.78,touch.size.y*.5)
 expect(touch.button_at(free).is_empty() and not touch.steer_region.has_point(free),"Screen centre-right is a free look surface")
 finger(touch,3,free,true);drag(touch,3,free+Vector2(50,-24),Vector2(50,-24))
 var looked:=touch.snapshot()
 expect(looked.look.x>0 and looked.look.y<0,"Dragging the free surface looks around")
 expect(touch.snapshot().look==Vector2.ZERO,"Look delta is consumed once per frame")
 expect(touch.snapshot().yaw>0,"Looking around does not disturb the steering stick")
 finger(touch,3,free,false)
 finger(touch,0,landing,false);expect(touch.steer==Vector2.ZERO and touch.stick_center.is_equal_approx(touch.stick_home),"Releasing the stick returns it home")
 touch.set_active(false);expect(touch.fingers.is_empty() and touch.steer==Vector2.ZERO and touch.look==Vector2.ZERO,"Opening a menu releases all touch inputs")
 touch.drag_anywhere=true;touch.arrange();touch.set_active(true)
 finger(touch,0,touch.stick_home,true)
 expect(not touch.engaged and touch.fingers[0]=="look","Whole-screen look includes the former analog pad")
 drag(touch,0,touch.stick_home+Vector2(50,-24),Vector2(50,-24))
 finger(touch,1,touch.zones.guns.get_center(),true)
 finger(touch,2,touch.zones.throttle_up.get_center(),true)
 var full_look:=touch.snapshot()
 expect(full_look.look==looked.look and full_look.yaw==0 and full_look.pitch==0,"The same drag has the same look delta inside and outside the analog area")
 expect(full_look.guns and full_look.throttle==1,"Whole-screen look preserves simultaneous weapons and throttle")
 finger(touch,0,touch.stick_home,false,true)
 expect(touch.snapshot().look==Vector2.ZERO and touch.snapshot().guns,"Canceling look keeps other fingers held without residual motion")
 touch.set_active(false);touch.drag_anywhere=false;touch.arrange();touch.set_active(true)
 finger(touch,0,landing,true);drag(touch,0,landing+Vector2(40,-30),Vector2(40,-30))
 expect(touch.engaged and touch.snapshot().yaw>0,"Switching back restores analog steering")
 touch.set_active(false)
 # Lists must scroll by dragging their contents, not only the narrow scroll bar.
 var sheet:=ScrollContainer.new();root.add_child(sheet)
 sheet.position=Vector2(20,20);sheet.size=Vector2(300,200)
 var rows:=VBoxContainer.new();sheet.add_child(rows)
 for i in 30:
  var row:=Button.new();row.text="row %d"%i;row.custom_minimum_size.y=40;rows.add_child(row)
 await process_frame
 await process_frame
 var lists=preload("res://native/input/touch_scroll.gd").new();root.add_child(lists);lists.scroll=sheet
 var inside: Vector2 = sheet.get_global_rect().get_center()
 var press:=InputEventScreenTouch.new();press.index=0;press.position=inside;press.pressed=true
 lists._input(press);expect(lists.finger==0,"A touch inside a list starts a scroll candidate")
 var swipe:=InputEventScreenDrag.new();swipe.index=0;swipe.position=inside+Vector2(0,-48);swipe.relative=Vector2(0,-48)
 lists._input(swipe)
 expect(lists.scrolling and sheet.scroll_vertical>0,"Dragging list contents scrolls the list")
 var lifted:=InputEventScreenTouch.new();lifted.index=0;lifted.position=swipe.position;lifted.pressed=false
 lists._input(lifted);expect(lists.finger<0,"Lifting the finger ends the scroll gesture")
 # A tap must still reach the row underneath rather than being eaten as a scroll.
 lists.release();sheet.scroll_vertical=0
 lists._input(press)
 var nudge:=InputEventScreenDrag.new();nudge.index=0;nudge.position=inside+Vector2(0,-3);nudge.relative=Vector2(0,-3)
 lists._input(nudge)
 expect(not lists.scrolling and sheet.scroll_vertical==0,"A small movement stays a tap and does not scroll")
 # Controls owning their own gestures, such as the atlas, keep their touches.
 lists.release();lists.gesture_control=rows.get_child(0)
 expect(not lists.owns(rows.get_child(0).get_global_rect().get_center()),"A gesture control inside the list keeps its own touches")
 lists.gesture_control=null;lists.scroll=null;lists.queue_free();sheet.queue_free()
 await process_frame
 var args:=OS.get_cmdline_user_args()
 var app=load("res://scenes/native_main.tscn").instantiate();app.settings_path="user://platform-check.cfg";app.save_path="user://platform-check.json"
 DirAccess.remove_absolute(app.settings_path);root.add_child(app);await process_frame
 app.open_cache(args[0]);app.launch_game(false,"Control check");await process_frame;await process_frame
 var game=current_scene;game.close_page();game.touch.mode=1;game._process(0)
 expect(game.touch.active,"Touch overlay active while flying")
 game.touch.drag_anywhere=true;game.save_settings()
 var touch_config:=ConfigFile.new();touch_config.load(game.settings_path)
 expect(bool(touch_config.get_value("input","touch_drag_anywhere",false)),"Whole-screen touch look is saved")
 game.touch.drag_anywhere=false;game.save_settings()
 # A browser with no Fullscreen API must say so rather than fail silently.
 game.fullscreen_supported=false;game.message.text="";game.notification_time=0
 var unchanged:=DisplayServer.window_get_mode()
 game.touch_action("full")
 expect(DisplayServer.window_get_mode()==unchanged and game.message.text.contains("Add to Home Screen"),"Missing Fullscreen API explains the home-screen route")
 game.fullscreen_supported=true;game.message.text="";game.notification_time=0
 # The fullscreen control is shared by the touch row, the pause menu and F11.
 if DisplayServer.get_name()!="headless":
  var before:=DisplayServer.window_get_mode()
  game.touch_action("full");expect(DisplayServer.window_get_mode()!=before,"Touch fullscreen control changes the window mode")
  game.toggle_fullscreen();expect(DisplayServer.window_get_mode()==before,"Fullscreen control toggles back")
 # Sideways thrust: A/D and the left stick slide the hull where something else can turn it.
 var pose=preload("res://native/simulation/ship_transform.gd").new();pose.strafe(500)
 expect(pose.origin==[500,0,0],"Lateral thrust travels along the hull's right axis")
 game.strafe_mode=0;game.touch.mode=1;game._process(0)
 expect(not game.strafe_enabled(),"Auto leaves the touch stick turning, having nothing else to turn with")
 game.touch.mode=2;game._process(0)
 expect(game.strafe_enabled(),"Auto strafes once a mouse and pad are steering instead")
 game.strafe_mode=2;expect(not game.strafe_enabled(),"Always turn overrides the platform default")
 game.strafe_mode=1;game.touch.mode=1;game._process(0)
 expect(game.strafe_enabled(),"Always strafe reaches touch as well")
 game.touch.mode=2;game._process(0);game.strafe_mode=1
 axis(game.controller,JOY_AXIS_LEFT_X,1,4)
 var sliding: Dictionary=game.flight_input()
 expect(sliding.strafe>.9 and sliding.yaw==0,"The left stick strafes rather than turning")
 axis(game.controller,JOY_AXIS_RIGHT_X,1,4)
 expect(game.flight_input().yaw>.9,"The right stick still turns while the left stick strafes")
 game.strafe_mode=2
 var turning: Dictionary=game.flight_input()
 expect(turning.strafe==0 and turning.yaw>.9,"Turn mode routes the left stick back to yaw")
 axis(game.controller,JOY_AXIS_LEFT_X,0,4);axis(game.controller,JOY_AXIS_RIGHT_X,0,4);game.strafe_mode=0
 var pilot=game.world.region.player;var saved=pilot.pose.copy_pose()
 pilot.set_strafe(0);pilot.advance(100)
 var straight: Array=pilot.pose.origin.duplicate()
 pilot.pose=saved.copy_pose();pilot.set_strafe(1);pilot.advance(100)
 expect(pilot.pose.origin!=straight,"Strafe input displaces the submarine off its forward track")
 pilot.pose=saved;pilot.set_strafe(0)
 game.show_pause();await process_frame;await process_frame
 expect(not game.touch.active and root.gui_get_focus_owner()!=null,"Menus hide touch pad and focus a controller-operable button")
 game.show_map();await process_frame
 var chart=game.map_widget
 var first:=InputEventScreenTouch.new();first.index=0;first.pressed=true;first.position=Vector2(100,100);chart._gui_input(first)
 var second:=InputEventScreenTouch.new();second.index=1;second.pressed=true;second.position=Vector2(200,100);chart._gui_input(second)
 var drag:=InputEventScreenDrag.new();drag.index=1;drag.position=Vector2(250,100);drag.relative=Vector2(50,0);chart._gui_input(drag)
 expect(chart.zoom>1 and not chart.tap_allowed,"Two-finger map pinch zooms without selecting a station")
 first.pressed=false;first.canceled=true;chart._gui_input(first);second.pressed=false;chart._gui_input(second)
 expect(chart.touches.is_empty(),"Map releases both gesture fingers")
 game.close_page();game.controller.device=9;game.controller_connection(9,false)
 expect(game.page=="pause" and game.controller.device==-1,"Controller disconnect pauses actual gameplay")
 game.close_page();game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 expect(game.page=="pause","App focus loss pauses actual gameplay")
 game.touch.mode=1;game.session.docked=true;game.show_station()
 for i in 4:await process_frame
 var footer: Node=game.column.get_child(game.column.get_child_count()-1)
 expect(game.sheet_scroll.get_global_rect().encloses(footer.get_global_rect()),"Touch station footer stays visible at 720p")
 game.queue_free();touch.queue_free();await process_frame
 for name in ["platform-check.cfg","platform-check.json","platform-check.json.bak"]:DirAccess.remove_absolute("user://"+name)
 print("PLATFORM_INPUT ",checks," checks; ",failures," failures");quit(1 if failures else 0)
