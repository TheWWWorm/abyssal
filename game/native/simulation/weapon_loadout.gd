extends RefCounted
## Imported weapon categories with symmetric engine-owned mount spacing.
const Weapon = preload("res://native/simulation/weapon.gd")
const Math = preload("res://native/simulation/fixed_math.gd")
var groups: Array = []
var selected := -1

static func create(item, data: Dictionary):
	var weapon := Weapon.new()
	var p: Array = item.parameters
	match item.id:
		15,16,17:
			weapon.configure(0,1,p[2],p[2],p[3],[0,0,0])
			weapon.fishing=true; weapon.fishing_radius=p[0]*200; weapon.slow_percent=p[1]
		3,4,5:
			weapon.configure(p[0],1,p[2],p[1],p[3],[0,0,2200]); weapon.beam=true
		12,13,14:
			weapon.configure(p[0],1,p[2],p[1],p[3],[0,0,0]); weapon.model_id=16; weapon.homing=true
		_:
			weapon.configure(p[0],10,p[2],p[1],p[3],[0,0,200])
			weapon.model_id=6766 if item.id == 42 else int(data.constants.ah["a:[S"][item.id])
	weapon.equipment_kind=item.kind; weapon.equipment_id=item.id
	return weapon

func configure(ship, data: Dictionary) -> void:
	groups=[]; selected=-1
	var combat: Array = []
	var harpoon = null
	for item in ship.equipment:
		if item == null or not item.is_weapon(): continue
		var weapon = create(item,data)
		if item.kind == 2: harpoon=weapon
		else: combat.push_front(weapon)
	if not combat.is_empty():
		for i in combat.size():
			combat[i].mount=Math.added(combat[i].mount,[roundi((i-(combat.size()-1)*.5)*700),0,0])
		groups.append(combat)
	if harpoon != null: groups.append([harpoon])
	if not groups.is_empty(): selected=0

func all_weapons() -> Array:
	var result: Array = []
	for group in groups: result.append_array(group)
	return result

func cycle() -> void:
	if not groups.is_empty(): selected=(selected+1)%groups.size()

func fire(pose, delta_ms: int, aim = null) -> void:
	if selected < 0: return
	for weapon in groups[selected]: weapon.request_fire(pose,delta_ms,aim)

func fire_kind(pose, delta_ms: int, fishing: bool, aim = null) -> void:
	for group in groups:
		if not group.is_empty() and group[0].fishing==fishing:
			for weapon in group: weapon.request_fire(pose,delta_ms,aim)
