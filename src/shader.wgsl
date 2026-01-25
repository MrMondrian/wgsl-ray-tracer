#import lib::{
    Ray, Hitable, HitRecord, ScatterRecord, Material, Texture,
    max_f32, hit_object, null_hit_record,
    LAMBERTIAN, METAL, SOLID_COLOR, CHECKER, IMAGE
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
@group(3) @binding(1) var t_diffuse: texture_2d<f32>;


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

fn sample_vec3(rng_seed: vec3<f32>) -> vec3<f32> {
    let out = vec3<f32>(
        random_vec3(rng_seed + vec3<f32>(0.0, 1.0, 2.0)),
        random_vec3(rng_seed + vec3<f32>(3.0, 4.0, 5.0)),
        random_vec3(rng_seed + vec3<f32>(6.0, 7.0, 8.0))
    );
    return out * 2.0 - 1.0;
}

fn sample_square(rng_seed: vec3<f32>) -> vec2<f32> {
    let sample = vec2<f32>(
        random_vec3(rng_seed + vec3<f32>(0.0, 1.0, 2.0)),
        random_vec3(rng_seed + vec3<f32>(3.0, 4.0, 5.0))
    );
    return sample - 0.5;
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


fn random_vec3_on_hemisphere(normal: vec3<f32>, rng_seed: vec3<f32>) -> vec3<f32> {
    let p = normal + sample_vec3(rng_seed);
    var normed = normalize(p);
    if dot(normed, normal) < 0.0 {
        normed = -normed;
    }
    return normed;
}


fn random_vec2(v: vec2<f32>) -> f32 { return float_construct(hash_vec2(vec2<u32>(bitcast<u32>(v.x), bitcast<u32>(v.y)))); }
fn random_vec3(v: vec3<f32>) -> f32 { return float_construct(hash_vec3(vec3<u32>(bitcast<u32>(v.x), bitcast<u32>(v.y), bitcast<u32>(v.z)))); }
fn hash(x: u32) -> u32 {
    var result = x;
    result += (result << 10u);
    result ^= (result >>  6u);
    result += (result <<  3u);
    result ^= (result >> 11u);
    result += (result << 15u);
    return result;
}

// Compound versions of the hashing algorithm
fn hash_vec2(v: vec2<u32>) -> u32 { return hash(v.x ^ hash(v.y)); }
fn hash_vec3(v: vec3<u32>) -> u32 { return hash((v.x ^ hash(v.y)) ^ hash(v.z)); }

// Construct a float with half-open range [0:1] using low 23 bits.
fn float_construct(m: u32) -> f32 {
    let ieee_mantissa: u32 = 0x007FFFFFu; // binary32 mantissa bitmask
    let ieee_one: u32      = 0x3F800000u; // 1.0 in IEEE binary32

    let result = (m & ieee_mantissa) | ieee_one;  // Keep only mantissa bits and add exponent

    return bitcast<f32>(result) - 1.0;    // Range [0:1]
}

fn mat_4_to_3(m: mat4x4<f32>) -> mat3x3<f32> {
    return mat3x3<f32>(
        vec3<f32>(m[0].xyz),
        vec3<f32>(m[1].xyz),
        vec3<f32>(m[2].xyz)
    );
}

fn get_attenuation_image(rec: HitRecord) -> vec3<f32> {
    let dims = textureDimensions(t_diffuse);
    let x = clamp(u32(rec.u * f32(dims.x)), 0u, dims.x - 1u);
    let y = clamp(u32(rec.v * f32(dims.y)), 0u, dims.y - 1u);
    return textureLoad(t_diffuse, vec2<u32>(x, y), 0).xyz;
}

fn get_attenuation(tex: Texture, rec: HitRecord) -> vec3<f32> { 
    switch tex.kind { 
        case SOLID_COLOR: {
            return get_attenuation_solid(tex);
        }
        case CHECKER: {
            return get_attentuation_checker(tex, rec);
        }
        case IMAGE: {
            return get_attenuation_image(rec);

        }
        default: {
            return vec3(0.0,0.0,0.0);
        }
    }
}

fn scatter(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    if material.kind == LAMBERTIAN {
        return scatter_lambertian(material, r, rec, seed);
    }
    if material.kind == METAL {
        return scatter_metal(material, r, rec, seed);
    }
    return ScatterRecord(false, vec3(0.0, 0.0, 0.0), Ray(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)));
}

fn scatter_lambertian(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    let scatter_ray = random_vec3_on_hemisphere(rec.normal, seed);
    let scattered = Ray(rec.p, scatter_ray);
    let attenuation = get_attenuation(material.tex, rec);
    return ScatterRecord(true, attenuation, scattered);
}

fn scatter_metal(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    let reflected = reflect(normalize(r.direction), rec.normal);
    let scattered = Ray(rec.p, reflected);
    let attenuation = get_attenuation(material.tex, rec);
    return ScatterRecord(true, attenuation, scattered);
}

fn get_attenuation_solid(tex: Texture) -> vec3<f32> {
    return tex.albedo;
}

fn get_attentuation_checker(tex: Texture, rec: HitRecord) -> vec3<f32> {
    let x_int = floor(tex.inv_scale * rec.p.x);
    let y_int = floor(tex.inv_scale * rec.p.y);
    let z_int = floor(tex.inv_scale * rec.p.z);

    let is_even = (x_int + y_int + z_int) % 2 == 0;
    
    if is_even {
      return tex.even;
    }
    return tex.odd;
}
