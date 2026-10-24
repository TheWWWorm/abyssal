extends RefCounted
## Analytic shallow bevels. Glass, painted markings and pigment stay flat.
const SCALE := 8

static func forms() -> Array:
	var result := []
	for rect in [Rect2(48,97,14,14),Rect2(48,113,14,13)]:result.append(["rim",rect,.02,.25,2.0])
	for x in [50,52,54,56,58]:result.append(["rail",Rect2(x,115,1,9),.012,.2])
	for rect in [Rect2(65,64,1,64),Rect2(67,64,1,64),Rect2(69,64,2,64),Rect2(32,96,2,32)]:result.append(["rail",rect,.01,.2])
	for rect in [Rect2(21,108,1098,23),Rect2(21,259,627,23),Rect2(899,259,220,23),Rect2(21,495,1098,23),Rect2(21,667,1098,23),Rect2(1119,0,21,1378)]:result.append(["patch",station(rect),.03,.25])
	for rect in [Rect2(43,689,451,234),Rect2(599,689,502,234)]:result.append(["patch",station(rect),-.045,.45])
	return result

static func station(rect: Rect2) -> Rect2:
	return Rect2(Vector2(75,64)+rect.position*Vector2(53.0/1141,64.0/1378),rect.size*Vector2(53.0/1141,64.0/1378))

static func generate(renderer) -> Image:
	var result := Image.create(128*SCALE,128*SCALE,false,Image.FORMAT_RGBA8);result.fill(Color8(128,128,255))
	for form in forms():
		var rect: Rect2=form[1];var bevel: float=form[3];var height: float=form[2]
		for y in range(floori(rect.position.y*SCALE),ceili(rect.end.y*SCALE)):
			if renderer.cancelled:return result
			for x in range(floori(rect.position.x*SCALE),ceili(rect.end.x*SCALE)):
				var sum := Vector3.ZERO;var old := result.get_pixel(x,y)
				for sy in 4:
					for sx in 4:
						var px := (x+(sx+.5)/4)/SCALE;var py := (y+(sy+.5)/4)/SCALE
						var edges := [px-rect.position.x,rect.end.x-px,py-rect.position.y,rect.end.y-py]
						var distance: float=edges[0];var edge := 0
						for i in (2 if form[0]=="rail" else 4):
							if edges[i]<distance:edge=i;distance=edges[i]
						if edges.min()<0 or (form[0]=="rim" and distance>=form[4]):sum+=Vector3(old.r,old.g,old.b);continue
						var slope := height/bevel if distance<bevel else 0.0
						if form[0]=="rim" and distance>form[4]-bevel:slope=-height/bevel
						var dx := slope if edge==0 else -slope if edge==1 else 0.0
						var dy := slope if edge==2 else -slope if edge==3 else 0.0
						sum+=Vector3(-dx,dy,1).normalized()*.5+Vector3.ONE*.5
				sum/=16;result.set_pixel(x,y,Color(sum.x,sum.y,sum.z,1))
			await renderer.checkpoint()
		renderer.completed+=1
	return result
