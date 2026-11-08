extends RefCounted
## Everything Maplewood's villagers say now lives in res://data/dialogue.json. Edit it freely:
## {sweater} becomes Rosa's sweater price today, {cottage} the cottage price, {rent} the daily rent.
## lines[id] has three tiers: 0-1 hearts, 2-3 hearts, 4-5 hearts.

const Data = preload("res://scripts/data.gd")

static var INTRO: Dictionary = Data.dialogue().get("intro", {})
static var LINES: Dictionary = Data.dialogue().get("lines", {})
static var GIFT_LOVED: Dictionary = Data.dialogue().get("gift_loved", {})
static var NEW_SHEEP: Array = Data.dialogue().get("new_sheep_names", ["Clover"])
