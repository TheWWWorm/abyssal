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
func check_weapon_taps(touch) -> void:
 touch.size=Vector2(1280,720);touch.arrange()
 var guns: Vector2=touch.zones.guns.get_center()
 var hook: Vector2=touch.zones.hook.get_center()
 finger(touch,8,guns,true);finger(touch,8,guns,false)
 expect(touch.snapshot().guns and not touch.snapshot().guns,"A quick weapon tap survives between render frames and fires once")
 finger(touch,8,guns,true);finger(touch,8,guns,false)
 for i in 5:expect(touch.snapshot().guns and not touch.snapshot().hook,"Double-tapping guns continues that bank after the finger lifts")
 finger(touch,8,guns,true);finger(touch,8,guns,false)
 expect(not touch.snapshot().guns,"One tap stops latched automatic guns")
 touch.reset()
 for i in 2:finger(touch,9,hook,true);finger(touch,9,hook,false)
 expect(touch.snapshot().hook and not touch.snapshot().guns,"Harpoon double-tap latches independently of the guns")
 touch.set_active(false);touch.set_active(true)
 expect(not touch.snapshot().hook,"Opening a menu clears touch autofire")
 finger(touch,8,guns,true);finger(touch,8,guns,false);touch.snapshot()
 touch.last_weapon_tap_ms-=touch.DOUBLE_TAP_MS+1
 finger(touch,8,guns,true);finger(touch,8,guns,false);touch.snapshot()
 expect(not touch.snapshot().guns,"Two separated taps do not latch automatic fire")
 touch.reset()
 finger(touch,8,guns,true);finger(touch,8,guns,false);touch.snapshot()
 finger(touch,8,guns,true);finger(touch,8,guns,false,true)
 expect(not touch.snapshot().guns,"A cancelled second tap cannot enable autofire")
 touch.reset()
 finger(touch,8,guns,true);finger(touch,8,guns,false);touch.snapshot()
 finger(touch,8,guns,true);drag(touch,8,guns+Vector2(70,0),Vector2(70,0));finger(touch,8,guns,false);touch.snapshot()
 expect(not touch.snapshot().guns,"Dragging out and back is not a double tap")
 touch.reset()

