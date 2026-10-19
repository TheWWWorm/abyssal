extends SceneTree
const Presence = preload("res://native/platform/discord_presence.gd")
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var menu := Presence.activity_for({},1234)
	expect(menu.details=="In the main menu" and not menu.has("state"),"The main menu carries no stale ship")
	expect(menu.timestamps.start==1234 and menu.assets.large_image=="abyssal","The session clock and original artwork key stay stable")
	var checks := [
		[{"page":""},"Exploring the ocean"],
		[{"page":"","autopilot":true},"Cruising on autopilot"],
		[{"page":"","combat":true,"autopilot":true},"In combat"],
		[{"page":"","fishing":true,"combat":true},"Fishing in the deep"],
		[{"page":"","transit":true,"combat":true},"Travelling through S.T.R.E.A.M."],
		[{"page":"pause","combat":true},"Paused"],
		[{"page":"settings","docked":true},"Adjusting settings"],
		[{"page":"station","docked":true},"Docked at a station"],
		[{"page":"market","market":"ships","docked":true},"Choosing a ship"],
		[{"page":"market","market":"equipment"},"Outfitting the submarine"],
		[{"page":"market","market":"trade"},"Trading at a station"],
		[{"page":"dialogue","mission":"A secret story title"},"Following the story"],
		[{"page":"map","autopilot":true},"Charting a course"]]
	for check in checks:
		var context: Dictionary=check[0];context["ship"]="Ino"
		var result := Presence.activity_for(context,1234)
		expect(result.details==check[1],"Activity follows actual state: "+str(context))
		expect(result.state=="Piloting Ino" and not JSON.stringify(result).contains("secret"),"Only activity and the equipped ship are shared")
	var localized := Presence.activity_for({"ship":"潜水艦".repeat(90)},1234)
	expect(localized.state.to_utf8_buffer().size()<=128 and not localized.state.contains("�"),"Long localized ship names stay valid within Discord's byte limit")
	var changed := Presence.activity_for({"ship":"Replacement ship"},1234)
	expect(changed.state=="Piloting Replacement ship" and changed.timestamps==menu.timestamps,"Buying a ship changes presence without resetting the session clock")
	expect(Presence.application_id()=="1561821965210222642","The game's public Discord application is configured")
	if "--pipe-probe" in OS.get_cmdline_user_args():
		var bridge := Presence.new();root.add_child(bridge)
		bridge.start()
		expect(not bridge.helper.is_empty(),"The desktop helper starts with a nonblocking OS pipe")
		if not bridge.helper.is_empty():
			var helper_pid := int(bridge.helper.pid)
			bridge.helper.stdio.store_string(JSON.stringify(Presence.activity_for({"ship":"Pipe test ship"},1234))+"\n")
			expect(bridge.helper.stdio.get_error()==OK,"Godot writes activity through the pipe")
			await create_timer(.3).timeout
			bridge.stop()
			for attempt in 20:
				if not OS.is_process_running(helper_pid):break
				await create_timer(.05).timeout
			expect(not OS.is_process_running(helper_pid),"Closing the Godot pipe leaves no helper process")
		bridge.queue_free()
	print("DISCORD_PRESENCE ",failures," failures")
	quit(1 if failures else 0)
