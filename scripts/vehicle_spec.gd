extends Resource
## Authored vehicle scene, mobility, weapon pair and selection presentation.
@export var name_key: StringName
@export var description_key: StringName
@export var scene: PackedScene
@export var silhouette: Texture2D
@export var weapons: Array[int] = [0, 1]
@export var max_speed: float = 14.5
@export var reverse_speed: float = 5.5
@export var acceleration: float = 4.2
@export var traverse_rate: float = 0.68
@export var damage_multiplier: float = 1.0