func run() -> void:
 var pad=preload("res://native/input/flight_controls.gd").new()
 axis(pad,JOY_AXIS_LEFT_X,.1);expect(pad.snapshot().horizontal==0,"Controller drift stays inside deadzone")
 axis(pad,JOY_AXIS_LEFT_X,.5);expect(pad.snapshot().horizontal>0 and pad.snapshot().horizontal<.5,"Analog steering retains partial deflection")
 axis(pad,JOY_AXIS_LEFT_Y,-1);expect(pad.snapshot().pitch>0,"Forward stick pitches upward")
 pad.invert=true;expect(pad.snapshot().pitch<0,"Invert setting applies to controller")
 pad.invert=false
 axis(pad,JOY_AXIS_LEFT_X,0);axis(pad,JOY_AXIS_LEFT_Y,0)
 axis(pad,JOY_AXIS_RIGHT_X,.9);axis(pad,JOY_AXIS_RIGHT_Y,-.6)
 expect(pad.snapshot().yaw>.6 and pad.snapshot().pitch>.3 and pad.snapshot().horizontal==0,"Right stick aims independently of the left stick")
 pad.invert=true;expect(pad.snapshot().pitch<0,"Invert setting reaches the right stick as well")
 pad.invert=false
 # Reassigned sticks: left up/down on the throttle, left/right on turning,
 # the right stick on the camera.
 pad.roles=[pad.Role.TURN,pad.Role.THROTTLE,pad.Role.CAMERA,pad.Role.CAMERA]
 var mapped: Dictionary=pad.snapshot()
 expect(mapped.yaw==0 and mapped.pitch==0 and mapped.camera.x>.6 and mapped.camera.y<0,"A stick given to the camera turns the view, not the ship")
 axis(pad,JOY_AXIS_LEFT_Y,-.9);axis(pad,JOY_AXIS_LEFT_X,.8);mapped=pad.snapshot()
 expect(mapped.throttle==1 and mapped.pitch==0 and mapped.yaw>.5 and mapped.horizontal==0,"Throttle and turning can sit on the left stick")
 axis(pad,JOY_AXIS_LEFT_Y,.3);expect(pad.snapshot().throttle==0,"A throttle stick steps only past half way")
 pad.roles=pad.DEFAULT_ROLES.duplicate();axis(pad,JOY_AXIS_LEFT_X,0);axis(pad,JOY_AXIS_LEFT_Y,0)
 # Held, the camera button lends the right stick to the camera; a tap does not.
 press(pad,pad.LOOK_BUTTON)
 mapped=pad.snapshot()
 expect(pad.looking() and mapped.camera.x>.6 and mapped.yaw==0 and pad.look_hold_used,"Holding D-pad left turns the camera with the right stick")
 press(pad,pad.LOOK_BUTTON,false)
 expect(pad.snapshot().camera==Vector2.ZERO and pad.snapshot().yaw>.6,"Letting go gives the right stick back to steering")
 axis(pad,JOY_AXIS_RIGHT_X,0);axis(pad,JOY_AXIS_RIGHT_Y,0)
 press(pad,pad.LOOK_BUTTON);pad.snapshot();expect(not pad.look_hold_used,"A tap on D-pad left stays a tap")
 press(pad,pad.LOOK_BUTTON,false)
 var config:=ConfigFile.new();config.set_value("input","pad_left_y",4);config.set_value("input","pad_right_x",99);config.set_value("input","pad_right_y","x")
 expect(pad.read_roles(config)==[pad.Role.TURN_OR_STRAFE,pad.Role.THROTTLE,pad.ROLE_NAMES.size()-1,pad.Role.PITCH],"Stick roles are read with bounds and defaults")
 expect(pad.snapshot().camera==Vector2.ZERO and pad.snapshot().yaw==0,"A centred right stick contributes nothing")
 axis(pad,JOY_AXIS_TRIGGER_RIGHT,.8);axis(pad,JOY_AXIS_TRIGGER_LEFT,.8)
 expect(pad.snapshot().guns and pad.snapshot().hook,"Independent triggers can fire both banks")
 pad.blocked=true;expect(not pad.snapshot().guns,"Menu closure suppresses held weapons")
 axis(pad,JOY_AXIS_TRIGGER_RIGHT,0);axis(pad,JOY_AXIS_TRIGGER_LEFT,0);pad.snapshot()
 press(pad,JOY_BUTTON_A);expect(pad.snapshot().fire,"Selected weapon rearms after release")
 axis(pad,JOY_AXIS_LEFT_X,.7,1);expect(not pad.snapshot().fire and pad.device==1,"Taking over from another controller clears prior buttons")
 press(pad,JOY_BUTTON_DPAD_UP);expect(pad.snapshot().throttle==1,"Controller can accelerate")
 press(pad,JOY_BUTTON_DPAD_DOWN);expect(pad.snapshot().throttle==0,"Opposing throttle inputs cancel")
 pad.reset();expect(pad.snapshot().horizontal==0 and pad.snapshot().throttle==0,"Disconnect/focus reset clears movement")
 var touch=preload("res://native/input/touch_controls.gd").new();root.add_child(touch);touch.mode=1;touch.set_active(true)
 await process_frame
 check_weapon_taps(touch)
 check_mirrored_throttle(touch)
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
  touch.size=dimensions;touch.arrange()
  for name in touch.zones:expect(Rect2(Vector2.ZERO,dimensions).encloses(touch.zones[name]),"Touch target fits: "+name)
 # Held upright (iPhone ratio), every control fits and none sits on another.
 touch.size=Vector2(589,1280);touch.arrange()
 var crowded: Array=[]
 for a in touch.ROUND:
  for b in touch.ROUND:
   if a<b and touch.zones[a].get_center().distance_to(touch.zones[b].get_center())<(touch.zones[a].size.x+touch.zones[b].size.x)*.5:crowded.append(a+"/"+b)
  if not Rect2(Vector2.ZERO,touch.size).encloses(touch.zones[a]):crowded.append(a+" off screen")
 var arc_zone: Rect2=touch.zones.throttle
 if arc_zone.get_center().distance_to(touch.zones.hook.get_center())<touch.arc_radius(arc_zone)+touch.zones.hook.size.x*.5+8:crowded.append("hook/throttle")
 expect(crowded.is_empty(),"Upright controls stay apart: %s"%[crowded])
 expect(is_equal_approx(touch.unit,minf(1280/1280.0,589/720.0)),"Upright controls keep their landscape size")
 # Settings held upright: no page is wider than the phone (an iPhone browser
 # with its bars is about 634 wide on the touch canvas).
 for room in [Vector2(540,1280),Vector2(591,1280),Vector2(634,1280),Vector2(1280,720)]:
  var holder:=Control.new();holder.size=room;root.add_child(holder)
  var menu=preload("res://native/presentation/settings_menu.gd").new();holder.add_child(menu)
  menu.configure("user://platform-fit.cfg",{},false,true)
  var wide: Array=[]
  for page in ["audio","graphics","display","controls","gameplay","steering","gamepad","touch","bindings","reference"]:
   menu.open(page);await process_frame;await process_frame
   if menu.get_combined_minimum_size().x>menu.size.x+.5 or not Rect2(Vector2.ZERO,room).encloses(menu.get_rect()):wide.append("%s %d>%d"%[page,menu.get_combined_minimum_size().x,menu.size.x])
  expect(wide.is_empty(),"Settings fit a %dx%d canvas: %s"%[room.x,room.y,wide])
  if room.x>=1280:expect(menu.tab_bar.columns==5,"A landscape canvas keeps the five tabs in one row")
  else:expect(menu.tab_bar.columns<5,"An upright canvas stacks the tabs")
  holder.queue_free()
 # Every size, landscape phones inside their notch margins included: round
 # controls keep a clear gap, and the depth label clears the top buttons.
 for dimensions in [Vector2(800,600),Vector2(1280,720),Vector2(1140,589),Vector2(2400,1080),Vector2(589,1184)]:
  touch.size=dimensions;touch.arrange()
  var tight: Array=[]
  for a in touch.ROUND:
   for b in touch.ROUND:
    if a<b and touch.zones[a].get_center().distance_to(touch.zones[b].get_center())<(touch.zones[a].size.x+touch.zones[b].size.x)*.5+12*touch.unit:tight.append(a+"/"+b)
  var label_top: float=touch.depth_rect.position.y-touch.DEPTH_LABEL
  if label_top<touch.zones.menu.end.y+12*touch.unit:tight.append("depth label/pause")
  expect(tight.is_empty(),"Controls keep clear of each other at %s: %s"%[dimensions,tight])
 touch.size=Vector2(1280,720);touch.arrange()
 expect(is_equal_approx(touch.zones.boost.get_center().y,touch.zones.hook.get_center().y),"Booster and harpoon sit level")
 expect(not touch.zones.has("full") and not touch.zones.has("camera"),"View and fullscreen live in the pause menu, not on the flight overlay")
 # The dock button only answers while there is something to dock with.
 touch.dock_ready=false
 expect(touch.button_at(touch.zones.dock.get_center())!="dock","A hidden dock button takes no touches")
 touch.dock_ready=true
 expect(touch.button_at(touch.zones.dock.get_center())=="dock","The dock button answers once docking is possible")
 touch.dock_ready=false
 # A weapon or booster that is not fitted has no button.
 touch.has_hook=false;touch.boost_mode="absent"
 expect(touch.button_at(touch.zones.hook.get_center())=="" and touch.button_at(touch.zones.boost.get_center())=="","Unfitted harpoon and booster have no buttons")
 touch.has_hook=true;touch.boost_mode="ready"
 # The throttle is an arc round the guns: where the thumb is on it sets the level.
 var levels: Array=[]
 touch.throttle_changed.connect(func(percent):levels.append(percent))
 var arc: Rect2=touch.zones.throttle
 var radius: float=touch.arc_radius(arc)
 expect(arc.get_center().is_equal_approx(touch.zones.guns.get_center()),"The throttle curves round the guns")
 finger(touch,5,arc.get_center()+Vector2.from_angle(PI+.02)*radius,true)
 drag(touch,5,arc.get_center()+Vector2.from_angle(PI*1.25)*radius,Vector2.ZERO)
 finger(touch,5,arc.get_center()+Vector2.from_angle(PI*1.25)*radius,false)
 expect(levels.size()>=2 and levels[0]==0 and levels[-1]==50,"The throttle arc is empty at its left end and half way at its middle")
 expect(touch.snapshot().throttle==0,"The arc sets the level directly rather than holding a throttle key")
 expect(touch.button_at(touch.zones.guns.get_center())=="guns","The guns inside the arc still answer")
 var home_hook: Rect2=touch.zones.hook
 touch.has_guns=false;touch.place_throttle()
 expect(touch.zones.hook==touch.zones.guns and touch.button_at(touch.zones.guns.get_center())=="hook","Without guns the harpoon takes their place and size")
 expect(touch.zones.throttle.get_center().is_equal_approx(touch.zones.hook.get_center()),"Without guns the throttle curves round the harpoon")
 touch.has_guns=true;touch.place_throttle()
 expect(touch.zones.hook==home_hook,"Fitting guns returns the harpoon to its own place")
 expect(touch.zones.hook.position.x<touch.zones.guns.position.x,"Harpoon then guns under the right thumb")
 expect(Rect2(Vector2.ZERO,touch.size).encloses(touch.steer_region),"Steering surface fits the screen")
 var landing: Vector2 = touch.steer_region.get_center()
 finger(touch,0,landing,true)
 expect(touch.stick_center.is_equal_approx(touch.clamp_stick(landing)),"Stick appears where the thumb lands")
 drag(touch,0,landing+Vector2(40,-30),Vector2(40,-30))
 finger(touch,1,touch.zones.guns.get_center(),true)
 finger(touch,2,touch.zones.boost.get_center(),true)
 var combined:=touch.snapshot()
 expect(combined.yaw>0 and combined.pitch>0 and combined.guns and combined.boost,"Three fingers steer, fire and boost simultaneously")
 finger(touch,1,touch.zones.guns.get_center(),false,true);expect(not touch.snapshot().guns and touch.snapshot().yaw>0,"Canceled finger releases only its own control")
 var free: Vector2 = Vector2(touch.size.x*.78,touch.size.y*.5)
 expect(touch.button_at(free).is_empty() and not touch.steer_region.has_point(free),"Screen centre-right is a free look surface")
 finger(touch,3,free,true);drag(touch,3,free+Vector2(50,-24),Vector2(50,-24))
 var looked:=touch.snapshot()
 expect(looked.look.x>0 and looked.look.y<0,"Dragging the free surface looks around")
 expect(touch.snapshot().look==Vector2.ZERO,"Look delta is consumed once per frame")
 expect(touch.snapshot().yaw>0,"Looking around does not disturb the steering stick")
 finger(touch,3,free,false)
 expect(touch.orbit_held(),"The camera stays swung after the look finger lifts")
 finger(touch,0,landing,false);expect(touch.steer==Vector2.ZERO and touch.stick_center.is_equal_approx(touch.stick_home),"Releasing the stick returns it home")
 expect(touch.orbit_held(),"Letting go of the stick does not bring the camera back")
 finger(touch,0,landing,true);finger(touch,0,landing,false)
 expect(not touch.orbit_held(),"Touching the stick again brings the camera back")
 finger(touch,3,free,true);finger(touch,3,free,false);touch.look_released_ms-=touch.ORBIT_HOLD_MS+1
 expect(not touch.orbit_held(),"The camera comes back by itself after a few seconds")
 touch.snapshot()
 # A fixed stick stays put; a touch has to land on it to steer.
 touch.fixed_stick=true
 finger(touch,0,landing,true)
 expect(touch.fingers[0]=="look","A fixed stick does not come to a thumb that lands elsewhere")
 finger(touch,0,landing,false);touch.snapshot()
 finger(touch,0,touch.stick_home+Vector2(30,0),true)
 expect(touch.engaged and touch.stick_center==touch.stick_home and touch.snapshot().yaw>0,"A thumb on the fixed stick steers from where it stands")
 finger(touch,0,touch.stick_home,false);touch.fixed_stick=false
 # The overlay can be inset from the screen's edges (a phone's notch margin):
 # fingers arrive in screen coordinates and must still find their buttons.
 touch.position=Vector2(70,0)
 finger(touch,6,touch.zones.guns.get_center()+Vector2(70,0),true)
 expect(touch.fingers.get(6,"")=="guns","An inset overlay maps screen touches onto its buttons")
 finger(touch,6,touch.zones.guns.get_center()+Vector2(70,0),false);touch.position=Vector2.ZERO
 var margins=preload("res://native/platform/safe_margins.gd")
 var landscape: Dictionary=margins.margins(Vector2(1280,589),Vector2i(2000,920),true)
 expect(landscape.side>=60 and landscape.top==0,"A widescreen phone held landscape keeps the interface off both side edges")
 var standing: Dictionary=margins.margins(Vector2(589,1280),Vector2i(920,2000),true)
 expect(standing.side==0 and standing.top>=50 and standing.bottom>0,"Held upright the interface keeps clear of the notch and the home indicator")
 expect(margins.margins(Vector2(1280,720),Vector2i(1920,1080),true).side==0 and margins.margins(Vector2(1280,589),Vector2i(2000,920),false).side==0,"16:9 screens and desktops keep the full width")
 var display=preload("res://native/presentation/display_settings.gd")
 expect(display.framed_fov(65,Vector2(1280,720))==65 and display.framed_fov(65,Vector2(589,1280))>85,"Held upright the camera widens its view rather than cutting the sides to a slit")
 touch.set_active(false);expect(touch.fingers.is_empty() and touch.steer==Vector2.ZERO and touch.look==Vector2.ZERO,"Opening a menu releases all touch inputs")
 touch.drag_anywhere=true;touch.arrange();touch.set_active(true)
 finger(touch,0,touch.stick_home,true)
 expect(not touch.engaged and touch.fingers[0]=="look","Whole-screen look includes the former analog pad")
 drag(touch,0,touch.stick_home+Vector2(50,-24),Vector2(50,-24))
 finger(touch,1,touch.zones.guns.get_center(),true)
 finger(touch,2,touch.zones.boost.get_center(),true)
 var full_look:=touch.snapshot()
 expect(full_look.look==looked.look and full_look.yaw==0 and full_look.pitch==0,"The same drag has the same look delta inside and outside the analog area")
 expect(full_look.guns and full_look.boost,"Whole-screen look preserves simultaneous weapons and boost")
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
 expect(lists.list_at(rows.get_child(0).get_global_rect().get_center())==null,"A gesture control inside the list keeps its own touches")
 # A list nobody named, such as the title's settings, is found under the finger.
 lists.gesture_control=null;lists.scroll=null;lists.release();sheet.scroll_vertical=0
 lists._input(press);lists._input(swipe)
 expect(lists.target==sheet and sheet.scroll_vertical>0,"A list under the finger scrolls without being named")
 lists._input(lifted)
 # Trade and Workshop put a stock list inside the page's own scroller.
 var outer:=ScrollContainer.new();root.add_child(outer)
 outer.position=Vector2(10,10);outer.size=Vector2(350,230)
 var body:=VBoxContainer.new();body.custom_minimum_size.y=600;outer.add_child(body)
 sheet.reparent(body);sheet.custom_minimum_size=Vector2(300,200)
 lists.release();lists.scroll=outer;sheet.scroll_vertical=0
 sheet.follow_focus=true;outer.follow_focus=true
 await process_frame;await process_frame
 inside=sheet.get_global_rect().get_center();press.position=inside
 swipe.position=inside+Vector2(0,-48)
 lists._input(press);lists._input(swipe)
 expect(lists.target==sheet and sheet.scroll_vertical>0 and outer.scroll_vertical==0,"A swipe scrolls the nested stock list instead of the surrounding page")
 expect(not sheet.follow_focus and not outer.follow_focus,"Touch focus does not jump the nested list under the finger")
 lists._input(lifted)
 var arrow:=InputEventKey.new();arrow.keycode=KEY_DOWN;arrow.pressed=true;lists._input(arrow)
 expect(sheet.follow_focus and outer.follow_focus,"Keyboard navigation restores focus scrolling after a swipe")
 var outside: Vector2=sheet.get_global_rect().end+Vector2(-20,8)
 var hit=lists.control_at(root,outside)
 expect(hit==null or not sheet.is_ancestor_of(hit),"Rows clipped below a list do not intercept touches outside it")
 lists.queue_free();outer.queue_free()
 await process_frame
 var args:=OS.get_cmdline_user_args()
 var app=load("res://scenes/native_main.tscn").instantiate();app.settings_path="user://platform-check.cfg";app.save_path="user://platform-check.json"
 DirAccess.remove_absolute(app.settings_path);root.add_child(app);await process_frame
 app.open_cache(args[0]);app.launch_game(false,"Control check");await process_frame;await process_frame
 var game=current_scene;game.close_page();game.touch.mode=1;game._process(0)
 expect(game.touch.active,"Touch overlay active while flying")
 var previous_size:=root.size
 for dimensions in [Vector2i(2340,1080),Vector2i(1080,2340)]:
  root.size=dimensions;await process_frame;await process_frame;game.layout();game._process(0)
  expect(game.ui.position.length()>0,"A phone-shaped viewport applies safe margins")
  expect(game.damage_feedback.get_global_rect().is_equal_approx(root.get_visible_rect()),"Damage edges cover the full viewport outside the safe margins")
  expect(game.crosshair.get_global_rect().get_center().distance_to(root.get_visible_rect().get_center())<1,"The reticle stays centred with asymmetric phone margins")
 root.size=previous_size;await process_frame;await process_frame;game.layout()
 game.touch.drag_anywhere=true;game.save_settings()
 var touch_config:=ConfigFile.new();touch_config.load(game.settings_path)
 expect(bool(touch_config.get_value("input","touch_drag_anywhere",false)),"Whole-screen touch look is saved")
 game.touch.drag_anywhere=false;game.touch.fixed_stick=true;game.save_settings()
 touch_config.load(game.settings_path)
 expect(bool(touch_config.get_value("input","touch_fixed_stick",false)),"The fixed-stick choice is saved")
 game.touch.fixed_stick=false;game.save_settings()
 # With a stick to steer by, a drag swings the camera instead of the helm.
 game.touch.reset();game.touch.look=Vector2(120,0)
 var orbit: Dictionary=game.flight_input()
 expect(game.view.look_offset.x<0 and is_zero_approx(orbit.mouse_x),"A touch drag orbits the camera without steering")
 game.view.look_offset=Vector2.ZERO
 # The vertical inversion reaches the touch stick, not only the drag.
 game.touch.steer=Vector2(0,-1)
 var upright: float=game.flight_input().pitch
 game.invert_mouse=true
 var inverted: float=game.flight_input().pitch
 expect(upright>0 and inverted<0,"Inverted vertical steering reverses the touch stick")
 game.invert_mouse=false;game.touch.reset()
 game.show_settings("controls")
 var control_rows: Array=game.settings_panel.column.find_children("*","Button",true,false).map(func(button):return button.text)
 expect("Touch controls" in control_rows,"The controls list names the touch section without its mode")
 game.close_page()
 # The overlay's view and fullscreen switches moved into the pause menu.
 game.show_pause()
 var pause_rows: Array=game.column.find_children("*","Button",true,false).map(func(button):return button.text)
 expect(pause_rows.any(func(text):return text.begins_with("Camera · ")) and "Fullscreen / windowed" in pause_rows,"Touch pause menu offers the camera view and fullscreen")
 game.close_page()
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
 await check_drag_is_not_a_tap(game)
 game.close_page();game.controller.device=9;game.controller_connection(9,false)
 expect(game.page=="pause" and game.controller.device==-1,"Controller disconnect pauses actual gameplay")
 game.close_page();game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 expect(game.page=="pause","App focus loss pauses actual gameplay")
 game.touch.mode=1;game.session.docked=true;game.show_station()
 for i in 4:await process_frame
 var footer: Node=game.column.get_child(game.column.get_child_count()-1)
 expect(game.page_scroll.get_global_rect().encloses(footer.get_global_rect()),"Touch station footer stays visible at 720p")
 await check_touch_placement(game)
 await check_touch_margin_placement(game)
 await check_market_scrolling(game)
 game.queue_free();touch.queue_free();await process_frame
 for name in ["platform-check.cfg","platform-check.json","platform-check.json.bak"]:DirAccess.remove_absolute("user://"+name)
 print("PLATFORM_INPUT ",checks," checks; ",failures," failures");quit(1 if failures else 0)

