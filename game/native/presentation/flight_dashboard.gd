extends Control
## Instrument console following art/refresh3/ui-v3.png and gameplay-target-v3.png.
const Scanner=preload("res://native/presentation/scanner.gd")
const Library=preload("res://scripts/model_library.gd")
var world
var imported_art
var throttle_keys := ["W","S"]
var navigation := ""
var objective_text := ""
var depth := 0
var safe_min := 0
var safe_max := 0
var stopped := false
var clock := 0.0
var redraw_clock := 0.0
var icons := {}
var font := SystemFont.new()
const INK=Color("c9ded5")
const MINT=Color("8fddc4")
const AMBER=Color("d7ae6a")
const DIM=Color("789997")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;font.font_names=PackedStringArray(["DejaVu Sans Mono","Liberation Mono"])
	resized.connect(queue_redraw)
func _process(delta: float) -> void:
	clock+=delta;redraw_clock+=delta
	if redraw_clock>.04 and visible:redraw_clock=0;queue_redraw()
func update(owner_world) -> void:
	world=owner_world
	depth=world.region.player.depth;safe_min=world.session.ship.minimum_depth;safe_max=world.session.ship.maximum_depth;stopped=world.region.player.stopped
	navigation="AUTOPILOT %d×"%world.speed if world.autopilot else "MANUAL"
func text(at: Vector2,value: String,color: Color=INK,pixels: int=13,width: float=-1) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,width,pixels,color)
func center_text(at: Vector2,value: String,color: Color,pixels: int) -> void:
	text(at-Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x*.5,0),value,color,pixels)
func plate(rect: Rect2,inset: bool=false) -> void:
	var x=rect.position.x;var y=rect.position.y;var w=rect.size.x;var h=rect.size.y;var c=7.0 if inset else 13.0
	var points=PackedVector2Array([Vector2(x+c,y),Vector2(x+w-c,y),Vector2(x+w,y+c),Vector2(x+w,y+h-c),Vector2(x+w-c,y+h),Vector2(x+c,y+h),Vector2(x,y+h-c),Vector2(x,y+c)])
	draw_colored_polygon(points,Color("061719ee") if inset else Color("172224ee"));var edge=points.duplicate();edge.append(points[0]);draw_polyline(edge,Color("64736a") if inset else Color("817d66"),1.0,true)
	if not inset:
		draw_line(Vector2(x+17,y+4),Vector2(x+w-17,y+4),Color("82908366"),1,true)
		for p in [Vector2(x+11,y+12),Vector2(x+w-11,y+12),Vector2(x+11,y+h-12),Vector2(x+w-11,y+h-12)]:
			draw_circle(p,2.8,Color("060c0e"));draw_line(p-Vector2(1.5,0),p+Vector2(1.5,0),Color("8b8772"),1,true)
func meter(at: Vector2,width: float,value: float,color: Color) -> void:
	for i in 20:
		draw_rect(Rect2(at+Vector2(i*width/20,0),Vector2(width/20-2,10)),color if float(i)/20<value else Color("263b3d"))
func _draw() -> void:
	if world==null or world.region==null:return
	var r=world.region;var player=r.player;var ship=world.session.ship;var w=size.x;var h=size.y
	# Three separate instruments, matching the generated target's open silhouette.
	# The radio occupies the lower left; no full-width bar or rectangular radar box.
	var left=maxf(360,w*.275);var width=minf(760,w-345-left);var right=left+width
	var y=h-112
	draw_line(Vector2(left,y+2),Vector2(right,y+2),Color("92795388"),1,true)
	draw_rect(Rect2(left,y,width,88),Color("03151b55"))
	text(Vector2(left+18,y+19),"THROTTLE",MINT,11)
	text(Vector2(left+25,y+45),"%d %%"%roundi(player.throttle),INK,22)
	for i in 20:
		var x=left+16+i*4.7
		draw_line(Vector2(x,y+56),Vector2(x-4,y+67),MINT if i*5<player.throttle else Color("294b48"),2,true)
	text(Vector2(left+14,y+80),"S  0   I  II  III  IV  W",DIM,8)
	var slots: Array=r.loadout.groups;var count=mini(4,maxi(1,slots.size()));var bank_left=left+122
	var slot_width=minf(112,(width-246)/maxi(4,count))
	for i in maxi(4,count):
		var at=Vector2(bank_left+i*slot_width,y)
		draw_line(at+Vector2(-5,12),at+Vector2(-5,76),Color("56645988"),1,true)
		text(at+Vector2(4,19),str(i+1),AMBER,12)
		if i>=slots.size():text(at+Vector2(10,59),"—",DIM,15);continue
		var weapon=slots[i][0];var id: int=weapon.equipment_id
		if imported_art!=null and not icons.has(id):icons[id]=imported_art.item(id,"equipment")
		if icons.get(id)!=null:draw_texture_rect(icons[id],Rect2(at+Vector2(14,24),Vector2(slot_width-28,30)),false,Color(.70,.86,.82))
		text(at+Vector2(5,67),"HARPOON" if weapon.fishing else "%d GUN%s"%[slots[i].size(),"S" if slots[i].size()>1 else ""],AMBER,9)
		if i==r.loadout.selected:draw_line(at+Vector2(7,77),at+Vector2(slot_width-12,77),MINT,1,true)
	var nx=right-108
	text(Vector2(nx,y+22),"MANUAL" if not world.autopilot else "AUTO %d×"%world.speed,MINT,10)
	draw_circle(Vector2(right-18,y+18),3,MINT)
	text(Vector2(nx,y+46),"FULL STOP" if stopped else "%04.1f m/s"%(player.speed_factor*10.0*player.throttle/100.0),INK,12)
	var boost=preload("res://native/presentation/flight_instruments.gd").boost_state(player)
	text(Vector2(nx,y+65),("BOOST %.1f s"%boost.seconds if boost.mode in ["active","charging"] else "BOOST "+str(boost.mode).to_upper()),DIM,8)
	meter(Vector2(nx,y+71),88,boost.fraction,AMBER)
	draw_top_console(w)
	draw_depth(h);draw_sonar(Vector2(w-140,h-145),108)
