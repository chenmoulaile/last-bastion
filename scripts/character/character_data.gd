extends "res://scripts/data/character_data.gd"
## Path alias required by the narrative design spec:
##   res://scripts/character/CharacterData.gd
##
## The single source of truth stays at res://scripts/data/character_data.gd so
## the v1.0 roster, save data and every existing .tres keep loading unchanged.
## This alias exists so new content can `extends` the path named in the spec
## without forking the resource schema (and without a duplicate class_name).
##
## Usage in a new resource script:
##   extends "res://scripts/character/character_data.gd"
