# Internal Tool System Guide

This guide serves to explain how the internal tool system and its related code is setup and functions. It will first go over how the math and code behind the tools work and afterwards will explain how you can add your own tools. However, if you want to understand the tools its first necessary to understand how the terrain is structured under the hood.

## Terrain Explained (SIMPLE VERSION)

The terrain is built from the marching squares algorithm, which means that unlike the marching cubes algorithm it can only have variation in the Y axis. For this reason, the terrain is built from a cellular grid (adjustable in the chunk management settings tab in the plugin) and all the terrain behaviour is calculated from values stored in or referencing to those cells. For example, the process for increasing terrain height works as follows: 1. select the cells you want to change the height value for; 2. pick a higher number; 3. store those new numbers in a height map. Almost everything in the plugin works this way, color values for the grass and floor, texture id's, etc...

## Tools Explained

Tools are an easy way to switch between functionalilty within the plugin. Tools are inherently resources that can be set via the inspector. The most important of the @export tool settings is the **MarchingSquaresToolAttributeSettings** resource. This is a list currently containing the following attribute categories for tools to use:

### Brush Attributes

These attributes can theoretically be used for any type of brush the user wants to create.

* brush_type → square or round
* size  → size of the brush
* ease_value → makes terrain made by the bridge tool more rounded if the value is increased or decreased
* height → controls the height of the terrain created by the level tool
* strength → controls how big the effect of the smooth tool is
* flatten → will make all the selected terrain the same height as the first selected cell
* falloff → will make the effect of certain brushes decrease the further the selected terrain cells are from the center of the selection
* quick_paint_selection → allows for height based brushes to instantly apply textures without having to use the vertex paint tool. The smooth tool skips skips this behaviour when the quick_paint_selection is set to "none". Other tools will apply the base wall and floor textures instead.

### Brush Specific Attributes

These are attributes specifically made to work for a singular specific brush and don't provide any value outside of those brushes:

* vp_falloff_mode → uses a special pattern different from the normal falloff to select cells while vertex painting
* curve_3d_mode → switches between point based and free form line bridge calculations
* mask_mode → controls if selected terrain should have grass spawn on it or not
* material → used for selecting which texture to use while vertex painting the terrain
* texture_name → used to change the material names in the plugin interface
* texture_preset → used to change all the vertex painting settings via pre-saved resources. This allows for quick swapping between aesthetics.
* paint_walls → self explanatory
* populator → used for selecting the current populator node in the tree
* remove_selection → used to remove parts of the current populator's cell selection

### Non-Brush Related Attributes

These are usually reserved for terrain settings and also have interal code that deviates from the above attributes:

* chunk_management → has the option to change individual and global chunk settings as well as set navmesh bounds based on the terrain cells
* terrain_settings → features all the global terrain settings as well as some (global) grass settings
* heightmap → can import & export the terrain and its chunks as well as extract and place custom mesh-heightmaps via a brush

### ________
The above settings are contained in an array of booleans per tool which can be set in the inspector. Enabling a setting in the array makes it popup in the plugin window when the tool is selected. When adding all the UI to the screen the plugin will read a **MarchingSquaresToolAttributesList** resource for all the necessary data such as label names, what type of UI element it should be, default values, etc. This resource also contains the export variable for the texture names in the vertex paint tool.

## How to Create New Tools?

To start making your own tools you need to first create a new **MarchingSquaresTool** resource in the tools folder. Simply right click in the folder and select _Create New_ → _Resource..._. You should see an option with a wrench icon. Make sure to also put the newly created tool in the **MarchingSquaresToolbox** script as a preload. Doing this, however, only allows you to create tools which can make use of all the pre-existing attributes listed above. But, what if you want to make new attributes (which you probably do if you are reading this)?

### Making New Attributes

To create new attributes you first need to go into the **MarchingSquaresToolAttributeSettings** script and add an export boolean value for the attribute you wish to create.

* _(Attribute UI gets created from top to bottom so if you wish to have consistency in whether checkboxes or sliders etc. are next to each other, then make sure that you account for that here.)_

To make the attribute actually readable in the code you need to do a couple of things. First, you need to go into the **MarchingSquaresToolAttributes** script and find the `new_attributes` variable and place the new attribute in its array with the following formatting:
```
	if tool_attributes.example:
		new_attributes.append(attribute_list.example)
```
Next up is creating the actual dictionary with all the attribute related data. To do this you need to create a new dictionary in the **MarchingSquaresToolAttributesList** script. Here you need to at least specify the _name_, UI _type_, _label_ text and _default_ value. Some tools like the already available vertex paint tool require extra attribute data like how many _options_ there are in the dropdown menu, but this depends on the type of UI element you are adding to the plugin window. Here is an example of what a dictionary entry should (and could) look like:
```
var example : Dictionary = {
	"name": "example",
	"type": "option",
	"label": "Example",
	"options": ["Grass", "Sand", "Rock"],
	"default": 0, # You need to use an integer for indexed values like options.
}
```
The current _type_ field options are:
1. CHECKBOX,
2. SLIDER,
3. OPTION,
4. TEXT,
5. CHUNK,
6. TERRAIN,
7. PRESET,
8. QUICK_PAINT,
9. HEIGHTMAP,
10. ERROR, _# This one is used as a failsafe if the internal logic fails._