func check_touch_placement(game) -> void:
 var layout=preload("res://native/input/touch_layout.gd")
 # Settings are text a player can edit, and older builds wrote other shapes.
 expect(layout.sanitize("not a layout").is_empty(),"A layout that is not a dictionary is discarded")
 var nonsense: Dictionary=layout.sanitize({"guns":{"x":NAN,"y":INF,"scale":99}})
 expect(layout.offset_of(nonsense,"guns")==Vector2.ZERO,"A control placed nowhere returns to its standard place")
 expect(layout.scale_of(nonsense,"guns")==layout.MAX_SCALE,"An impossible stored size is clamped to one that still draws")
 expect(layout.sanitize({"nonexistent":{"x":5,"y":5,"scale":1}}).is_empty(),"A control this build does not place is dropped")
 var stored: Dictionary=layout.sanitize({"guns":{"x":10,"y":-20,"scale":1.5},"map":{"x":0,"y":0,"scale":1}})
 expect(stored.has("guns") and not stored.has("map"),"Only controls actually moved are stored")
 expect(layout.scale_of(stored,"guns")==1.5 and layout.offset_of(stored,"guns")==Vector2(10,-20),"A stored placement reads back unchanged")
 expect(layout.decode(layout.encode(stored))==stored,"A layout survives the settings file round trip")
 expect(layout.decode("{ not json").is_empty(),"A damaged layout falls back to the standard composition")
 expect(layout.adjusted(stored,"guns",Vector2.ZERO,1.0).is_empty(),"Returning a control home leaves nothing behind")
 expect(layout.scale_of(layout.adjusted(stored,"guns",Vector2.ZERO,9.0),"guns")==layout.MAX_SCALE,"An oversized control is clamped to a size that still draws")
 # The same offsets have to mean the same composition on a different screen.
 var touch=game.touch
 # Placement is about where controls sit, so every one of them is fitted here.
 touch.mode=1;touch.set_active(true);touch.has_guns=true;touch.has_hook=true
 touch.layout={};touch.size=Vector2(1280,720);touch.arrange()
 var anchor: Vector2=touch.control_rect("guns").get_center()
 var stick_anchor: Vector2=touch.control_rect("stick").get_center()
 touch.layout={"guns":{"x":-40,"y":-30,"scale":1.5},"stick":{"x":25,"y":0,"scale":1.0}}
 touch.arrange()
 var moved: Rect2=touch.control_rect("guns")
 expect(moved.get_center().is_equal_approx(anchor+Vector2(-40,-30)*touch.unit),"A placement moves its control by the offset it stored")
 expect(is_equal_approx(moved.size.x/148.0/touch.unit,1.5),"A placement resizes its control about its own centre")
 expect(touch.control_rect("stick").get_center().is_equal_approx(stick_anchor+Vector2(25,0)*touch.unit),"The steering stick follows its placement too")
 expect(touch.button_at(moved.get_center())=="guns","A moved control answers touches where it now is")
 expect(touch.free_left>=touch.zones.boost.end.x and touch.free_right<=touch.zones.throttle.position.x,"The free HUD band is re-derived from the moved controls")
 # Editing happens over the live controls, with the panel out of the way.
 var editor=preload("res://native/presentation/touch_layout_editor.gd").new()
 game.ui.add_child(editor);editor.size=touch.size;editor.configure(touch);await process_frame
 expect(touch.layout_preview,"The editor draws every control, not only the held ones")
 expect(editor.anchors.has("guns"),"The editor measures each control at its standard place")
 editor.select("guns")
 var target: Vector2=touch.control_rect("guns").get_center()
 expect(editor.at(target)=="guns","A touch on a control selects that control")
 editor.begin(target,0)
 expect(not editor.panel.visible,"The panel gets out of the way while a control is dragged")
 editor.move_to(target+Vector2(60,0))
 expect(touch.control_rect("guns").get_center().x>target.x,"Dragging moves the control with the finger")
 editor.move_to(Vector2(9000,9000))
 var pushed: Rect2=touch.control_rect("guns")
 expect(game.get_viewport().get_visible_rect().encloses(touch.get_global_transform_with_canvas()*pushed),"A control cannot be dragged off the screen")
 editor.finish()
 expect(editor.panel.visible,"The panel returns when the finger lifts")
 editor.reset_selected()
 expect(touch.control_rect("guns").get_center().is_equal_approx(anchor),"Resetting one control returns it to the standard composition")
 editor.reset_all()
 expect(editor.working.is_empty() and touch.control_rect("stick").get_center().is_equal_approx(stick_anchor),"Resetting all returns every control")
 # The controls have to be visible and named while they are being placed: an
 # unlabelled outline tells a player nothing about what they are resizing.
 expect(touch.visible,"The controls stay on screen while their placement is edited")
 expect(not touch.active,"Placing the controls does not let them steer the submarine")
 # Nothing may sit under the panel, or that control cannot be dragged at all.
 for dimensions in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2000,1175)]:
  editor.size=dimensions;touch.size=dimensions;touch.arrange();editor.place_panel()
  await process_frame
  var panel_rect: Rect2 = editor.panel.get_rect()
  expect(Rect2(Vector2.ZERO,editor.size).encloses(panel_rect),"The editor panel stays on screen at %s"%dimensions)
  var hidden: Array = []
  for id in layout.IDS:
   var control: Rect2 = touch.control_rect(id)
   if control.size.x>0 and panel_rect.intersects(control): hidden.append(id)
  expect(hidden.is_empty(),"No control sits under the editor panel at %s: %s"%[dimensions,hidden])
 editor.size=Vector2(1280,720);touch.size=Vector2(1280,720);touch.arrange();editor.place_panel();await process_frame
 # A player who still needs the space can move the panel out of the way.
 var start: Vector2 = editor.panel.position
 var press:=InputEventScreenTouch.new();press.index=0;press.pressed=true;press.position=start+Vector2(10,10)
 editor.drag_panel(press)
 var shove:=InputEventScreenDrag.new();shove.index=0;shove.position=start+Vector2(90,10)
 editor.drag_panel(shove)
 expect(editor.panel.position.x>start.x,"The editor panel can be dragged aside")
 var lift:=InputEventScreenTouch.new();lift.index=0;lift.pressed=false;lift.position=shove.position
 editor.drag_panel(lift)
 expect(editor.panel_finger<0,"Releasing ends the panel drag")
 touch.has_guns=false;touch.place_throttle()
 expect(touch.zones.hook!=touch.weapon_home.guns,"The editor shows the harpoon at its own place")
 editor.queue_free();await process_frame
 expect(not touch.layout_preview,"Leaving the editor stops previewing idle controls")
 expect(touch.zones.hook==touch.weapon_home.guns,"Leaving the editor puts a gunless ship's harpoon back in the guns' place")
 touch.has_guns=true;touch.place_throttle()
 var before_mirroring: Rect2=touch.control_rect("guns")
 game.show_settings("touch");await process_frame;await process_frame
 var mirror=game.settings_panel.find_child("Row_touch_mirror_fire",true,false)
 expect(mirror!=null,"Touch settings offer a fire-control mirror switch")
 if mirror!=null:
  mirror.pressed.emit();await process_frame;await process_frame
  var config:=ConfigFile.new();config.load(game.settings_path)
  expect(touch.mirror_fire_control and bool(config.get_value("input","touch_mirror_fire",false)),"Mirroring applies immediately and is saved")
  expect(touch.control_rect("guns")==before_mirroring,"Mirroring keeps the player's button position and size")
  touch.mirror_fire_control=false;game.read_settings()
  expect(touch.mirror_fire_control,"Reloading settings restores the mirrored fire control")
  game.settings_panel.find_child("Row_touch_mirror_fire",true,false).pressed.emit();await process_frame
  expect(not touch.mirror_fire_control,"The same switch restores the original throttle arc")
 game.settings_panel.back()
 touch.layout={};touch.arrange();touch.set_active(false)