func draw_top_console(w: float) -> void:
	draw_set_transform(Vector2(w*.5,0),0,Vector2.ONE*minf(1.0,(w-64)/960.0))
	var center := 0.0
	var left := center-480
	draw_rect(Rect2(left-12,8,984,126),Color("03121be0"))
	var health=world.region.player.health
	# Keep critical instruments together even on ultrawide displays.
	draw_line(Vector2(left,19),Vector2(center+480,19),Color("9b805288"),1,true)
	draw_line(Vector2(left,22),Vector2(center+480,22),Color("9b805233"),1,true)
	text(Vector2(left+10,41),"01 / OBJECTIVE",AMBER,10)
	var lines := objective_text.split("\n")
	text(Vector2(left+10,64),lines[0] if not lines.is_empty() else "Explore the ocean",INK,15,280)
	text(Vector2(left+10,86),lines[1] if lines.size()>1 else world.session.stations[world.session.station_id].name.to_upper(),MINT,12,280)
	if lines.size()>2:text(Vector2(left+10,126),lines[2],AMBER,11,280)
	text(Vector2(left+10,106),"CARGO %d/%d   •   %d CR"%[world.session.ship.cargo_used,world.session.ship.capacity(),world.session.credits],DIM,11,290)
	var f: Array=world.region.player.pose.forward
	var heading=fposmod(rad_to_deg(atan2(f[0],f[2])),360)
	var pivot=Vector2(center-50,64)
	draw_arc(pivot,39,-PI,0,40,Color("b0935b"),1,true)
	for i in 13:
		var a=-PI+i*PI/12;draw_line(pivot+Vector2.from_angle(a)*39,pivot+Vector2.from_angle(a)*(34 if i%3==0 else 36),DIM,1,true)
	center_text(pivot+Vector2(0,9),"%03d°"%roundi(heading),MINT,21)
	center_text(pivot+Vector2(0,30),"HEADING",AMBER,9)
	var values := [health.hull,health.shield,health.armor]
	var maximum := [health.max_hull,world.session.ship.shield,world.session.ship.armor]
	for i in 3:
		var at := Vector2(center+112+i*124,66)
		var ratio := clampf(float(values[i])/maxi(1,maximum[i]),0,1)
		var color := Color("ee876c") if i==0 and ratio<.3 else MINT
		draw_arc(at,30,PI*.8,PI*2.2,48,Color("2c4746"),3,true)
		draw_arc(at,30,PI*.8,PI*.8+PI*1.4*ratio,48,color,3,true)
		draw_arc(at,35,PI*.8,PI*2.2,48,Color("98815488"),1,true)
		center_text(at+Vector2(0,-39),["HULL","SHIELD","ARMOR"][i],AMBER,11)
		center_text(at+Vector2(0,7),"%d"%values[i] if maximum[i]>0 else "—",color,22)
		center_text(at+Vector2(0,44),"/ %d"%maximum[i] if maximum[i]>0 else "ABSENT",DIM,10)
	draw_set_transform(Vector2.ZERO)
