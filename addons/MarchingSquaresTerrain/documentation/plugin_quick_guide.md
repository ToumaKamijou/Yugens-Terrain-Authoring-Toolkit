# Plugin Quick Guide

### What is Yūgen's Terrain Authoring Toolkit?
Yūgen's Terrain Authoring Toolkit is a terrain plugin developed by [Yūgen](https://www.youtube.com/@yugen_seishin) as an alternative to using 3d modelling software like blender to create custom terrain shapes. Instead of having to switch between softwares every time you want to make a change, you can now do it all inside the godot engine itself! This plugin's main functionality is facilitated by the marching squares (not cubes) algorithm. While this plugin was created originally with isometric perspective and 3d pixel art games in mind, it can be used for a plethora of genres.

Below you will find a brief explanation of all the tools included in the plugin. A more in depth explanation of how all the tools function internally can be found in the _documentation+_ folder. Other plugin explanations and where to find certain code can also be found in the same folder.

For community showcases, feature requests and bug reporting, please refer to the [discord](https://discord.gg/ZSeYkTCgft).

## Tool Overview

### Brush Tool
* Used to elevate or lower terrain.
  * Holding **[SHIFT]** and pressing **[LEFT MOUSE BUTTON]** with most brush tools selected will keep adding terrain to the selection even after letting go of the original mouse click.
  * In the same fashion as above, holding **[SHIFT]** and using the **[SCROLL WHEEL]** decreases and increases the current brush size.
  * You can also press **[ALT]** to deselect the current draw selection.

### Level Tool
* Used to level terrain to a certain height.
  * Press **[CTRL]** while hovering over terrain to set the current level height to the hovered terrain's height.

### Smooth Tool
* Used to smooth neighbouring terrain to their average height.

### Bridge Tool
* Used to create a bridge between two points.
  * The bridge curve falloff can be set via the "ease value" attribute. For reference see the below ease value cheatsheet (see also the _documentation+_ folder).

![Godot Ease Value Cheatsheet](documentation+\ease_cheatsheet.png "Ease Cheatsheet")

### Grass Mask Tool
* Used to control where grass gets placed.

### Vertex Paint Tool
* Used to paint textures onto the terrain.
  * 16 textures in total of which 15 can be editted.
	* The final 16th texture is used for turning terrain invisible.
	* The first 6 textures can have grass.
	* Texture names can be changed at will.
  * Texture presets can be used to quickly swap between texture pallets.
	* They can be exported in the plugin via the right hand UI panel at the bottom.
  * "Quick Paints" are a way to quickly set textures while moddeling the terrain.
	* They can be accesed via any of the height based terrain brushes.
	* You can make global or texture preset specific ones. 
	  * → Create a **MarchingSquaresQuickPaint** resource in their dedicated folders in the parent plugin folder.

### Debug Brush Tool
* Used to print the following data about selected cells:
  * Global position;
  * Internal color id;
  * Normals;

### Chunk Management Tool
* Used to create, delete and change chunk settings.
* Individual chunk's vertex merge thresholds can be changed → making terrain _rounder_ or _blockier_.

### Terrain Settings Tool
* Used to tweak global terrain settings.
  * The "Blend Mode" dropdown menu allows you to set the terrain's texture blending mode to suit your liking.
  * Setting a "Noise Hmap" makes the base chunk height generation procedural instead of flat.
  * Setting the "Animation Fps" value to more than 0 makes the grass sprites move with limited fps.
	* Keeping it at 0 gives the grass a smooth wind based effect.
  * "Ridge Threshold" controls how close grass sprites get spawned to lowering terrain(cliffs).
  * "Ledge Threshold" controls how close grass sprites get spawned to elevating terrain (walls).

## License (MIT)
Feel free to use, improve and change this plugin according to your needs, but include a copyright mention to the original project and author.
