# Terrain Controllers

This folder is reserved for focused terrain subsystem controllers.

Planned controllers include:

- `MSTNavMeshController.gd` — NavMesh painting, baking, caching, and cleanup. (next extraction)
- `MSTCollisionController.gd` — Collision rebuild queue, debounce, and diagnostics.
- `MSTMaterialController.gd` — Wind, material synchronization, and terrain visual state.
- `MSTPostProcessController.gd` — Post-processing effect management.

Keep serialized terrain settings and scene/chunk ownership on `MarchingSquaresTerrain`; controllers should own subsystem behavior and state.