func check_touch_margin_placement(game) -> void:
 # Exercise GUI hit testing as well as saving: a placed button outside its
 # parent's safe rectangle must remain selectable and work during flight.
 var original_size:=root.size
 var touch=game.touch
 var original_layout: Dictionary=touch.layout.duplicate(true)
 for dimensions in [Vector2i(2340,1080),Vector2i(1080,2340)]:
  root.size=dimensions
  for i in 4:await process_frame
  game.show_settings("touch");touch.layout={};touch.arrange()
  var home: Rect2=touch.control_rect("menu")
  expect(touch.safe_rect().encloses(home),"Default touch placement stays inside the safe area at %s"%dimensions)
  game.settings_panel.hide();game.show_layout_editor()
  for i in 3:await process_frame
  var editor=game.layout_editor
  var transform: Transform2D=touch.get_global_transform_with_canvas()
  var start: Vector2=transform*home.get_center()
  var screen: Rect2=game.get_viewport().get_visible_rect()
  var target: Vector2=Vector2(screen.end.x-home.size.x*.5-2,start.y) if dimensions.x>dimensions.y else Vector2(start.x,screen.position.y+home.size.y*.5+2)
  var press:=InputEventScreenTouch.new();press.index=70;press.pressed=true;press.position=start
  game.get_viewport().push_input(press,true)
  expect(editor.finger==70 and editor.selected=="menu","A screen touch starts a placement drag at %s"%dimensions)
  var swipe:=InputEventScreenDrag.new();swipe.index=70;swipe.position=target;swipe.relative=target-start
  game.get_viewport().push_input(swipe,true)
  var moved: Rect2=touch.control_rect("menu")
  expect((transform*moved.get_center()).distance_to(target)<1,"A button follows the drag into the screen margin at %s"%dimensions)
  expect(not touch.safe_rect().has_point(moved.get_center()),"The custom button can sit beyond the safe-area boundary at %s"%dimensions)
  expect(screen.encloses(transform*moved),"The custom button stays within the actual screen at %s"%dimensions)
  press.pressed=false;press.position=target;game.get_viewport().push_input(press,true)
  press.pressed=true;game.get_viewport().push_input(press,true)
  expect(editor.finger==70 and editor.selected=="menu","A button in the margin can be picked up again through GUI input at %s"%dimensions)
  press.pressed=false;game.get_viewport().push_input(press,true)
  var saved: Dictionary=editor.working.duplicate(true)
  editor.closed.emit(saved)
  for i in 3:await process_frame
  touch.layout={};game.read_settings();touch.arrange()
  expect(touch.layout==saved and touch.control_rect("menu").is_equal_approx(moved),"Done saves and reloads the margin placement at %s"%dimensions)
  if dimensions.x>dimensions.y:
   root.size=Vector2i(1080,2340)
   for i in 4:await process_frame
   expect(game.get_viewport().get_visible_rect().encloses(touch.get_global_transform_with_canvas()*touch.control_rect("menu")),"Rotating a margin placement keeps the button on screen")
   root.size=dimensions
   for i in 4:await process_frame
   expect(touch.layout==saved and touch.control_rect("menu").is_equal_approx(moved),"Turning back restores the preferred margin placement")
  game.close_page();touch.set_active(true)
  finger(touch,71,target,true)
  expect(touch.fingers.get(71,"")=="menu","The moved button answers flight touches in the margin at %s"%dimensions)
  finger(touch,71,target,false,true)
  game.show_settings("touch");game.settings_panel.hide();game.show_layout_editor()
  game.layout_editor.reset_all();game.layout_editor.closed.emit(game.layout_editor.working)
  for i in 3:await process_frame
  expect(touch.layout.is_empty() and touch.safe_rect().encloses(touch.control_rect("menu")),"Reset all restores the inset default at %s"%dimensions)
  if dimensions.x>dimensions.y:
   # The floating stick also has to accept a thumb in the margin without
   # pulling the visible stick back against the safe-area boundary.
   game.settings_panel.hide();game.show_layout_editor()
   for i in 3:await process_frame
   editor=game.layout_editor;editor.select("stick");editor.grab=Vector2.ZERO
   editor.move_to(Vector2(-9000,touch.stick_home.y))
   editor.closed.emit(editor.working)
   for i in 3:await process_frame
   game.close_page();touch.fixed_stick=false;touch.set_active(true)
   var thumb: Vector2=Vector2(screen.position.x+minf(game.ui.get_global_rect().position.x*.5,touch.stick_radius*.5),(touch.get_global_transform_with_canvas()*touch.stick_home).y)
   finger(touch,72,thumb,true)
   expect(touch.engaged,"A floating stick placed in the margin accepts a thumb there")
   expect((transform*(touch.stick_center-Vector2.ONE*touch.stick_radius)).x<game.ui.get_global_rect().position.x,"The floating stick can still extend into the screen margin")
   finger(touch,72,thumb,false)
  touch.layout={};game.save_settings()
 touch.layout=original_layout;game.save_settings()
 root.size=original_size
 for i in 4:await process_frame
 touch.arrange();game.show_station()