func draw_depth(h: float) -> void:
	var top=182.0;var bottom=h-285;var span=maxf(170,bottom-top)
	var low=mini(safe_min-1000,depth-1000);var high=maxi(safe_max+1000,depth+1000)
	low=maxi(0,int(floor(low/1000.0))*1000);high=int(ceil(high/1000.0))*1000
	text(Vector2(30,148),"DEPTH",AMBER,15);text(Vector2(31,168),"m",DIM,11)
	draw_line(Vector2(33,top),Vector2(33,top+span),AMBER,2,true)
	var a=clampf(float(safe_min-low)/(high-low),0,1);var b=clampf(float(safe_max-low)/(high-low),0,1)
	draw_line(Vector2(28,top+a*span),Vector2(28,top+b*span),Color("83cdb9"),2,true)
	for value in range(low,high+1,250):
		var y=top+float(value-low)/(high-low)*span;var major=value%1000==0
		draw_line(Vector2(34,y),Vector2(48 if major else 39,y),AMBER if major else DIM,1,true)
		if major:text(Vector2(53,y+4),str(value),AMBER,11)
	var cursor=top+float(depth-low)/(high-low)*span
	var color=MINT if depth>=safe_min and depth<=safe_max else Color("e6b85b") if depth<safe_min else Color("e9977d")
	var points=PackedVector2Array([Vector2(34,cursor),Vector2(47,cursor-14),Vector2(111,cursor-14),Vector2(118,cursor-7),Vector2(118,cursor+14),Vector2(47,cursor+14)])
	draw_colored_polygon(points,Color("10332ff2"));var edge=points.duplicate();edge.append(points[0]);draw_polyline(edge,color,1,true)
	text(Vector2(49,cursor+6),str(depth),color,18)
	text(Vector2(29,top+span+27),"SAFE %d–%d"%[safe_min,safe_max],DIM,9)
func draw_compass(w: float) -> void:
	var f: Array=world.region.player.pose.forward
	var heading=fposmod(rad_to_deg(atan2(f[0],f[2])),360)
	var center=w*.5;var width=minf(450,w*.31)
	plate(Rect2(center-width*.5-16,16,width+32,66),true)
	for offset in range(-60,61,5):
		var angle=roundi(heading/5)*5+offset;var x=center+(angle-heading)*width/120
		var major=posmod(angle,30)==0;draw_line(Vector2(x,33),Vector2(x,41 if major else 37),DIM,1,true)
		if major:
			var v=posmod(angle,360);var value={0:"N",90:"E",180:"S",270:"W"}.get(v,str(v))
			text(Vector2(x-8,26),value,AMBER,11)
	draw_colored_polygon(PackedVector2Array([Vector2(center,48),Vector2(center-4,43),Vector2(center+4,43)]),MINT)
	text(Vector2(center-40,67),"HDG %03d°"%roundi(heading),MINT,12)
	if world.autopilot:text(Vector2(center-150,89),world.session.stations[world.destination].name.to_upper() if world.destination>=0 else "LOCAL APPROACH",INK,12,300)
func draw_sonar(center: Vector2,radius: float) -> void:
	text(center+Vector2(-24,-radius-15),"SONAR",AMBER,11)
	draw_circle(center,radius,Color("04182040"));draw_arc(center,radius,0,TAU,96,AMBER,1.0,true)
	draw_arc(center,radius+3,0,TAU,96,Color("5b695d66"),1,true)
	draw_arc(center,radius-7,0,TAU,96,Color("75633e"),1,true)
	for ring in 4:draw_arc(center,radius*(ring+1)/4,0,TAU,64,Color("436260"),1,true)
	for i in 12:
		var direction=Vector2.from_angle(i*TAU/12);draw_line(center,center+direction*radius,Color("263f41"),1,true)
	var sweep=clock*.6
	for j in 18:draw_line(center,center+Vector2.from_angle(sweep-j*.022)*radius,Color(.35,.85,.70,(1-float(j)/18)*.12),2,true)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-5),center+Vector2(-4,4),center+Vector2(4,4)]),MINT)
	var pose: Transform3D=world.region.player.pose.godot_transform();var inverse=pose.basis.inverse();var contacts=[]
	contacts.append({"at":Vector3.ZERO,"color":AMBER})
	for i in world.region.gates.size():
		if world.region.gate_index(i)==i:contacts.append({"at":Library.point(world.region.gates[i]),"color":Color("be99f2")})
	for role in ["enemy","friend","creature"]:
		for actor in world.region.enemies if role=="enemy" else world.region.friends if role=="friend" else world.region.creatures:
			var detail=Scanner.describe(actor,role,world.session.ship.passive_radar,world.region.mission.kind,world.region.player.pose.origin)
			if detail.visible:contacts.append({"at":Library.point(actor.pose.origin),"color":Color("ec8872") if role=="enemy" else MINT})
	for contact in contacts:
		var local: Vector3=inverse*(contact.at-pose.origin);var point=Vector2(local.x,local.z)*radius/1200
		if point.length()<radius-4:draw_circle(center+point,2.8,contact.color)
	text(center+Vector2(-89,radius-40),"RNG 1.2 km",AMBER,10)
	text(center+Vector2(-89,radius-24),"SCAN" if world.session.ship.passive_radar>0 else "NAV ONLY",DIM,10)
