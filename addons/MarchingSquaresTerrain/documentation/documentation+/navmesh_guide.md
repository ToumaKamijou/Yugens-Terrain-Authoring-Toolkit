# NavigationMesh Guide

As the plugin currently generates dense, complex geometry it can sometimes be hard to bake a standard NavigationMesh. This small guide shows a simple step-by-step process that will make a working NavigationMesh for your terrain and games!

(This guide is courtesy of [DanTrz](https://github.com/DanTrz))

## Setting up!

1. Create a NavigationRegion3D and move it to the root of your scene.
2. Within the NavigationRegion3D set the following setting attributes:
   * Parsed Geometry Type → Static Colliders
   * Source Geometry Mode → Group Explicit
   * Cells (Cell Size) → 1.0
   * Cells (Cell Height) → 0.5
   * Agents (Height) → 2.0
   * Agents (Radius) → 1.0
   * Agents (Max Climb) → 0.5
3. In the Source Group Name (within NavigationMesh), you will now need to specify what groups to generate the NavigationMesh data for. This will avoid godot scanning everything. The new settings we just applied will reduce the data required for this process.
4. Finally, make sure that within the **Terrain Chunk** nodes, the "StaticBody3D" nodes in are added to the group you listed in "Source Group Name" setting.
- By doing this, you will only generate NavMeshData for the specific chunks' "StaticBody3D" that you added to the group. And with the new NavigationMesh resource settings, you will reduce the complexity in the NavData generated.