func check_mirrored_throttle(touch) -> void:
 var levels: Array=[]
 var record:=func(percent):levels.append(percent)
 touch.throttle_changed.connect(record)
 for dimensions in [Vector2(1280,720),Vector2(589,1280),Vector2(1920,1080)]:
  touch.size=dimensions;touch.layout={};touch.arrange()
  var offset: Vector2=Vector2(180*touch.unit,touch.zones.guns.get_center().y)-touch.zones.guns.get_center()
  touch.layout={"guns":{"x":offset.x/touch.unit,"y":0,"scale":1.25}};touch.arrange()
  var area: Rect2=touch.zones.throttle;var center: Vector2=area.get_center();var radius: float=touch.arc_radius(area)
  var original_button: Rect2=touch.zones.guns
  touch.mirror_fire_control=true
  expect(touch.zones.guns==original_button,"Mirroring a moved, resized fire control keeps its placement")
  expect(touch.button_at(center)=="guns","Mirroring keeps the centre available for firing")
  var old_middle: Vector2=center+Vector2(-1,-1).normalized()*radius
  expect(not touch.on_arc(area,old_middle),"The old throttle arc no longer intercepts touches")
  touch.throttle_level=.4;levels.clear()
  finger(touch,11,center+Vector2(radius,0),true)
  for level in [.25,.5,.75,1.0]:drag(touch,11,center+Vector2.from_angle(-PI*.5*level)*radius,Vector2.ZERO)
  finger(touch,11,center+Vector2(0,-radius),false)
  expect(levels==[0,25,50,75,100],"The right-side arc increases from its outer end to the top at %s"%dimensions)
  expect(not touch.snapshot().guns,"Dragging the mirrored throttle does not fire the weapon")
  touch.has_guns=false;touch.place_throttle()
  expect(touch.button_at(center)=="hook" and touch.on_arc(area,center+Vector2(1,-1).normalized()*radius),"The mirrored arc also works when the harpoon occupies the fire button")
  touch.has_guns=true;touch.place_throttle();touch.reset()
  touch.mirror_fire_control=false
  expect(touch.on_arc(area,old_middle),"Turning mirroring off restores the original arc")
 touch.throttle_changed.disconnect(record)
 touch.layout={};touch.size=Vector2(1280,720);touch.arrange();touch.reset()

