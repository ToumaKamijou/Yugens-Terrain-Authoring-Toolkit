shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, alpha_to_coverage;
render_mode unshaded;

#define BAKE_MODE 1
#include "mst_terrain.gdshaderinc"
