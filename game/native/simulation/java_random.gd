extends "res://native/simulation/linear_congruential.gd"
## The simulation's random stream. The phone game draws everything from one
## java.util.Random: market stock, contract offers, creature placement, ship
## salvage, the AI's whims. Drawing the same sequence here is what makes
## those come out as the original would deal them, so this is that generator
## (linear_congruential.gd), seeded and stepped the same way.
