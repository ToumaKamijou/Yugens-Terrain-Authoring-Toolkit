# Yūgen's Terrain Authoring Toolkit
The public version of the Marching Squares Terrain plugin for godot.

This project is an effort to create a simple to use and powerfull terrain authoring tool inside godot aimed at 3d pixel art games. However, the plugin featured in this project can be used for a wide variety of games and experimentation is encouraged! As of right now the plugin has the following features:

* Elevate and lower terrain based on cells in a chunk grid
* Level terrain to a user-set height
* Smooth terrain depending on the average height of neighbouring cells
* Create a bridge between two points by drawing a line between them
* Paint up to 15(+1) custom textures onto the terrain
* Paint a mask map that determines whether selected cells should draw `MultiMeshInstance3d` grass instances
* Get debug information for selected cells
* Change the internal marching squares algorithm vertex merge threshold value resulting in smoother or blockier terrain
* Change global terrain settings like wall texture, wall color, grass animation fps and more...

For more in-depth documentation, please refer to the _documentation_ folder in the addon.

For community showcases, feature requests and bug reporting, please refer to the [discord](https://discord.gg/ZSeYkTCgft).
A bug can also be reported by opening a new issue thread in the issues tab of this github project.

## Install Guide

To install the plugin, simply download or clone the latest stable version of this project and copy the plugin from this project's addon folder into your own. Make sure to turn on the plugin in godot by going into the project settings and under "plugins" checking the checkbox next to the plugin's name.

Watch the [YouTube](https://www.youtube.com/watch?v=TV3QyGNMAwo) video to get started with the plugin!!!

## Known Issues

1. Icons appear smaller with the new 4.6 godot standard theme (will be fixed in 1.1)
3. Wall textures don't disappear properly when the "void" texture is selected (will be fixed in 1.1)
4. Collision shapes dissapear when in front of a MarchingSquaresTerrain node
5. Terrain that is copied into a new open scene fails to load on startup (will be fixed in 1.1)
6. Brush visuals and cell data doesn't scale with cell_size so very small and very big cell sizes don't work properly
7. Running physics on a separate thread crashes the plugin (will be fixed in 1.2)
8. Terrain sizes are very big causing warning messages (will be fixed in 1.2)

## Credits

Developed by [Yūgen](https://www.youtube.com/@yugen_seishin) and originally forked from [Jackachulian](https://github.com/jackachulian/jackachulian) on github.

Special Contributors:
* [DanTrz](https://github.com/DanTrz)

A special thanks to DanTrz (creator of the TileMapLayer3D plugin) for co-authoring big parts of the plugin since the 1.0 release. He has been an amazing contributor to the project and an awesome guy to work with!

Contributors:
* [Dylearn](https://www.youtube.com/@Dylearn)
* [AtSaturn](https://www.youtube.com/@AtPlayerSaturn)
* My lifelong best friends!

###
A big thanks to the above people for giving helpful insights, discussing certain features and thinking together about math related problems. Without them I couldn't have finished the plugin as fast as I have.
