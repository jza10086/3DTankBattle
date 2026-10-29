# Sources & credits

## Redistributed asset

**Quaternius — Animated Tanks Pack (June 2019), Tank2 desert variant**

- Pack-specific author page: https://quaternius.com/packs/animatedtanks.html
- Download folder linked by author: https://drive.google.com/drive/folders/1tHX0RF9l4Nw4EZwxH6xWta0HsICU2h-G
- Exact original Tank2 FBX: https://drive.google.com/file/d/1a57hqb1yEdLCbeQiQQjf2mobANJNc5dc/view
- Exact pack license: https://drive.google.com/file/d/1VuTMkuQymqZGmLIACWWMOI4lXLx0TCCY/view
- **License: CC0 1.0 Universal**, verified against the downloaded 2019 pack's `License.txt`, not assumed from mirrors or the author's general current license.
- Included file: `assets/quaternius/tank_desert.glb`; license and detailed conversion provenance reside beside it.
- Modified: Blender conversion, normalized axes/scale, separate turret/barrel pivots and muzzle, opaque material correction, independent runtime left/right track clip playback, recoil and small original ID/antenna additions. Source four track animations retained. Wheels remain part of the hull mesh.

No War Thunder, Battlefield, or other proprietary game assets are included.

## Studied examples — no copied source code

- [Godot VehicleBody3D documentation](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html): vehicle-physics limitations and custom CharacterBody3D/RigidBody3D alternatives informed the choice of a predictable kinematic training chassis.
- [tokyogeometry/nani-raycast-wheel](https://github.com/tokyogeometry/nani-raycast-wheel), MIT, Godot 4 raycast-wheel example: studied ground-contact and spring/damper concepts. This project implements its own four-contact visual ground-following model, not that example's rigid-body suspension.
- [AnderHominem/Code-for-animating-tank-tracks](https://github.com/AnderHominem/Code-for-animating-tank-tracks), MIT: studied articulated tread animation approaches. The shipped default instead uses the CC0 model's original skeletal tread animation split by side.

All procedural environment geometry, fallback tank geometry, HUD, gameplay code and synthesized WAV sound effects were authored for this project. No third-party example code was copied into the repository.
