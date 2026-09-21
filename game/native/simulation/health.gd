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
	# The phone game's cm: a hit spends shield, then armour, then hull, and
	# the pressure damage of a dive out of its band is taken by one layer on
	# its own, going to the hull only once that layer is gone. A wound named
	# for the hull ignores every protection and the enabled flags alike.
	if kind=="hull":hull=maxi(0,hull-amount);return
	if not enabled or not vulnerable:return
	if kind in ["shield","armor"]:
		var layer: int=shield if kind=="shield" else armor
		if layer<=0:hull=maxi(0,hull-amount)
		elif kind=="shield":shield=maxi(0,shield-amount)
		else:armor=maxi(0,armor-amount)
		return
	var carried: int=amount-shield
	if carried<=0:shield-=amount;return
	shield=0
	carried-=armor
	if carried<=0:armor=-carried;return
	armor=0;hull-=carried
	if hull<0:
		hull=0
		# Only a blow that would have gone past the last of the hull carries
		# the mark of the special weapon that struck it.
		if mark_special:special_kill=true

func regenerate(layer: String) -> void:
	if layer=="shield": shield=mini(shield+1,max_shield)
	elif layer=="hull": hull=mini(hull+1,max_hull)

func values() -> Array:
	return [hull,shield,armor,special_kill]
