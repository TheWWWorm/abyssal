extends RefCounted
## Margins that keep the interface clear of a phone's notch, camera cutout,
## status bar and rounded corners. The 3D view still fills the whole screen;
## only the interface is inset.
##
## Held landscape, a phone can be turned either way round, so both sides get
## the larger inset and the layout stays centred. Held upright, the top keeps
## clear of the notch and status bar and the bottom of the home indicator.

## Wider (or taller) than any tablet (4:3 to 16:10) and than 16:9 screens.
const PHONE_ASPECT := 1.85
## Share of the long side kept clear on a phone even when the platform reports
## no cutout, as browsers do without a safe-area inset.
const PHONE_SIDE := .055
const PHONE_TOP := .05
const PHONE_BOTTOM := .025

static func platform_insets() -> Dictionary:
	"""Cutout insets as fractions of the window: left, right, top, bottom."""
	var none := {"left":0.0,"right":0.0,"top":0.0,"bottom":0.0}
	if not OS.has_feature("mobile") and not OS.has_feature("web"): return none
	if OS.has_feature("web"):
		var measured: Variant = JavaScriptBridge.eval("""(function(){
			var probe=document.createElement('div');
			probe.style.cssText='position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
			document.body.appendChild(probe);
			var style=getComputedStyle(probe);
			var result=[style.paddingLeft,style.paddingRight,style.paddingTop,style.paddingBottom].map(function(v){return parseFloat(v)||0;});
			result.push(window.innerWidth||0,window.innerHeight||0);
			probe.remove();return result.join(',');})()""",true)
		var parts := str(measured).split(",")
		if parts.size()!=6 or float(parts[4])<=0 or float(parts[5])<=0: return none
		var width := float(parts[4]);var height := float(parts[5])
		return {"left":float(parts[0])/width,"right":float(parts[1])/width,"top":float(parts[2])/height,"bottom":float(parts[3])/height}
	var area := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if area.size.x<=0 or area.size.y<=0 or screen.x<=0 or screen.y<=0: return none
	return {"left":maxf(0,area.position.x)/screen.x,"right":maxf(0,screen.x-area.end.x)/screen.x,
		"top":maxf(0,area.position.y)/screen.y,"bottom":maxf(0,screen.y-area.end.y)/screen.y}

static func margins(ui_size: Vector2, window_size: Vector2i, touch: bool) -> Dictionary:
	"""Margins in interface units: `side` for both left and right, then `top`
	and `bottom`."""
	var result := {"side":0.0,"top":0.0,"bottom":0.0}
	if window_size.x<=0 or window_size.y<=0: return result
	var insets := platform_insets()
	var side: float=maxf(insets.left,insets.right)
	var top: float=insets.top;var bottom: float=insets.bottom
	if touch and float(window_size.x)/window_size.y>=PHONE_ASPECT: side=maxf(side,PHONE_SIDE)
	if touch and float(window_size.y)/window_size.x>=PHONE_ASPECT:
		top=maxf(top,PHONE_TOP);bottom=maxf(bottom,PHONE_BOTTOM)
	result.side=roundf(clampf(side,0,.15)*ui_size.x)
	result.top=roundf(clampf(top,0,.12)*ui_size.y)
	result.bottom=roundf(clampf(bottom,0,.08)*ui_size.y)
	return result
