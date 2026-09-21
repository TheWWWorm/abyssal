extends Control
## The phone game's opening, played once at the start of a new expedition
## (ad.a on the first level): sixty-nine seconds of the camera coming in on
## the station along ck's second path while the title cards go by, two sonar
## pings, then the game's own track from the ninth second to the end. The
## cards are the imported strings and the imported logo. It can be skipped.
signal finished
const Library = preload("res://scripts/model_library.gd")
## The original runs 69 s; the last leg to the hull is timed by its length,
## at the pace of the legs before it, so the sequence may run a little over.
var duration := 69.0
## Card start and end, in seconds, and the string of each (bd.a in ad.a);
## the third card is the logo (bd.a(true)) rather than a line.
const CARDS := [[4.0,9.0,622],[14.0,19.0,623],[24.0,29.0,-1],[34.0,39.0,624],[44.0,51.0,625],[56.0,61.0,626],[65.0,69.0,627]]
const PINGS := [3.5,7.0]
const MUSIC_AT := 8.75
## The shot, in metres from the station's centre, with the camera's pitch:
## ck's second path, which holds its first mark for five seconds, then comes
## in from fifteen hundred metres out looking down, levels off at two
## hundred, swings round the far side, stands off again and finally pulls
## away; the last mark is where the chase camera takes over.
const MARKS := [[5.0,Vector3(1500,50,0),-90.0],[20.0,Vector3(1200,50,0),-44.0],[30.0,Vector3(200,0,0),0.0],[40.0,Vector3(0,-30,-200),0.0],[55.0,Vector3(300,0,0),0.0],[65.0,Vector3(300,0,-500),0.0]]
## The last seconds bring the camera to the submarine at its berth, which
## may lie on the far side of the station from the path's last mark: the
## way there passes over the station, at the pace of the legs before, and
## the chase camera takes over only once the shot is beside the hull.
const LEG_SPEED := 90.0
var handover_from := 67.0
var marks: Array = []
var hull := Vector3.ZERO
var view
var dive_audio
var session
var active := false
var elapsed := 0.0
var focus := Vector3.ZERO
var caption := Label.new()
var logo := TextureRect.new()
var hint := Label.new()
var pings_played := 0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(caption);caption.add_theme_font_size_override("font_size",24);caption.add_theme_color_override("font_color",Color("d6e8ee"))
	caption.add_theme_color_override("font_shadow_color",Color.BLACK);caption.add_theme_constant_override("shadow_offset_y",2)
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(logo);logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;logo.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(hint);hint.text="Enter / click to skip";hint.add_theme_font_size_override("font_size",13);hint.modulate=Color("7fa5b3")
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(layout);layout();hide()

func layout() -> void:
	var unit := clampf(minf(size.x/1000.0,size.y/720.0),0.8,2.5)
	caption.size=Vector2(minf(620*unit,size.x-48),120*unit);caption.position=Vector2(28*unit,size.y-caption.size.y-40*unit)
	logo.size=Vector2(354,81)*unit;logo.position=Vector2((size.x-logo.size.x)*.5,36*unit)
	hint.size=Vector2(300,20);hint.position=Vector2(size.x-hint.size.x-24,size.y-38)

func begin(owner_view, owner_audio, owner_session, logo_texture: Texture2D) -> void:
	view=owner_view;dive_audio=owner_audio;session=owner_session
	logo.texture=logo_texture
	# The station's centre, from the modules as they stand in the water.
	var bounds := AABB();var first := true
	for station in view.station_nodes:
		var box: AABB=station.transform*station.solid_bounds()
		bounds=box if first else bounds.merge(box);first=false
	focus=bounds.get_center() if not first else Vector3.ZERO
	var top: float=(bounds.end.y-focus.y if not first else 80.0)+70.0
	hull=Library.point(view.world.region.player.pose.origin)
	marks=MARKS.duplicate(true)
	# The final approach: from the last mark to a point beside the hull, by
	# way of a mark above the station, so the leg clears every module.
	var outward: Vector3=hull-focus;outward.y=0
	if outward.length_squared()<1.0:outward=Vector3.RIGHT
	var from: Vector3=marks[-1][1]
	var turn: float=Vector3(from.x,0,from.z).signed_angle_to(outward,Vector3.UP)
	# Abeam of the hull, on the side the leg arrives from and a little
	# astern, so the step to the chase camera behind it crosses no hull.
	var abeam: Vector3=outward.cross(Vector3.UP).normalized()*(55.0 if turn>=0 else -55.0)
	var beside: Vector3=outward+abeam-outward.normalized()*20.0+Vector3.UP*18.0
	var midway: Vector3=from.lerp(beside,.5);midway.y=maxf(midway.y,top)
	var leg: float=maxf(5.0,(from.distance_to(midway)+midway.distance_to(beside))/LEG_SPEED)
	var start: float=float(marks[-1][0])
	marks.append([start+leg*.5,midway,0.0]);marks.append([start+leg,beside,0.0])
	duration=start+leg+.5;handover_from=duration-2.0
	elapsed=0.0;pings_played=0;active=true
	view.cinematic_override=true;view.cinematic_blend=0.0;view.cinematic_transform=shot(0.0)
	caption.text="";logo.hide();show()