If you have a tool that uses custom logic that has nothing to do with brushes, then it is recommended to make its own option for it like CHUNK or TERRAIN. Adding new options can be done in the **MarchingSquaresToolAttributes** script under the `enum SettingType` variable. Make sure to also include the new setting type in the `type_map` variable in the `show_tool_attributes(tool_index: int) -> void` function.

### Setting up the Attribute Code

After you have created your new attribute and selected it in the inspector for the tool resource, its time for coding in the actual attribute behaviour step by step:

* In the **MarchingSquaresToolAttributes** script you will find the `add_setting(p_params: Dictionary) -> void:` function and within it the `match setting_type:` operation. 
  * If you created a new _type_ setting then you should create a new match statement for it here.
  * Setting types like CHECKBOX will not need any modifications for you to see and use them in the editor. However, other types like slider will need you to specify what kind of slider it is. You can easily check for these differences by using an if statement and checking for the setting_name variable.
* Next up you need to create a matching variable for your attribute in the **MarchingSquaresTerrainPlugin** script and go to the `_get_setting_value(p_setting_name: String) -> Variant:` function in the **MarchingSquaresToolAttributes** script and add your attribute and variable to it.
* Finally, go to the **MarchingSquareUI** script and do the same in the `_on_setting_changed(p_setting_name: String, p_value: Variant) -> void:` function.

### Implementing Tool Functionality

[DISCLAIMER] Some tool functionality like disabling certain variables during certain tool uses is too complex to explain here and would require this guide to explain all the code in the plugin. If you find yourself stuck coding in new behaviour and can't figure out a good solution, please consider joining the [discord](https://discord.gg/ZSeYkTCgft) to ask questions and get feedback!

To actually make your tools do something, you need to code in the behaviour in the **MarchingSquaresTerrainPlugin** script. First up, find the `TerrainToolMode` variable and place your new tool in the enum list. If your new tool is brush based and has to do with changing the height in any sort of way the next section will be easy, otherwise you will need to do a lot more work to make your tool work:

* For brush related tools, first up you need to go to the `draw_pattern(terrain: MarchingSquaresTerrain)` function and create a new if statement in the `for draw_cell_coords: Vector2i in draw_chunk_dict:` loop matching your tool.
* If your brush is height based, then you can code in the behaviour of the brush by setting the restore_value (value that gets used to undo an action) variable to `restore_value = chunk.get_height(draw_cell_coords)`, and the draw_value variable to the actual new height you calculated with the new behaviour. You can now skip the other steps and test your new tool, but if you have other wishes for your tools, keep reading.
* If your tool is brush based and does not modify the height you will need to create a new undo_redo action. They should be at the end of the function where you have been working in up until now. Make sure to create a new elif statement that matching your tool mode. In the same script you will need to create a new function that handles the new behaviour. Depending on the intended behaviour you will need to write multiple new functions in several scripts that modify, retrieve and store all sorts of new variables. To get a good idea of how to do this you can look through the plugin for the functions and variables related to the VERTEX_PAINT tool mode.
* If your tool is non-brush based and does things in the world based on the position of your mouse, then you can code in new behaviour in the `handle_mouse(camera: Camera3D, event: InputEvent) -> int` function under the `if intersection:` statement. Look at how the code for the CHUNK_MANAGEMENT tool mode is set up for examples.
* For all the other tool types you will need to think of new ways to implement the behaviour. These make up the minority of the cases but one such tool is the TERRAIN_SETTINGS tool mode that only lets you interact with the editor and connects @export variables that store terrain data like wall color to the UI.

## Adding Terrain Settings

As adding terrain settings works almost the same as adding new tool attributes, this section will only cover new information. You will first need to create a new @export variable in the **MarchingSquaresTerrain** script. If you want to have the variable be hidden from the normal inspector you will need to use the following format: `@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE)`. After which you can set your normal variable data like type and default value. Make sure to create a setter function for the new variable like so:
```
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var example : int = 1:
	set(value):
		example = value
		# Here you will need to set the custom behaviour for your variable. E.g. if the variable is used inside a shader you can set it here instead of making a complicated array of functions calling each other everytime you want to change a value.
```
Next, we go into the **MarchingSquaresToolAttributes** script and place our newly created variable in the `terrain_settings_data` dictionary variable. Also make sure to link the terrain variable and the UI value to each other in the `_on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:` function in the **MarchingSquaresUI** script. All the other parts of the process like coding in what kind of UI element should appear etc. are the same as the tool attributes section above and can be found in the same sections of code but a little bit lower down.
