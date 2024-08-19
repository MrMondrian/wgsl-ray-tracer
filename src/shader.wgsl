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

@group(0) @binding(0) var<uniform> frame_data: vec2<u32>;

@group(1) @binding(0) var<uniform> camera: Camera;

const NUM_HITABLES = 1u;
@group(2) @binding(0) var<storage,read> hitabble_list: array<Hitable>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {

    let x = in.tex_coords.x * f32(camera.image_width);
    let y = in.tex_coords.y * f32(camera.image_height);
    let pixel_loc = camera.pixel00_loc + x * camera.pixel_delta_u + y * camera.pixel_delta_v;

    let ray_origin = camera.center;
    let ray_direction = pixel_loc - ray_origin;
    let ray = Ray(ray_origin, ray_direction);
    return ray_color(ray);

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
}

fn ray_color(ray: Ray)  -> vec4<f32> {
    for (var idx = 0u; idx < NUM_HITABLES; idx = idx + 1u) {
        let sphere = hitabble_list[idx];
        let record = hit(sphere, ray, 0.0, max_f32);
        if record.hit {
            let N = normalize(at(ray, record.t) - vec3(0.0, 0.0, -1.0));
            return vec4<f32>(0.5*(N.x+1.0), 0.5*(N.y+1.0), 0.5*(N.z+1.0), 1.0);
        }
    }

    let unit_direction = normalize(ray.direction);
    let a = 0.5*(unit_direction.y + 1.0);
    let color =  (1.0-a)*vec3(1.0, 1.0, 1.0) + a*vec3(0.5, 0.7, 1.0);
    return vec4<f32>(color, 1.0);
}


fn hit(hitable: Hitable, r: Ray, t_min: f32, t_max: f32) -> HitRecord {
    // if hitable.kind == SPHERE {
        return hit_sphere(hitable.sphere, r, t_min, t_max);
    // }
    // return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0));
}


fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.origin + t * ray.direction;
}

fn hit_sphere(sphere: Sphere, r: Ray, ray_tmin: f32, ray_tmax: f32) -> HitRecord {
    let oc = sphere.center - r.origin;
    let a = dot(r.direction, r.direction);
    let half_b = dot(oc,r.direction);
    let c = dot(oc,oc) - sphere.radius * sphere.radius;
    let discriminant = half_b*half_b - a*c;
    if discriminant < 0.0 {
        return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0));
    }

    let sqrtd = sqrt(discriminant);
    var root = (half_b - sqrtd) / a;

    if root <= ray_tmin || ray_tmax <= root {
        root = (half_b + sqrtd) / a;
        if root <= ray_tmin || ray_tmax <= root {
            return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0));
        } 
    }

    let p = at(r,root);
    let normal = (p - sphere.center) / sphere.radius;
    var record = HitRecord(true,root,p,normal);
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
