#define_import_path blit
// Blit shaders - full-screen triangle using vertex_index trick
struct BlitVertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
}

fn blit_vs_impl(vertex_index: u32) -> BlitVertexOutput {
    // Full-screen triangle: 3 vertices that cover the entire screen
    // Vertex 0: (-1, -1), Vertex 1: (3, -1), Vertex 2: (-1, 3)
    var out: BlitVertexOutput;
    let x = f32(i32(vertex_index & 1u) * 4 - 1);
    let y = f32(i32(vertex_index >> 1u) * 4 - 1);
    out.position = vec4<f32>(x, y, 0.0, 1.0);
    // Texture coordinates: (0,1), (2,1), (0,-1) -> after clipping covers (0,0) to (1,1)
    out.tex_coords = vec2<f32>((x + 1.0) * 0.5, (1.0 - y) * 0.5);
    return out;
}

@group(0) @binding(0) var blit_texture: texture_2d<f32>;
@group(0) @binding(1) var blit_sampler: sampler;
