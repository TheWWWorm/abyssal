extends RefCounted
## One-unit market transaction, validated before either inventory is changed.
var price := 0
var owned := 0
var stock := 0

func transact(buy: bool, credits: int, cargo_used: int, capacity: int) -> int:
	if price<=0:return 0
	if buy and stock>0 and credits>=price and cargo_used<capacity:
		stock-=1
		owned+=1
		return -price
	if not buy and owned>0:
		owned-=1
		stock+=1
		return price
	return 0
