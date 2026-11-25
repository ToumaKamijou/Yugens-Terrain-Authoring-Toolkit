# Code Style Guide

If you want to contribute to the plugin by opening a PR then it is helpfull that everyone who works on the plugin follows a predetermined code style. This short guide will give several code examples to help you on your way to create awesome additions to the plugin!

## Examples

### Basic script setup

All the scripts in the plugin follow the following conventions when setting up:
* The node type that gets extended is placed before the class name.
* Class names should have the **MarchingSquares** or **MST** prefix attached to them.
  * **MST** is prefered if the class name is very long.
* Variables/Functions/etc... should use snakecase.
* Private functions should have a '_' in front of their function name.
  * Normal variables do not follow this rule.
* The script_wide variable section and all functions should have 2 whitelines between them.
* Typing for variables should have a space in front of the ':'. 
  * (e.g. "variable_name : float" instead of "variable_name: float")
  * However, typing for functions, dictionaries, etc. should follow normal conventions.
* Exported variables should follow the below structure.
* There should be tabs instead of blanks between code parts.
  * These tabs should go until the next line's starting tab. 
* Regions can be one space apart from each other as can functions at the top and bottom of regions.
  * All the other functions inside or outside regions except for the above exceptions should have two spaces between them.
  * Variable regions shouldn't have any spaces between them.
  * Regions shouldn't contain capitalization in their names.
* Only use double hashtags for editor visible comments that explain the functionality of export variables, functions or classes.
* All comments should start with a capital.

```
@tool
extends ExampleNode3D
class_name MarchingSquaresExampleClass
## This is an example class that shows how to style your code in this plugin.

enum Enum_Variable {1, 2, 3, 4, 5}

const CONSTANT_VARIABLE : int = 1

# This is a normal comment on how the variable works
var variable : float = 1.0

#region example vars
var ex1 : int = 0
var ex2 : int = 1
#endregion

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var export_variable : String = "example":
	set(value):
		export_variable = value
		# other code that affects e.g. the terrain shader


#region example functions

func _example_private_function(parameter_variable: int) -> int:
	var mult_val := 5
	return parameter_variable * mult_val


func example_public_function(parameter_variable: float) -> void:
	variable = parameter_variable

#endregion

#region one more example region

#endregion
```
