extends RefCounted
## Defensive layers consume damage in order, with bounded nonnegative values.
var hull := 0
var shield := 0
var armor := 0
var max_hull := 0
var max_shield := 0
var max_armor := 0
var enabled := true
var vulnerable := true
var special_kill := false

func configure(h: int, s: int, a: int) -> void:
	hull=h; max_hull=h; shield=s; max_shield=s; armor=a; max_armor=a

func set_hull(value: int) -> void:
	# Explicit hull upgrades raise the regeneration ceiling.
	hull=maxi(0,value); max_hull=maxi(max_hull,hull)

func damage(amount: int,kind: String="combined",mark_special: bool=false) -> void:
	if amount<=0 or not enabled or not vulnerable:return
	var layers: Array=["shield","armor","hull"] if kind=="combined" else [kind,"hull"] if kind in ["shield","armor"] else ["hull"]
	var pending:=amount
	for layer in layers:
		var absorbed:=mini(maxi(0,int(get(layer))),pending)
		set(layer,maxi(0,int(get(layer))-absorbed));pending-=absorbed
		if pending==0:break
	if hull==0 and mark_special:special_kill=true

func regenerate(layer: String) -> void:
	if layer=="shield": shield=mini(shield+1,max_shield)
	elif layer=="hull": hull=mini(hull+1,max_hull)

func values() -> Array:
	return [hull,shield,armor,special_kill]