func advance(delta: float) -> void:
	if not active:return
	elapsed+=delta
	while pings_played<PINGS.size() and elapsed>=PINGS[pings_played]:
		dive_audio.cue("sonar");pings_played+=1
	if elapsed>=MUSIC_AT:dive_audio.opening_music=true
	view.cinematic_transform=shot(elapsed)
	view.cinematic_blend=smoothstep(handover_from,duration,elapsed)
	var line := "";var show_logo := false;var strength := 0.0
	for card in CARDS:
		if elapsed<card[0] or elapsed>=card[1]:continue
		# Each card fades over its first and last third of a second.
		strength=minf(1.0,minf(elapsed-card[0],card[1]-elapsed)/.35)
		if int(card[2])<0:show_logo=true
		else:line=session.text(int(card[2]))
	caption.text=line;caption.modulate=Color(1,1,1,strength)
	logo.visible=show_logo;logo.modulate=Color(1,1,1,strength)
	if elapsed>=duration:finish()

func shot(at: float) -> Transform3D:
	"""The camera at a moment of the path: a smooth curve through the marks
	(h.a interpolates them cubically), looking at the station and pitched by
	the mark's own angle."""
	var last: int=marks.size()-1
	var segment := 0
	while segment<last-1 and at>=float(marks[segment+1][0]):segment+=1
	var t0: float=marks[segment][0];var t1: float=marks[segment+1][0]
	var weight := clampf((at-t0)/(t1-t0),0.0,1.0)
	var p0: Vector3=marks[maxi(0,segment-1)][1];var p1: Vector3=marks[segment][1];var p2: Vector3=marks[segment+1][1];var p3: Vector3=marks[mini(last,segment+2)][1]
	var position: Vector3=focus+p1.cubic_interpolate(p2,p0,p3,weight)
	var pitch: float=lerpf(float(marks[segment][2]),float(marks[segment+1][2]),smoothstep(0.0,1.0,weight))
	# The shot watches the station until its last leg, then the submarine.
	var subject: Vector3=focus.lerp(hull,smoothstep(float(MARKS[-1][0]),handover_from,at))
	var forward: Vector3=(subject-position)
	forward.y=0
	if forward.length_squared()<1e-4:forward=Vector3.FORWARD
	forward=forward.normalized()
	var right: Vector3=forward.cross(Vector3.UP).normalized()
	var aimed: Vector3=forward.rotated(right,deg_to_rad(pitch))
	# Past the original's last mark the shot looks down on the station it
	# crosses and then at the hull, instead of holding the horizon.
	if at>float(MARKS[-1][0]) and subject.distance_squared_to(position)>1.0:aimed=(subject-position).normalized()
	# Straight down has no horizon to keep level: hold the level frame's right.
	return Transform3D(Basis.looking_at(aimed,Vector3.UP if absf(aimed.y)<.999 else right.cross(aimed)),position)

func skip() -> void:
	if active:finish()

func finish(announce: bool=true) -> void:
	"""Ends the shot. Without the announcement nothing follows it: that is
	the page being closed from outside, not the sequence reaching its end."""
	if not active:return
	active=false
	if view!=null:view.cinematic_override=false;view.cinematic_blend=0.0
	if dive_audio!=null:dive_audio.opening_music=false
	hide()
	if announce:finished.emit()
