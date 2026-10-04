# Plugin Quick Guide

### What is Yūgen's Terrain Authoring Toolkit?
Yūgen's Terrain Authoring Toolkit is a terrain plugin developed by [Yūgen](https://www.youtube.com/@yugen_seishin) as an alternative to using 3D modelling software like blender to create custom terrain shapes. Instead of having to switch between softwares every time you want to make a change, you can now do it all inside the Godot Engine itself! This plugin's main functionality is facilitated by the marching squares (not cubes) algorithm. While this plugin was created originally with isometric perspective and 3D Pixel Art games in mind, it can be used for a plethora of genres.

Below you will find a brief explanation of all the tools included in the plugin. A more in depth explanation of how all the tools function internally can be found in the _documentation+_ folder. Other plugin explanations and where to find certain code can also be found in the same folder.

For community showcases, feature requests and bug reporting, please refer to the [discord](https://discord.gg/ZSeYkTCgft).

## Tool Overview

### Brush Tool
The most basic of brushes that can simply elevate or lower terrain.

> _The following can be used on all brush related tools..._

Shortcuts:
* Shift+LMB+Drag: Add cells to the current draw selection.

* Ctrl+LMB+Drag: Remove cells from the current draw selection (in the Level tool Ctrl+LMB sets the level height instead).

* Shift+MWU/MWD: Increase or decrease the brush size.

* Alt/RMB/Esc: Reset the current draw selection.

### Level Tool
A handy brush that levels the terrain to a certain height.

Shortcuts:
* Ctrl+LMB: Set the terrain level height to the hovered cell's Y value.

### Smooth Tool
A powerful brush that smooths neighbouring terrain cells to a collective average height.

### Bridge Tool
An intuitive brush for creating bridges between two points.

Info:
* The bridge curve falloff can be set via the "ease value" attribute. For reference see the below ease value cheatsheet (see also the _documentation+_ folder).

* Enabling Curve3D Mode changes the bridge calculations to be point based, allowing for free form bridges.

![Godot Ease Value Cheatsheet](documentation+\ease_cheatsheet.png "Ease Cheatsheet")

### Grass Mask Tool
A brush that controls where grass gets placed. Fully grassless chunks can be enabled in the `Chunk Manager` tool.

### Vertex Paint Tool
A vertex-based painting brush that allows for up to 256 custom textures to be edited and applied onto the terrain.

Info:
* A Texture Preset is a resource that stores and loads a group of vertex painter settings and textures. Use these for editing and saving different environments or quickly testing custom palettes.

* Quick Paints are a quick way to set textures on the fly while moddeling the terrain. They can be either terrain-wide or preset specific. The quick paint resource files should be stored inside their dedicated folder in the MST parent folder.

### Debug Brush Tool
Prints data about selected cells.
Debug info:
* global_pos
* vertex_color_idx (0-255)
* normal...

### Chunk Management Tool
Manages the creation, deletion and changing of individual and global chunk settings.

Info:
* Inside the Chunk Tab settings such as the chunk_dimensions and cell_size can be changed. Additionally, this is where prefabs can be applied.

* Terrain specific NavMesh groups can be applied via this tool as well!

Chunk cell merge modes can be used to alter the merge thresholds of neighbouring vertices. These have the biggest impact on the overall _feel_ of the terrain.
* Cubic: The most blocky of all the modes. Has minimal smoothing between cells;

* Polyhedron: Blocky terrain with slight cell smoothing;

* Rounded Polyhedron: A 50/50 mix between having smooth and blocky terrain;

* Semi Round: Mostly smooth terrain with occasional blocky cells;

* Spherical: All the terrain will become smooth. This mode looks the most unnatural for the marching squares algorithm.

Shortcuts:
* CTRL+LMB: Change the currently selected chunk to the hovered chunk.

### Terrain Settings Tool
Allows the user to tweak existing and add custom global terrain settings.

Info:
* The Vertex Painter Tab is mainly used for changing texture blending related settings.

* The Environment Tab and Wind Tab can be used to alter terrain generation and the feel of vegetation.

* Finally, the Post-Processing Tab allows for custom shaders to be applied to the terrain and/or built-in vegetation systems.

## License (MIT)
Feel free to use, improve and change this plugin according to your needs, but include a copyright mention to the original project and author.
