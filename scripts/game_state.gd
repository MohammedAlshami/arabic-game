extends Node

enum Mode { MENU, EDIT, PLAY, STRUCTURE }

var current_mode := Mode.MENU
var map_to_load := ""
var structure_to_edit := ""
