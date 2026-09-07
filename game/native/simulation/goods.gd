extends "res://native/simulation/trade.gd"
## Cargo schema adapter with indexed inventory merges and copy-on-write crafting.
const Math = preload("res://native/simulation/fixed_math.gd")
var id := 0
var tech_level := 0
var origin_station := 0
var destination_station := 0
var availability := 0
var minimum_price := 0
var maximum_price := 0
var ingredients: Array = []
var ingredient_counts: Array = []
var missing_ingredients := 0

func configure(row: Array) -> void:
 id=int(row[0]); tech_level=int(row[1]); origin_station=int(row[2]); destination_station=int(row[3])
 availability=int(row[4]); minimum_price=int(row[5]); maximum_price=int(row[6])
 price=minimum_price+(maximum_price-minimum_price)/2
 if row.size() > 7:
  ingredients=row[7].map(func(value): return int(value))
  ingredient_counts=row[8].map(func(value): return int(value))

func total_price() -> int:
 return maxi(0,price)*maxi(0,owned)

func copy_stack(count: int, at_price: int = -1):
 var result = get_script().new()
 result.configure([id,tech_level,origin_station,destination_station,availability,minimum_price,maximum_price,ingredients,ingredient_counts])
 result.owned=count
 result.price=price if at_price < 0 else at_price
 return result

static func contains(items: Array, item_id: int, count: int = 1) -> bool:
 for item in items:
  if item.id == item_id and item.owned >= count: return true
 return false

static func merge(existing: Array,incoming: Array) -> Array:
 var indexed: Dictionary={};var result: Array=[]
 for item in existing+incoming:
  if not indexed.has(item.id):
   var stack=item.copy_stack(item.owned);indexed[item.id]=stack;result.append(stack)
  else:indexed[item.id].owned+=item.owned
 return result

static func owned_items(items: Array,take_stock: bool=false) -> Array:
 var result: Array=[]
 for item in items:
  var quantity: int=item.stock if take_stock else item.owned
  if quantity>0:result.append(item.copy_stack(quantity))
 return result

static func market_rows(cargo: Array,inventory: Array) -> Array:
 var result: Array=[];var indexed: Dictionary={}
 for source in cargo:
  var item=source.copy_stack(source.owned);indexed[item.id]=item;result.append(item)
 for source in inventory:
  if not indexed.has(source.id):
   var item=source.copy_stack(0);indexed[item.id]=item;result.append(item)
  indexed[source.id].stock+=source.owned;indexed[source.id].price=source.price
 return result

func manufacture(items: Array,count: int) -> Array:
 var requirements: Dictionary={}
 for index in ingredients.size():requirements[ingredients[index]]=int(requirements.get(ingredients[index],0))+ingredient_counts[index]*count
 var output: Array=[]
 for item in items:
  var needed:=int(requirements.get(item.id,0));var consumed:=mini(item.owned,needed)
  requirements[item.id]=needed-consumed;output.append(item.copy_stack(item.owned-consumed))
 if requirements.values().any(func(value):return value>0):return items
 return merge(output,[copy_stack(count)])
