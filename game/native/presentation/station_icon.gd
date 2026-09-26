extends Control
## Line icons for the station interface, drawn as vectors so they stay sharp
## at every interface scale and take the palette's colour (gold included).
## Shapes are laid out on a square from -1 to 1 around the control's centre.

var icon := "":
	set(value): icon=value; queue_redraw()
var color := Color("5fd4f0"):
	set(value): color=value; queue_redraw()

func _init(name_: String="", tint: Color=Color("5fd4f0"), extent: float=40.0) -> void:
	icon=name_; color=tint
	custom_minimum_size=Vector2(extent,extent)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	size_flags_vertical=Control.SIZE_SHRINK_CENTER

func _ready() -> void: resized.connect(queue_redraw)

var _r := 1.0
var _c := Vector2.ZERO
func _p(x: float, y: float) -> Vector2: return _c+Vector2(x,y)*_r
func _width() -> float: return maxf(1.5,_r*.11)

func _line(points: Array, closed := false) -> void:
	var line := PackedVector2Array()
	for point in points: line.append(_p(point.x,point.y))
	if closed and line.size()>1: line.append(line[0])
	# A faint wider pass under each stroke gives the lit-glass edge.
	draw_polyline(line,Color(color,.18),_width()*2.6,true)
	draw_polyline(line,color,_width(),true)

func _fill(points: Array, alpha := .22) -> void:
	var shape := PackedVector2Array()
	for point in points: shape.append(_p(point.x,point.y))
	draw_colored_polygon(shape,Color(color,alpha))

func _ring(center: Vector2, radius: float, from := 0.0, to := TAU, closed := true) -> Array:
	var points: Array=[]
	var steps := maxi(10,int(absf(to-from)/TAU*36))
	for i in steps+1:
		var angle := from+(to-from)*i/steps
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	if closed and is_equal_approx(absf(to-from),TAU): points.pop_back()
	return points

