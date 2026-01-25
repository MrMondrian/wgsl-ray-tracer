#define_import_path lib
const LAMBERTIAN: u32 = 0u;
const METAL: u32 = 1u;
const SOLID_COLOR: u32 = 0u;
const CHECKER: u32 = 1u;
const IMAGE: u32 = 2u;
const PI: f32 = 3.1415926;
const SPHERE: u32 = 0u;
const max_f32: f32 = 1000000.0;

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}

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
    u: f32,
    v: f32
}

struct ScatterRecord {
    hit: bool,
    attenuation: vec3<f32>,
    scattered: Ray,
}

struct Material {
    tex: Texture,
    kind: u32,
}

struct Texture {
    albedo: vec3<f32>,
    kind: u32,
    inv_scale: f32,
    even: vec3<f32>,
    odd: vec3<f32>,
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
    let uv = get_sphere_uv(normal);
    var record = HitRecord(true,root,p,normal, hitable.material, uv.x, uv.y);
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


fn get_sphere_uv(p: vec3<f32>) -> vec2<f32> {
    let theta = acos(-p.y);
    let phi = atan2(-p.z, p.x) + PI;
    let u = phi / (2*PI);
    let v = theta / PI;
    return vec2(u,v);
}

fn reflect(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return v - 2.0 * dot(v, n) * n;
}

fn null_hit_record() -> HitRecord {
    return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), Material(null_texture(), 0), 0.0, 0.0);
}

fn null_texture() -> Texture {
    return Texture(vec3(0.0,0.0,0.0),0, 0.0, vec3(0.0,0.0,0.0), vec3(0.0,0.0,0.0));
}