func pointer(game, pressed: bool, at: Vector2, moving: bool=false) -> void:
 var event: InputEventMouse=InputEventMouseMotion.new() if moving else InputEventMouseButton.new()
 event.device=InputEvent.DEVICE_ID_EMULATION;event.position=at;event.global_position=at
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 if not moving:event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
 game.get_viewport().push_input(event,true)
func check_drag_is_not_a_tap(game) -> void:
 # A finger dragged across a button is moving the screen: the button must
 # not fire, and the next tap must land where it is made, not on it.
 var layer:=CanvasLayer.new();layer.layer=100;game.add_child(layer)
 var dragged:=Button.new();dragged.position=Vector2(20,20);dragged.size=Vector2(300,60);layer.add_child(dragged)
 var other:=Button.new();other.position=Vector2(20,120);other.size=Vector2(300,60);layer.add_child(other)
 var fired:=[0,0];dragged.pressed.connect(func():fired[0]+=1);other.pressed.connect(func():fired[1]+=1)
 await process_frame
 pointer(game,true,Vector2(40,50));pointer(game,true,Vector2(90,52),true);pointer(game,true,Vector2(200,52),true);pointer(game,false,Vector2(200,52))
 expect(fired==[0,0],"A drag across a button does not press it")
 pointer(game,true,Vector2(60,150));pointer(game,false,Vector2(61,150))
 expect(fired==[0,1],"The tap after a drag lands on the button tapped")
 pointer(game,true,Vector2(60,50));pointer(game,false,Vector2(62,51))
 expect(fired==[1,1],"A tap on a button still presses it")
 layer.queue_free()

