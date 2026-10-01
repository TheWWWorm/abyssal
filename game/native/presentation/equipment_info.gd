extends RefCounted
## Read-only equipment descriptions from the same parameters used by simulation.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
static func stats(item) -> String:
	var p: Array = item.parameters
	match item.kind:
		0,1:
			var mode := EngineLanguage.translate("Homing torpedo") if item.id in [12,13,14] else (EngineLanguage.translate("Beam weapon") if item.id in [3,4,5] else EngineLanguage.translate("Projectile weapon"))
			return mode+" · "+EngineLanguage.translate("Damage %d")%p[0]+" · "+EngineLanguage.translate("Range %.0f m")%(float(p[2])*float(p[3])*0.01)+" · "+EngineLanguage.translate("Firing interval %.2f s")%(float(p[1])/1000.0)
		2:
			return EngineLanguage.translate("Harpoon")+" · "+EngineLanguage.translate("Range %.0f m")%(float(p[2])*float(p[3])*0.01)+" · "+EngineLanguage.translate("Capture tolerance %d m")%(int(p[0])*2)+" · "+EngineLanguage.translate("Slowing %d%%")%p[1]
		3:
			var result: String=EngineLanguage.translate("Shield %d")%p[0]+" · "+EngineLanguage.translate("Shallow limit %d")%p[2]
			if int(p[1])>0: result+=" · "+EngineLanguage.translate("Recharge interval %.2f s")%(float(p[1])/1000.0)
			else: result+=" · "+EngineLanguage.translate("Passive recharge: none")
			return result
		4: return EngineLanguage.translate("Armor %d")%p[0]+" · "+EngineLanguage.translate("Deep limit %d")%p[1]
		5: return EngineLanguage.translate("Cargo capacity +%d%%")%p[0]
		6: return EngineLanguage.translate("Engine range +%d%%")%p[0]
		7: return EngineLanguage.translate("Steering +%d%%")%p[0]
		8: return EngineLanguage.translate("Radar level %d")%p[0]
		9: return EngineLanguage.translate("Boost %.1f×")%(float(p[0])/2.0)+" · "+EngineLanguage.translate("Duration %.1f s")%(float(p[1])/1000.0)+" · "+EngineLanguage.translate("Recharge %.1f s")%(float(p[2])/1000.0)
		10: return EngineLanguage.translate("Automatic hull repair")
	return ""
static func kind_name(item) -> String:
	"""What sort of system it is, as the shop's detail names it."""
	match item.kind:
		0,1: return stats(item).get_slice(" · ",0)
		2: return EngineLanguage.translate("Harpoon")
		3: return EngineLanguage.translate("Shield")
		4: return EngineLanguage.translate("Armor")
		5: return EngineLanguage.translate("Cargo module")
		6: return EngineLanguage.translate("Engine")
		7: return EngineLanguage.translate("Steering")
		8: return EngineLanguage.translate("Radar")
		9: return EngineLanguage.translate("Booster")
		10: return EngineLanguage.translate("Repair system")
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
