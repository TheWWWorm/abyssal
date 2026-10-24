extends RefCounted
## Source-aligned markings and smooth structural profiles, in original texels.
const SCALE := 8
const SHADES := {
	"boundary":[41,75,38,76,29,79,69,47,20,20,46],"upper":[61,95,58,118,53,98,117,64,19,23,41],
	"joint":[14,48,16,60,24,74,23,12,0,21,65],"shoulder":[36,72,36,85,26,85,29,14,2,23,70],
	"collar":[104,147,134,173,126,130,80,66,10,14,54],"lower":[52,95,55,104,67,83,76,46,19,14,43],
	"tail":[38,84,46,92,53,72,62,30,16,16,39]}
const SECTIONS := [[0,16,[[0,"boundary"],[2,"upper"],[16,"upper"]]],[16,18,[[16,"joint"],[18,"joint"]]],
	[18,19,[[18,"shoulder"],[19,"shoulder"]]],[19,20,[[19,"collar"],[20,"collar"]]],
	[20,32,[[20,"lower"],[24,"lower"],[30,"tail"],[32,"boundary"]]]]
const LANES := [[64,65,0,0],[65,66,1,1],[66,67,2,2],[67,68,3,3],[68,69,4,4],[69,71,5,6],[71,72,7,7],[72,74,8,9],[74,75,10,10]]

static func smooth_ramp(t: float) -> float:
	t=clampf(t,0,1);return t*t*(3-2*t)

static func fill(out: Image, rect: Rect2i, value: float) -> void:
	out.fill_rect(Rect2i(rect.position*SCALE,rect.size*SCALE),Color(value,value,value,1))

static func shade(y: float, anchors: Array, column: int) -> float:
	for i in anchors.size()-1:
		var a: Array=anchors[i];var b: Array=anchors[i+1]
		if y>=a[0] and y<=b[0]:return lerpf(SHADES[a[1]][column],SHADES[b[1]][column],smooth_ramp((y-a[0])/(b[0]-a[0])))
	return SHADES[anchors[-1][1]][column]

static func apply(out: Image, source: Image, renderer) -> void:
	out.fill_rect(Rect2i(114*SCALE,2*SCALE,12*SCALE,12*SCALE),Color8(22,43,54))
	var logo := source.get_region(Rect2i(115,3,10,10));logo.resize(10*SCALE,10*SCALE,Image.INTERPOLATE_NEAREST);logo.convert(out.get_format())
	out.blit_rect(logo,Rect2i(0,0,10*SCALE,10*SCALE),Vector2i(115*SCALE,3*SCALE))
	var frames := [[48,97,14,14,73],[49,98,12,12,172],[50,99,10,10,36],[51,100,8,8,0],
		[48,113,14,13,73],[49,114,12,11,172],[50,115,10,9,0]]
	for x in [50,52,54,56,58]:frames.append([x,115,1,9,48])
	frames.append([54,115,1,1,53])
	for frame in frames:fill(out,Rect2i(frame[0],frame[1],frame[2],frame[3]),frame[4]/255.0)
	for rect in [Rect2i(51,98,3,1),Rect2i(56,109,3,1),Rect2i(51,114,3,1),Rect2i(56,124,3,1)]:
		for x in rect.size.x*SCALE:
			var t: float= (x+.5)/(rect.size.x*SCALE);var reflection := smooth_ramp(1-absf(t*2-1))
			var gray := Color(172/255.0,172/255.0,172/255.0).srgb_to_linear().lerp(Color(244/255.0,244/255.0,244/255.0).srgb_to_linear(),reflection).linear_to_srgb()
			out.fill_rect(Rect2i(rect.position.x*SCALE+x,rect.position.y*SCALE,1,rect.size.y*SCALE),gray)
	for repeat in [64,96]:
		for section in SECTIONS:
			for y in range(section[0]*SCALE,section[1]*SCALE):
				for lane in LANES:
					var a := shade((y+.5)/SCALE,section[2],lane[2]);var b := shade((y+.5)/SCALE,section[2],lane[3])
					for x in range(lane[0]*SCALE,lane[1]*SCALE):
						var t: float= 0.0 if lane[2]==lane[3] else smooth_ramp(((x+.5)/SCALE-lane[0]-.5)/(lane[1]-lane[0]-1))
						var value := lerpf(a,b,t)/255;out.set_pixel(x,repeat*SCALE+y,Color(value,value,value,1))
				await renderer.checkpoint()
	for y in 32*SCALE:
		var sy := 96+(y+.5)/SCALE-.5;var lo := clampi(floori(sy),0,127);var hi := mini(lo+1,127)
		for x in 4*SCALE:
			var sx := 32+x/SCALE;out.set_pixel(32*SCALE+x,96*SCALE+y,source.get_pixel(sx,lo).lerp(source.get_pixel(sx,hi),sy-floorf(sy)))
		await renderer.checkpoint()