func _box(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [Vector2(x0,y0),Vector2(x1,y0),Vector2(x1,y1),Vector2(x0,y1)]

func _cube(center: Vector2, s: float) -> void:
	var top := [center+Vector2(0,-s),center+Vector2(s*.87,-s*.5),center,center+Vector2(-s*.87,-s*.5)]
	var outline := [center+Vector2(0,-s),center+Vector2(s*.87,-s*.5),center+Vector2(s*.87,s*.5),center+Vector2(0,s),center+Vector2(-s*.87,s*.5),center+Vector2(-s*.87,-s*.5)]
	_fill(top,.3)
	_line(outline,true)
	_line([center+Vector2(-s*.87,-s*.5),center,center+Vector2(s*.87,-s*.5)])
	_line([center,center+Vector2(0,s)])

func _gear(center: Vector2, outer: float, inner: float, teeth: int) -> void:
	var points: Array=[]
	for i in teeth*4:
		var angle := TAU*i/(teeth*4.0)-PI*.5
		var radius := outer if i%4 in [1,2] else inner
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	_fill(points,.18);_line(points,true)
	_line(_ring(center,inner*.42),true)

func _draw() -> void:
	_r=minf(size.x,size.y)*.5*.86;_c=size*.5
	match icon:
		"hangar":
			# A submarine seen from the side, bow to the right.
			var hull: Array=[]
			for i in 25:
				var angle := TAU*i/24.0
				hull.append(Vector2(cos(angle)*.82,sin(angle)*.3+.25))
			_fill(hull,.2);_line(hull,true)
			_line([Vector2(-.28,-.02),Vector2(-.2,-.42),Vector2(.18,-.42),Vector2(.26,-.02)])
			_line([Vector2(.02,-.42),Vector2(.02,-.62),Vector2(.2,-.62)])
			_line([Vector2(-.82,.25),Vector2(-.98,.02),Vector2(-.98,.48),Vector2(-.82,.25)])
			for x in [.1,.35]: _line(_ring(Vector2(x,.2),.07))
		"missions","journal":
			_fill(_box(-.58,-.82,.58,.82),.14)
			_line([Vector2(-.58,-.82),Vector2(.3,-.82),Vector2(.58,-.54),Vector2(.58,.82),Vector2(-.58,.82)],true)
			_line([Vector2(.3,-.82),Vector2(.3,-.54),Vector2(.58,-.54)])
			for y in [-.3,.02,.34]: _line([Vector2(-.3,y),Vector2(.3,y)])
			if icon=="journal": _line([Vector2(-.3,.58),Vector2(.05,.58)])
		"contracts":
			_fill(_box(-.58,-.82,.58,.82),.14)
			_line(_box(-.58,-.82,.58,.82),true)
			for y in [-.45,-.15]: _line([Vector2(-.3,y),Vector2(.3,y)])
			_line([Vector2(-.26,.36),Vector2(-.06,.56),Vector2(.32,.14)])
		"map":
			var head: Array=_ring(Vector2(0,-.28),.46,PI*.8,PI*2.2,false)
			head.append(Vector2(0,.6));_fill(head,.2);_line(head,true)
			_line(_ring(Vector2(0,-.28),.16))
			var base: Array=[]
			for i in 17: var a := PI*i/16.0; base.append(Vector2(cos(a)*.7,sin(a)*.18+.62))
			_line(base)
		"trade":
			_cube(Vector2(-.42,.36),.42);_cube(Vector2(.42,.36),.42);_cube(Vector2(0,-.36),.42)
		"cargo":
			_cube(Vector2(0,0),.82)
		"status":
			for bar in [[-.5,.15],[0,-.7],[.5,-.25]]:
				var x: float=bar[0];var top: float=bar[1]
				_fill(_box(x-.14,top,x+.14,.78),.45);_line(_box(x-.14,top,x+.14,.78),true)
		"system":
			_gear(Vector2.ZERO,.86,.62,8)
		"workshop":
			_gear(Vector2(-.22,.18),.62,.44,7)
			_gear(Vector2(.52,-.5),.36,.25,6)
		"depart":
			for x in [-.52,.08]: _line([Vector2(x,-.62),Vector2(x+.46,0),Vector2(x,.62)])
		"back":
			_line([Vector2(.28,-.66),Vector2(-.34,0),Vector2(.28,.66)])
		"next":
			_line([Vector2(-.28,-.66),Vector2(.34,0),Vector2(-.28,.66)])
		"cart":
			_line([Vector2(-.95,-.66),Vector2(-.66,-.66),Vector2(-.42,.3),Vector2(.62,.3),Vector2(.84,-.4),Vector2(-.56,-.4)])
			_fill([Vector2(-.56,-.4),Vector2(.84,-.4),Vector2(.62,.3),Vector2(-.42,.3)],.2)
			for x in [-.3,.5]: _line(_ring(Vector2(x,.6),.13))
		"wrench":
			_line([Vector2(-.66,.66),Vector2(.2,-.2)])
			var jaw: Array=_ring(Vector2(.42,-.42),.36,PI*1.25+.9,PI*1.25+TAU-.9,false)
			_line(jaw)
			_line([Vector2(-.66,.66),Vector2(-.5,.82)]);_line([Vector2(-.82,.5),Vector2(-.66,.66)])
		"person":
			_fill(_ring(Vector2(0,-.4),.34),.2);_line(_ring(Vector2(0,-.4),.34))
			var shoulders: Array=_ring(Vector2(0,.72),.66,PI,TAU,false)
			shoulders.append(Vector2(.66,.72));_line(shoulders)
		"medal":
			_fill([Vector2(-.46,-.86),Vector2(-.12,-.86),Vector2(.1,-.3),Vector2(-.22,-.2)],.4)
			_fill([Vector2(.46,-.86),Vector2(.12,-.86),Vector2(-.1,-.3),Vector2(.22,-.2)],.4)
			_line([Vector2(-.46,-.86),Vector2(-.12,-.86),Vector2(.1,-.3)]);_line([Vector2(.46,-.86),Vector2(.12,-.86),Vector2(-.1,-.3)])
			_fill(_ring(Vector2(0,.3),.5),.22);_line(_ring(Vector2(0,.3),.5))
			var star: Array=[]
			for i in 10:
				var a := -PI*.5+PI*i/5.0;var radius := .3 if i%2==0 else .13
				star.append(Vector2(cos(a),sin(a))*radius+Vector2(0,.3))
			_line(star,true)
		"shield":
			var outline: Array=[Vector2(0,-.86),Vector2(.7,-.6),Vector2(.66,.1),Vector2(0,.86),Vector2(-.66,.1),Vector2(-.7,-.6)]
			_fill(outline,.22);_line(outline,true)
			_line([Vector2(0,-.5),Vector2(0,.5)])
		"armor","grid":
			for cell in [Vector2(-.44,-.44),Vector2(.44,-.44),Vector2(-.44,.44),Vector2(.44,.44)]:
				var box: Array=_box(cell.x-.34,cell.y-.34,cell.x+.34,cell.y+.34)
				_fill(box,.3 if cell.x<0 or cell.y<0 else .1);_line(box,true)
		"hull":
			var outline: Array=[Vector2(0,-.86),Vector2(.74,-.44),Vector2(.74,.44),Vector2(0,.86),Vector2(-.74,.44),Vector2(-.74,-.44)]
			_fill(outline,.2);_line(outline,true)
			_line([Vector2(-.36,-.1),Vector2(0,.26),Vector2(.4,-.24)])
		"credits":
			for y in [.5,.12,-.26]:
				var disc: Array=_ring(Vector2(0,y),.66)
				for i in disc.size(): disc[i]=Vector2(disc[i].x,(disc[i].y-y)*.36+y)
				_fill(disc,.28);_line(disc,true)
				_line([Vector2(-.66,y),Vector2(-.66,y+.26)]);_line([Vector2(.66,y),Vector2(.66,y+.26)])
		"lock":
			_fill(_box(-.56,-.1,.56,.78),.3);_line(_box(-.56,-.1,.56,.78),true)
			_line(_ring(Vector2(0,-.1),.36,PI,TAU,false))
			_line([Vector2(0,.22),Vector2(0,.46)])
		"save":
			_line([Vector2(-.76,-.76),Vector2(.5,-.76),Vector2(.76,-.5),Vector2(.76,.76),Vector2(-.76,.76)],true)
			_fill(_box(-.44,-.76,.36,-.24),.3);_line(_box(-.44,.2,.44,.76),true)
		"controls":
			var pad: Array=[Vector2(-.9,-.16),Vector2(-.6,-.46),Vector2(.6,-.46),Vector2(.9,-.16),Vector2(.8,.42),Vector2(.46,.5),Vector2(.26,.2),Vector2(-.26,.2),Vector2(-.46,.5),Vector2(-.8,.42)]
			_fill(pad,.18);_line(pad,true)
			_line([Vector2(-.6,-.12),Vector2(-.3,-.12)]);_line([Vector2(-.45,-.27),Vector2(-.45,.03)])
			_line(_ring(Vector2(.36,-.2),.07));_line(_ring(Vector2(.56,-.02),.07))
		"audio":
			# A speaker cone with two sound arcs.
			var cone := [Vector2(-.82,-.26),Vector2(-.44,-.26),Vector2(-.02,-.66),Vector2(-.02,.66),Vector2(-.44,.26),Vector2(-.82,.26)]
			_fill(cone,.22);_line(cone,true)
			_line(_ring(Vector2(-.02,0),.42,-PI*.3,PI*.3,false))
			_line(_ring(Vector2(-.02,0),.78,-PI*.32,PI*.32,false))
		"graphics":
			_fill(_box(-.86,-.66,.86,.4),.16);_line(_box(-.86,-.66,.86,.4),true)
			_line([Vector2(-.3,.72),Vector2(.3,.72)]);_line([Vector2(0,.4),Vector2(0,.72)])
			_line([Vector2(-.6,.18),Vector2(-.2,-.24),Vector2(.1,.06),Vector2(.3,-.12),Vector2(.6,.18)])
		"world":
			_line(_ring(Vector2.ZERO,.82))
			var meridian: Array=_ring(Vector2.ZERO,.82)
			for i in meridian.size(): meridian[i]=Vector2(meridian[i].x*.4,meridian[i].y)
			_line(meridian,true)
			_line([Vector2(-.82,0),Vector2(.82,0)])
		"help":
			_line(_ring(Vector2.ZERO,.84))
			var hook: Array=_ring(Vector2(0,-.2),.28,PI*1.1,PI*2.4,false)
			hook.append(Vector2(0,.24));_line(hook)
			_line(_ring(Vector2(0,.52),.05))
		"transfer":
			_line([Vector2(-.8,-.3),Vector2(.7,-.3)]);_line([Vector2(.4,-.6),Vector2(.76,-.3),Vector2(.4,0)])
			_line([Vector2(.8,.36),Vector2(-.7,.36)]);_line([Vector2(-.4,.06),Vector2(-.76,.36),Vector2(-.4,.66)])
		"reload":
			_line(_ring(Vector2.ZERO,.7,-PI*.35,PI*1.45,false))
			var tip: Vector2=Vector2(cos(-PI*.35),sin(-PI*.35))*.7
			_line([tip+Vector2(-.36,-.06),tip,tip+Vector2(.04,.36)])
		"exit":
			_line([Vector2(.2,-.8),Vector2(-.7,-.8),Vector2(-.7,.8),Vector2(.2,.8)])
			_line([Vector2(-.2,0),Vector2(.86,0)]);_line([Vector2(.56,-.3),Vector2(.86,0),Vector2(.56,.3)])
		"resume":
			var play: Array=[Vector2(-.46,-.72),Vector2(.7,0),Vector2(-.46,.72)]
			_fill(play,.3);_line(play,true)
		"freeze":
			_line(_ring(Vector2.ZERO,.82))
			_fill(_box(-.36,-.4,-.1,.4),.5);_fill(_box(.1,-.4,.36,.4),.5)
		"profile":
			_fill(_box(-.86,-.62,.86,.62),.14);_line(_box(-.86,-.62,.86,.62),true)
			_line(_ring(Vector2(-.38,-.12),.2))
			_line(_ring(Vector2(-.38,.44),.34,PI,TAU,false))
			for y in [-.2,.1,.36]: _line([Vector2(.08,y),Vector2(.6,y)])
		"camera":
			_fill(_box(-.86,-.44,.44,.5),.16);_line(_box(-.86,-.44,.44,.5),true)
			_line([Vector2(.44,-.1),Vector2(.86,-.36),Vector2(.86,.4),Vector2(.44,.16)])
		"fullscreen":
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				_line([corner*Vector2(.8,.4),corner*.8,corner*Vector2(.4,.8)])
