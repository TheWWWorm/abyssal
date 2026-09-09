extends SceneTree
## Exercise GUI event routing with real joypad events, including nonzero device IDs.
var failures := 0
var checks := 0
func expect(ok: bool, message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
 for i in 8:await process_frame
func tap(button: int, device: int=3) -> void:
 for down in [true,false]:
  var event:=InputEventJoypadButton.new();event.device=device;event.button_index=button;event.pressed=down
  Input.parse_input_event(event)
  await process_frame
func tilt(axis: int, value: float, device: int=3) -> void:
 var event:=InputEventJoypadMotion.new();event.device=device;event.axis=axis;event.axis_value=value
 Input.parse_input_event(event)
 await process_frame
func screen_touch(down: bool, point: Vector2) -> void:
 var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=down
 Input.parse_input_event(event)
 await process_frame
func mouse_motion(relative: Vector2, device: int=0) -> void:
 var event:=InputEventMouseMotion.new();event.relative=relative;event.device=device
 Input.parse_input_event(event)
 await process_frame
func keyboard(down: bool) -> void:
 var event:=InputEventKey.new();event.keycode=KEY_W;event.physical_keycode=KEY_W;event.pressed=down
 Input.parse_input_event(event)
 await process_frame
func focused_text() -> String:
 var control:=root.gui_get_focus_owner()
 return control.text if control is Button else ""
func run() -> void:
 root.size=Vector2i(1280,720)
 var app=load("res://scenes/native_main.tscn").instantiate()
 app.settings_path="user://gamepad-ui-check.cfg";app.save_path="user://gamepad-ui-check.json"
 for path in [app.settings_path,app.save_path,app.save_path+".bak"]:DirAccess.remove_absolute(path)
 root.add_child(app);await settle()
 expect(root.gui_get_focus_owner()==app.title_menu.footer,"Empty title focuses the content chooser")
 await tap(JOY_BUTTON_DPAD_UP)
 expect(focused_text()=="Exit","D-pad navigates the title on a nonzero controller")
 await tap(JOY_BUTTON_DPAD_UP)
 expect(focused_text()=="Help","D-pad moves to Help")
 await tap(JOY_BUTTON_A)
 expect(app.title_menu.help_open,"A activates Help")
 await tap(JOY_BUTTON_A)
 expect(not app.title_menu.help_open,"One press toggles Help exactly once")
 await tilt(JOY_AXIS_LEFT_Y,-1);await tilt(JOY_AXIS_LEFT_Y,0)
 expect(focused_text()=="Options","Left stick navigates the title")
 await tap(JOY_BUTTON_A);await settle()
 expect(app.modal.visible,"A opens title Options")
 await tap(JOY_BUTTON_B);await settle()
 expect(not app.modal.visible and root.gui_get_focus_owner()==app.title_menu.footer,"B closes Options and restores title focus")
 app.open_cache(OS.get_cmdline_user_args()[0]);await settle()
 expect(root.gui_get_focus_owner()==app.title_menu.new_button,"Imported content focuses Start")
 await tap(JOY_BUTTON_A);await settle()
 expect(app.modal.visible and root.gui_get_focus_owner() is LineEdit,"A opens diver creation")
 await tap(JOY_BUTTON_DPAD_DOWN)
 var portrait:=root.gui_get_focus_owner() as OptionButton
 expect(portrait!=null,"D-pad leaves the name field for portrait options")
 if portrait!=null:
  var original:=portrait.selected
  await tap(JOY_BUTTON_A);await settle()
  expect(portrait.get_popup().visible,"A opens a portrait dropdown")
  await tap(JOY_BUTTON_DPAD_DOWN);await tap(JOY_BUTTON_A);await settle()
  expect(not portrait.get_popup().visible and portrait.selected!=original,"D-pad and A select a dropdown item")
  await tap(JOY_BUTTON_A);await tap(JOY_BUTTON_B);await settle()
  expect(not portrait.get_popup().visible and app.modal.visible,"B cancels only the open dropdown")
 await tap(JOY_BUTTON_B);await settle()
 expect(not app.modal.visible,"B returns from diver creation")
 await tap(JOY_BUTTON_A);await settle()
 for i in 12:
  if focused_text()=="BEGIN EXPEDITION >":break
  await tap(JOY_BUTTON_DPAD_DOWN)
  expect(app.modal.is_ancestor_of(root.gui_get_focus_owner()),"Diver navigation stays inside its dialog")
 expect(focused_text()=="BEGIN EXPEDITION >","Controller reaches Begin expedition")
 await tap(JOY_BUTTON_A);await settle()
 var game=current_scene
 expect(not game.touch.enabled(),"Title gamepad input survives the scene change")
 game.set_process(false);game.close_page()
 await tap(JOY_BUTTON_START);await settle()
 expect(game.page=="pause" and focused_text()=="Resume","Start opens the pause menu with usable focus")
 await tap(JOY_BUTTON_DPAD_DOWN)
 expect(focused_text()=="Overworld map","D-pad navigates pause options")
 await tap(JOY_BUTTON_A);await settle()
 expect(game.page=="map","A opens the world map")
 await tap(JOY_BUTTON_B);await settle()
 expect(game.page!="map","B leaves the world map")
 game.show_controls();await settle()
 var navigated:=false
 for i in 40:
  await tap(JOY_BUTTON_DPAD_DOWN)
  var control:=root.gui_get_focus_owner()
  if control is HSlider:
   var before: float=control.value
   await tap(JOY_BUTTON_DPAD_RIGHT)
   expect(control.value>before,"D-pad adjusts a settings slider")
   expect(game.sheet_scroll.scroll_vertical>0,"Settings scroll to the focused slider")
   expect(game.sheet_scroll.get_global_rect().intersects(control.get_global_rect()),"Focused settings stay on screen")
   navigated=true;break
 expect(navigated,"Controller navigation reaches the settings sliders")
 game.show_dialogue([{"speaker":"Test","text":"Controller briefing"}],game.close_page);await settle()
 await tap(JOY_BUTTON_A);await settle()
 expect(game.page.is_empty(),"A advances dialogue and resumes gameplay")
 expect(not game.controller.snapshot().fire,"Selecting a menu does not leave the weapon firing")
 await tap(JOY_BUTTON_START);await settle();await tap(JOY_BUTTON_A);await settle()
 expect(game.page.is_empty(),"A activates Resume")
 # The first pad and a hot-plugged replacement must both operate menus.
 await tap(JOY_BUTTON_START,0);await settle();await tap(JOY_BUTTON_A,0);await settle()
 expect(game.page.is_empty(),"Controller zero also activates Resume")
 game.touch.mode=0
 expect(not game.touch.enabled(),"Gamepad used in menus keeps Auto touch controls hidden")
 var point: Vector2=game.touch.stick_home
 await screen_touch(true,point)
 expect(game.touch.visible and game.touch.engaged,"Touch brings the flight pad back and uses the first finger")
 expect(not game.strafe_enabled(),"Auto steering switches back to touch turning")
 await mouse_motion(Vector2(8,3),InputEvent.DEVICE_ID_EMULATION)
 expect(game.touch.visible and game.touch.engaged,"Touch-generated mouse motion cannot hide or release the pad")
 await tilt(JOY_AXIS_LEFT_X,.12)
 expect(game.touch.visible,"Controller drift does not steal touch input")
 await tilt(JOY_AXIS_TRIGGER_LEFT,-1)
 expect(game.touch.visible,"A resting trigger does not steal touch input")
 await keyboard(false)
 expect(game.touch.visible,"A key release does not steal touch input")
 await tilt(JOY_AXIS_LEFT_X,.8)
 expect(not game.touch.visible and game.touch.fingers.is_empty() and game.touch.steer==Vector2.ZERO,"Intentional stick motion hides pads and clears held touch controls")
 expect(game.strafe_enabled(),"Auto steering restores gamepad strafe")
 await tilt(JOY_AXIS_LEFT_X,0);await screen_touch(false,point)
 expect(not game.touch.visible,"Lifting a previous touch does not restore the pad")
 await screen_touch(true,point);await screen_touch(false,point)
 expect(game.touch.visible,"The next screen touch restores the pad")
 await keyboard(true)
 expect(not game.touch.visible,"Keyboard input hides the touch pad")
 await keyboard(false);await screen_touch(true,point);await screen_touch(false,point)
 await mouse_motion(Vector2.ZERO)
 expect(game.touch.visible,"Stationary mouse events leave touch active")
 await mouse_motion(Vector2(6,2))
 expect(not game.touch.visible,"Physical mouse motion hides the touch pad")
 await screen_touch(true,point);await screen_touch(false,point)
 await tap(JOY_BUTTON_A)
 expect(not game.touch.visible,"Gamepad button input hides the touch pad")
 game.show_pause();await settle()
 await screen_touch(true,Vector2(1200,650));await screen_touch(false,Vector2(1200,650))
 expect(game.touch.enabled() and not game.touch.visible,"Touch in a menu selects touch mode without overlaying flight controls")
 await tap(JOY_BUTTON_START);await settle()
 expect(game.page.is_empty() and not game.touch.visible,"Resuming with a pad keeps touch controls hidden")
 game.queue_free();await settle()
 for name in ["gamepad-ui-check.cfg","gamepad-ui-check.json","gamepad-ui-check.json.bak"]:DirAccess.remove_absolute("user://"+name)
 print("GAMEPAD_UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
