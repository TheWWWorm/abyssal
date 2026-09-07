extends RefCounted
## Imported equipment schema; linear technology pricing and explicit resale.
const Math = preload("res://native/simulation/fixed_math.gd")
var id := 0
var kind := 0
var rarity := 0
var minimum_price := 0
var maximum_price := 0
var parameters: Array = [0,0,0,0]
var price := 0
var quantity := 0
var discounted := false

func configure(row: Array) -> void:
 id=int(row[0]); kind=int(row[1]); rarity=int(row[2])
 minimum_price=int(row[3]); maximum_price=int(row[4])
 for i in 4: parameters[i]=int(row[5+i])
 price=minimum_price+(maximum_price-minimum_price)/2

func is_weapon() -> bool:
 return kind in [0,1,2]

func total_price() -> int:
 return maxi(0,price)*maxi(0,quantity)

func station_price(tech_level: int, resale: bool = false) -> void:
 var quality:=clampf(tech_level/10.0,0,1)
 price=maxi(1,roundi(lerpf(maximum_price,minimum_price,quality)*(0.65 if resale else 1.0)))

func copy_stack(count: int = 1, at_price: int = -1):
 var result = get_script().new()
 result.configure([id,kind,rarity,minimum_price,maximum_price]+parameters)
 result.price=price if at_price < 0 else at_price
 result.quantity=count
 result.discounted=discounted
 return result
