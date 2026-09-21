extends RefCounted
## Imported equipment records: technology pricing and the resale cut, as the phone game deals them.
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
 # dn.a: a station of technology n sells at the floor plus (10-n)/10 of the
 # spread, and what is sold back, or bought back, is worth a fifth less;
 # both cuts apply to gear that has already been owned once.
 price=minimum_price+int(Math.f32(Math.f32(float(10-tech_level)/10.0)*float(maximum_price-minimum_price)))
 if discounted:price=int(Math.f32(float(price)/1.25))
 if resale:price=int(Math.f32(float(price)/1.25))

func copy_stack(count: int = 1, at_price: int = -1):
 var result = get_script().new()
 result.configure([id,kind,rarity,minimum_price,maximum_price]+parameters)
 result.price=price if at_price < 0 else at_price
 result.quantity=count
 result.discounted=discounted
 return result
