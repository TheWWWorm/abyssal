extends SceneTree
const StationTheme=preload("res://native/presentation/station_theme.gd")
var failures := 0
var picked: Array=[]
func expect(value: bool, why: String) -> void:
	if not value: failures+=1; push_error(why)
func _initialize() -> void: call_deferred("checks")
func touch(at: Vector2, pressed: bool) -> void:
	var event:=InputEventScreenTouch.new();event.index=0;event.position=at;event.pressed=pressed
	Input.parse_input_event(event);await settle()
func drag(from: Vector2, to: Vector2) -> void:
	var steps := 12
	for i in range(1,steps+1):
		var event:=InputEventScreenDrag.new();event.index=0
		event.position=from.lerp(to,float(i)/steps);event.relative=(to-from)/steps;event.velocity=(to-from)*5
		Input.parse_input_event(event);await settle()
func settle() -> void:
	for i in 2:await process_frame
func checks() -> void:
	root.size=Vector2i(1152,648)
	var list:=OptionButton.new();list.position=Vector2(400,20);root.add_child(list)
	for i in 200:list.add_item("Station %d"%i,i)
	list.select(0);StationTheme.style_option(list,false,true)
	list.item_selected.connect(func(index):picked.append(index))
	var popup:=list.get_popup()
	list.show_popup();await settle()
	var scroll: ScrollContainer
	for node in popup.find_children("*","ScrollContainer",true,false):scroll=node
	if scroll==null:
		var pending: Array=popup.get_children(true)
		while not pending.is_empty():
			var node: Node=pending.pop_front()
			if node is ScrollContainer:scroll=node;break
			pending.append_array(node.get_children(true))
	expect(scroll!=null and popup.visible,"The list opens with a scroll area")
	var rect:=Rect2(popup.position,popup.size)
	var middle:=rect.position+Vector2(rect.size.x*.4,rect.size.y*.6)
	await touch(middle,true)
	await drag(middle,middle-Vector2(0,200))
	await touch(middle-Vector2(0,200),false)
	print("scrolled to ",scroll.scroll_vertical," picked ",picked," open ",popup.visible)
	expect(scroll.scroll_vertical>150,"A finger drag scrolls the list")
	expect(picked.is_empty() and popup.visible,"Ending a drag picks nothing and keeps the list open")
	expect(not popup.is_item_disabled(5),"Rows are selectable again after the drag")
	await touch(middle,true);await touch(middle,false)
	print("after tap picked ",picked," open ",popup.visible)
	expect(picked.size()==1 and picked[0]>3,"A tap still picks the row under the finger")
	print("POPUP_DRAG %d failures"%failures)
	quit(1 if failures else 0)
