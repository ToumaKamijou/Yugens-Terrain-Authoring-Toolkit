@tool
extends Resource
class_name MarchingSquaresTexturePreset


@export var preset_name : String = "New Preset"

@export var new_tex_names : MarchingSquaresTextureNames = MarchingSquaresTextureNames.new()

@export var new_textures : MarchingSquaresTextureList = MarchingSquaresTextureList.new()

@export var quick_paints : Array[MarchingSquaresQuickPaint] = []

@export_group("Texture Library")
@export var texture_library : Resource
@export var baked_albedo_array_path : String = ""
@export var baked_normal_array_path : String = ""
@export var baked_grass_array_path : String = ""
@export var baked_dense_slot_lookup: PackedInt32Array = PackedInt32Array()

# In the future could include terrain/chunk settings
@export_group("Global Settings")
@export var apply_vertex_painter_settings : bool = true
@export var apply_grass_settings : bool = true

@export_group("Texture Settings")
@export var visible_texture_slot_count : int = 6
@export var slot_color_indices : Array = [[], [], [], [], [], [], [], [], [], [], [], [], [], [], []]

@export var slot_blend_modes : Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# Palette weights (per palette index 0-127). Used to control distribution of each palette color.
# Values are normalized per-slot in the shader (so they behave like percentages).
@export var palette_weights : Array[float] = []

# Per texture-slot scale values (0..255). This complements the legacy first-15 texture_scales array.
@export var slot_texture_scales : Array[float] = []

# Wetness controls (per texture slot)
# slot_wet_enabled[slot] toggles wetness effects on/off for that slot.
# slot_wet_modes[slot]: 0 = Wet (darken only), 1 = Glossy puddles (noise-masked).
@export var slot_wet_enabled : Array[bool] = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
@export var slot_wet_modes : Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# Terrain wetness target roughness per texture slot (0 = shiny/wet, 1 = matte/dry)
@export var slot_roughnesses : Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var slot_grass_wetnesses : Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Shared global-noise controls per texture slot.
@export var slot_floor_noise_enabled : Array = []
@export var slot_floor_noise_strengths : Array = []
@export var slot_floor_noise_scales : Array = []
@export var slot_wall_noise_enabled : Array = []
@export var slot_wall_noise_strengths : Array = []
@export var slot_wall_noise_scales : Array = []


func has_baked_arrays() -> bool:
	return (
		not baked_albedo_array_path.is_empty()
		and not baked_normal_array_path.is_empty()
		and ResourceLoader.exists(baked_albedo_array_path)
		and ResourceLoader.exists(baked_normal_array_path)
	)
