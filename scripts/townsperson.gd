extends "res://scripts/villager.gd"
## One of Maple Grove's townsfolk (scripts/townsfolk.gd, data/townsfolk.json): a villager body that
## wanders, sits and reads like the cast, but lists its own menu (main._actions_for asks ke_actions
## first): a word, and a sweater when they want one. Never in main.villagers.

var town: Node # townsfolk.gd
var tags: Array = [] # who they are, for the lines they may say: adult, man, kid, young, old...
var state := "away" # away, walking, idle, to_bench, bench, cafe, leaving
var until := 0.0 # the game hour (townsfolk.now_h) this state ends by
var goal := Vector3.ZERO # where they're walking to
var bench: Node = null # the bench they're on or heading for
var bench_end := 0.0
var talks := 0


func ke_actions() -> Array:
	return town.actions(self)


func ke_action(id: String) -> void:
	town.action(self, id)
