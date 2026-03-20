#import lib::{
  Ray,
  HitRecord,
  ScatterRecord,
  Material,
  Texture,
  max_f32,
  hit_object, 
  null_hit_record, 
  scatter, 
  sample_vec3, 
  sample_square, 
  mat_4_to_3,
  get_attenuation_image,
  get_sphere_uv
}

#import binds::{
  Camera,
  camera,
  hitabble_list,
  prev_frame,
  output_texture
}

#import blit::{
  BlitVertexOutput,
  blit_texture,
  blit_sampler,
  blit_vs_impl,
}

@vertex
fn blit_vs(@builtin(vertex_index) vertex_index: u32) -> BlitVertexOutput {
    return blit_vs_impl(vertex_index);
}

@fragment
fn blit_fs(in: BlitVertexOutput) -> @location(0) vec4<f32> {
    return textureSample(blit_texture, blit_sampler, in.tex_coords);
}


// Compute shader entry point
@compute @workgroup_size(8, 8)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let x = global_id.x;
    let y = global_id.y;

    // Bounds check
    if x >= camera.image_width || y >= u32(camera.image_height) {
        return;
    }

    let fx = f32(x);
    let fy = f32(y);
    let tex_coords = vec2<f32>(fx / f32(camera.image_width), fy / camera.image_height);

    var seed = vec3<f32>(tex_coords, tex_coords.x * tex_coords.y);
    seed = seed * f32(camera.iteration);

    let prev_color = prev_frame[x + y * camera.image_width];

    let sample = sample_square(seed);
    let pixel_loc = camera.pixel00_loc + ((fx + sample.x) * camera.pixel_delta_u) + ((fy + sample.y) * camera.pixel_delta_v);

    let ray_origin = camera.center;
    var ray_direction = pixel_loc - ray_origin;
    ray_direction = mat_4_to_3(camera.rotation) * ray_direction;
    let ray = Ray(ray_origin, ray_direction);
    let sample_color = ray_color(ray, seed);
    let color = (f32(camera.iteration - 1u) * prev_color + sample_color) / f32(camera.iteration);
    prev_frame[x + y * camera.image_width] = color;
    textureStore(output_texture, vec2<i32>(i32(x), i32(y)), color);
}

// Path-traces a single ray up to camera.max_depth bounces.
// Accumulates per-bounce attenuation and applies the sky gradient for the terminal ray.
fn ray_color(ray: Ray, seed: vec3<f32>)  -> vec4<f32> {
    var hits = 0u;
    var attenuations = array<vec3<f32>, 100>();
    var curr_ray = ray;
    let uv = get_sphere_uv(normalize(ray.direction));
    var color = get_attenuation_image(uv.x, uv.y);
    return vec4<f32>(color, 1.0);
}
