struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
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

@group(0) @binding(0) var<uniform> camera: Camera;

@group(1) @binding(0) var<storage,read> hitabble_list: array<Hitable>;

@group(2) @binding(0) var<storage,read_write> prev_frame: array<vec4<f32>>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {

    let x = in.tex_coords.x * f32(camera.image_width);
    let y = in.tex_coords.y * f32(camera.image_height);
    
    var seed = vec3<f32>(in.tex_coords, in.tex_coords.x * in.tex_coords.y);
    seed = seed * f32(camera.iteration);

    let u = u32(floor(x));
    let v = u32(floor(y));

    let prev_color = prev_frame[u + v * camera.image_width];

    let sample = sample_square(seed);
    let pixel_loc = camera.pixel00_loc + ((x + sample.x) * camera.pixel_delta_u) + ((y + sample.y) * camera.pixel_delta_v);

    let ray_origin = camera.center;
    let ray_direction = pixel_loc - ray_origin;
    let ray = Ray(ray_origin, ray_direction);
    let sample_color = ray_color(ray, seed);
    let color = (f32(camera.iteration - 1u) * prev_color + sample_color) / f32(camera.iteration);
    prev_frame[u + v * camera.image_width] = color;
    return color;
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

fn hit_object(hitable: Hitable, r: Ray, t_min: f32, t_max: f32) -> HitRecord {
    if hitable.kind == SPHERE {
        return hit_sphere(hitable, r, t_min, t_max);
    }
    return null_hit_record();
}


fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.origin + t * ray.direction;
}

fn hit_sphere(hitable: Hitable, r: Ray, ray_tmin: f32, ray_tmax: f32) -> HitRecord {
    let oc = hitable.sphere.center - r.origin;
    let a = dot(r.direction, r.direction);
    let half_b = dot(oc,r.direction);
    let c = dot(oc,oc) - hitable.sphere.radius * hitable.sphere.radius;
    let discriminant = half_b*half_b - a*c;
    if discriminant < 0.0 {
        return null_hit_record();
    }

    let sqrtd = sqrt(discriminant);
    var root = (half_b - sqrtd) / a;

    if root <= ray_tmin || ray_tmax <= root {
        root = (half_b + sqrtd) / a;
        if root <= ray_tmin || ray_tmax <= root {
            return null_hit_record();
        } 
    }

    let p = at(r,root);
    let normal = normalize((p - hitable.sphere.center) / hitable.sphere.radius);
    var record = HitRecord(true,root,p,normal, hitable.material);
    record.normal = set_front_face(record, r);
    return record;

}

fn set_front_face(rec: HitRecord, r: Ray) -> vec3<f32> {
    let front_face = dot(r.direction, rec.normal) < 0.0;
    if !front_face {
        return -rec.normal;
    }
    return rec.normal;
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
    let attenuation = material.albedo;
    return ScatterRecord(true, attenuation, scattered);
}

fn scatter_metal(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    let reflected = reflect(normalize(r.direction), rec.normal);
    let scattered = Ray(rec.p, reflected);
    let attenuation = material.albedo;
    return ScatterRecord(true, attenuation, scattered);
}

fn reflect(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return v - 2.0 * dot(v, n) * n;
}

fn null_hit_record() -> HitRecord {
    return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), Material(vec3(0.0, 0.0, 0.0), 0));
}

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}

const SPHERE = u32(0);
const max_f32 = 3.40282347e+38;

struct Hitable {
    kind: u32,
    sphere: Sphere,
    material: Material,
}

struct Sphere {
    center: vec3<f32>,
    radius: f32,
}

struct HitRecord {
    hit: bool,
    t: f32,
    p: vec3<f32>,
    normal: vec3<f32>,
    material: Material,
}

struct ScatterRecord {
    hit: bool,
    attenuation: vec3<f32>,
    scattered: Ray,
}

struct Material {
    albedo: vec3<f32>,
    kind: u32,
}

const LAMBERTIAN = u32(0);
const METAL = u32(1);

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