func check_market_scrolling(game) -> void:
 # Send real touch events through the viewport, including Godot's emulated
 # mouse press, over each part of the actual Trade and Workshop rows.
 game.touch.mode=1;game.session.docked=true
 game.session.campaign.rebel_stations[game.session.station_id]=true
 var station: Dictionary=game.session.stations[game.session.station_id]
 station.tech=100;station.cargo=[]
 for id in mini(20,game.content.data.tables.goods.size()):station.cargo.append(game.session.make_goods(id,5))
 var original_size:=root.size
 for dimensions in [Vector2i(2340,1080),Vector2i(1080,2340)]:
  root.size=dimensions
  for i in 4:await process_frame
  for kind in ["trade","manufacture"]:
   game.show_market(kind,true)
   for i in 5:await process_frame
   var stock: ScrollContainer=game.column.find_child("StockRows_"+kind,true,false)
   expect(stock!=null and stock.get_v_scroll_bar().max_value>stock.get_v_scroll_bar().page,"The %s fixture has scrollable stock"%kind)
   if stock==null:continue
   var row: Button=stock.find_child("Stock_1",true,false)
   if row==null:expect(false,"The %s fixture has a second row"%kind);continue
   var cells:=row.get_child(0)
   var controls: Array=[row,cells.get_child(0),cells.get_child(1).get_child(0),cells.get_child(1).get_child(1),cells.get_child(2)]
   for control in controls:
    game.touch_scroll.release();stock.scroll_vertical=0
    for i in 2:await process_frame
    var point: Vector2=control.get_global_rect().get_center()
    if control==row:point.x=row.global_position.x+6
    var at: Vector2=root.get_final_transform()*point
    var outer_before: int=game.page_scroll.scroll_vertical
    var press:=InputEventScreenTouch.new();press.index=0;press.position=at;press.pressed=true
    Input.parse_input_event(press);await process_frame
    expect(stock.scroll_vertical==0,"Touching a %s row does not jump to its focus"%kind)
    for step in 4:
     var motion:=InputEventScreenDrag.new();motion.index=0;motion.relative=Vector2(0,-24);at+=motion.relative;motion.position=at
     Input.parse_input_event(motion);await process_frame
    var lift:=InputEventScreenTouch.new();lift.index=0;lift.position=at;lift.pressed=false
    Input.parse_input_event(lift);await process_frame
    expect(stock.scroll_vertical>20,"Dragging over %s %s scrolls its stock"%[kind,control.get_class()])
    expect(game.page_scroll.scroll_vertical==outer_before,"Dragging %s stock leaves the surrounding page still"%kind)
    expect(game.market_selection==0 and is_instance_valid(row),"Dragging a %s row does not select or rebuild it"%kind)
   game.touch_scroll.release();stock.scroll_vertical=0
   for i in 2:await process_frame
   var tap:=InputEventScreenTouch.new();tap.index=0;tap.pressed=true;tap.position=root.get_final_transform()*row.get_global_rect().get_center()
   Input.parse_input_event(tap);await process_frame
   tap=tap.duplicate();tap.pressed=false;Input.parse_input_event(tap)
   for i in 4:await process_frame
   expect(game.market_selection==1,"A tap after scrolling still selects the %s row"%kind)
 root.size=original_size
