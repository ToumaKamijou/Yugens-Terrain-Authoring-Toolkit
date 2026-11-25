# Code Locations

This small guide explains where you can find the code for several (smaller) features inside the plugin.

### Grass and Texture Mixing

* **MarchingSquaresTerrainVertexColorHelper** (The whole script)
* **MarchingSquaresChunk** script → `add_point(x: float, y: float, z: float, uv_x: float = 0, uv_y: float = 0, diag_midpoint: bool = false)` function.
* **mst_terrain** gdshader → fragment function.

Here you can change the logic for how the color_0 and color_1 variables are calculated to change how the grass appears and floor textures get mixed.

Although the variables are called _color_, the shader logic uses a byte sized integer Array.

### Wind Animations

* **mst_global_wind** gdshader → all functions and variables.

Feel free to change these animations to what looks best for your project! The animation system that is included right now serves as a base for people to build upon.

### Cell Normal Calculations

* **MarchingSquaresTerrainPlugin** script → `get_cell_normal(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Vector3:` function.
  
### Chunk UI Lines

* **MarchingSquaresTerrainGizmo** script → `try_add_chunk(terrain_system: MarchingSquaresTerrain, coords: Vector2i):` function.
* **MarchingSquaresTerrainGizmo** script → `add_chunk_lines(terrain_system: MarchingSquaresTerrain, coords: Vector2i, material: Material):` function.

### Terrain Mapping

* **mst_terrain** gdshaderinc → fragment function.

### Ridge & Ledge Texture Calculations

* **mst_terrain** gdshaderinc → end of the fragment function.
* **MarchingSquaresTerrainVertexColorHelper** script → at the start of the `blend_colors(vertex: Vector3, uv: Vector2, diag_midpoint: bool = false) -> Dictionary[String, Color]:` function
