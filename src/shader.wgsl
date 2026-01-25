#import lib::{
    Ray,
    Hitable,
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
    mat_4_to_3
}
struct Camera {
    @location(0) aspect_ratio: f32,
    @location(1) image_width: u32,
    @location(2) image_height: f32,
    @location(3) center: vec3<f32>,
    @location(4) pixel00_loc: vec3<f32>,
    @location(5) pixel_delta_u: vec3<f32>,
    @location(6) pixel_delta_v: vec3<f32>,
    @location(7) samples_per_pixel: u32,
    @location(8) pixels_sample_scale: f32,
    @location(9) max_depth: u32,
    @location(10) iteration: u32,
    @location(11) rotation: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> camera: Camera;

@group(1) @binding(0) var<storage,read> hitabble_list: array<Hitable>;

@group(2) @binding(0) var<storage,read_write> prev_frame: array<vec4<f32>>;

@group(3) @binding(0) var output_texture: texture_storage_2d<rgba8unorm, write>;


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

// Blit shaders - full-screen triangle using vertex_index trick
struct BlitVertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
}

@vertex
fn blit_vs(@builtin(vertex_index) vertex_index: u32) -> BlitVertexOutput {
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

@fragment
fn blit_fs(in: BlitVertexOutput) -> @location(0) vec4<f32> {
    return textureSample(blit_texture, blit_sampler, in.tex_coords);
}


fn ray_color(ray: Ray, seed: vec3<f32>)  -> vec4<f32> {
    var hits = 0u;
    var attenuations = array<vec3<f32>, 100>();
    var curr_ray = ray;
    var mutable_seed = seed;
    for(var depth = 0u; depth < camera.max_depth; depth = depth + 1u) {
        let hit_record = get_hit_record(curr_ray, 0.001, max_f32);
        if hit_record.hit {
            let scatter_record = scatter(hit_record.material, curr_ray, hit_record, mutable_seed);
            if scatter_record.hit {
                attenuations[hits] = scatter_record.attenuation;
                curr_ray = scatter_record.scattered;
                hits = hits + 1u;
                mutable_seed = sample_vec3(mutable_seed);
            }
            else {
                break;
            }
        }
        else {
            break;
        }
    }
    let unit_direction = normalize(curr_ray.direction);
    let a = 0.5*(unit_direction.y + 1.0);
    var color =  (1.0-a)*vec3(1.0, 1.0, 1.0) + a*vec3(0.5, 0.7, 1.0);
    for (var i = 0u; i < hits; i = i + 1u) {
        color *= attenuations[i];
    }
    return vec4<f32>(color, 1.0);
}

fn get_hit_record(r: Ray, t_min: f32, t_max: f32) -> HitRecord {
    var closest_so_far = max_f32;
    var record = null_hit_record();
    for (var idx = 0u; idx < arrayLength(&hitabble_list); idx = idx + 1u) {
        let sphere = hitabble_list[idx];
        let temp_record = hit_object(sphere, r, t_min, closest_so_far);
        if temp_record.hit {
            closest_so_far = temp_record.t;
            record = temp_record;
        }
    }
    return record;
}
