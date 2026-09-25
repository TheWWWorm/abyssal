extends RefCounted
## Read-only equipment descriptions from the same parameters used by simulation.
static func stats(item) -> String:
	var p: Array = item.parameters
	match item.kind:
		0,1:
			var mode := "Homing torpedo" if item.id in [12,13,14] else ("Beam weapon" if item.id in [3,4,5] else "Projectile weapon")
			return "%s · Damage %d · Range %.0f m · Firing interval %.2f s"%[mode,p[0],float(p[2])*float(p[3])*0.01,float(p[1])/1000.0]
		2:
			return "Harpoon · Range %.0f m · Capture tolerance %d m · Slowing %d%%"%[float(p[2])*float(p[3])*0.01,int(p[0])*2,p[1]]
		3:
			var result := "Shield %d · Shallow limit %d"%[p[0],p[2]]
			if int(p[1])>0: result+=" · Recharge interval %.2f s"%(float(p[1])/1000.0)
			else: result+=" · Passive recharge: none"
			return result
		4: return "Armor %d · Deep limit %d"%[p[0],p[1]]
		5: return "Cargo capacity +%d%%"%p[0]
		6: return "Engine range +%d%%"%p[0]
		7: return "Steering +%d%%"%p[0]
		8: return "Radar level %d"%p[0]
		9: return "Boost %.1f× · Duration %.1f s · Recharge %.1f s"%[float(p[0])/2.0,float(p[1])/1000.0,float(p[2])/1000.0]
		10: return "Automatic hull repair"
	return ""
static func kind_name(item) -> String:
	"""What sort of system it is, as the shop's detail names it."""
	match item.kind:
		0,1: return stats(item).get_slice(" · ",0)
		2: return "Harpoon"
		3: return "Shield"
		4: return "Armor"
		5: return "Cargo module"
		6: return "Engine"
		7: return "Steering"
		8: return "Radar"
		9: return "Booster"
		10: return "Repair system"
	return ""
static func figures(item) -> Array:
	"""The stats line as [name, value] pairs for a table, without the kind."""
	var result: Array=[]
	for part in stats(item).split(" · "):
		if item.kind in [0,1,2] and part==kind_name(item): continue
		if part.contains(": "):
			result.append([part.get_slice(": ",0),part.get_slice(": ",1)]);continue
		var cut := -1
		for i in range(1,part.length()):
			if part[i-1]==" " and part[i] in "0123456789+-": cut=i;break
		result.append([part.substr(0,cut).strip_edges(),part.substr(cut)] if cut>0 else [part,""])
	return result
