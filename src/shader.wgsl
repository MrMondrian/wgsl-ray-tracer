struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
}

@vertex
fn vs_main(
    model: VertexInput,
) -> VertexOutput {
    var out: VertexOutput;
    out.tex_coords = model.tex_coords;
    out.clip_position = vec4<f32>(model.position, 1.0);
    return out;
}

@group(0) @binding(0) var<uniform> frameData: vec2<u32>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let camera_center = vec3(0.0, 0.0, 0.0);
    return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
