extends Resource
## Authored vehicle dimensions, mobility, weapon pair and presentation assets.
@export var display_name: String
@export var description: String
@export var model: PackedScene
@export_file("*.json") var track_path: String
@export var silhouette: Texture2D
@export var weapons: Array[int] = [0, 1]
@export var max_speed: float = 14.5
@export var reverse_speed: float = 5.5
@export var acceleration: float = 4.2
@export var traverse_rate: float = 0.68
@export var damage_multiplier: float = 1.0
@export var hull_size: Vector3 = Vector3(2.4, 0.8, 5.5)
@export var hull_center: Vector3 = Vector3(0, 0.15, 0)
@export var track_length: float = 4.9
@export var track_width: float = 1.03
@export var turret_size: Vector3 = Vector3(2.15, 0.65, 2.65)
@export var turret_center: Vector3 = Vector3(0, 0.3, 0.25)
@export var barrel_length: float = 2.9
@export var barrel_width: float = 0.18
