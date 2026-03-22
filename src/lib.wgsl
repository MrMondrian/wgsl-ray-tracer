#define_import_path lib
const LAMBERTIAN: u32 = 0u;
const METAL: u32 = 1u;
const SOLID_COLOR: u32 = 0u;
const CHECKER: u32 = 1u;
const IMAGE: u32 = 2u;
const PI: f32 = 3.1415926;
const SPHERE: u32 = 0u;
const max_f32: f32 = 1000000.0;

@group(3) @binding(1) var t_diffuse: texture_2d<f32>;

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

// Dispatches a ray-object intersection test based on the hitable's kind.
// Returns a null HitRecord if the kind is unrecognised or there is no hit.
fn hit_object(hitable: Hitable, r: Ray, t_min: f32, t_max: f32) -> HitRecord {
    if hitable.kind == SPHERE {
        return hit_sphere(hitable, r, t_min, t_max);
    }
    return null_hit_record();
}

// Evaluates the ray equation P(t) = origin + t * direction.
fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.origin + t * ray.direction;
}

// Ray-sphere intersection using the quadratic formula (half-b variant).
// Returns a null HitRecord if there is no hit in [ray_tmin, ray_tmax].
// Sets the outward normal and computes UV coordinates on the sphere surface.
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

// Ensures the stored normal always points against the incoming ray.
// Returns the (possibly flipped) normal for the hit record.
fn set_front_face(rec: HitRecord, r: Ray) -> vec3<f32> {
    let front_face = dot(r.direction, rec.normal) < 0.0;
    if !front_face {
        return -rec.normal;
    }
    return rec.normal;
}


// Maps a unit-sphere surface point to (u, v) in [0,1]^2.
// u is the longitude (0 at -x, 0.5 at +x), v is the latitude (0 at south pole).
fn get_sphere_uv(p: vec3<f32>) -> vec2<f32> {
    let theta = acos(-p.y);
    let phi = atan2(-p.z, p.x) + PI;
    let u = phi / (2*PI);
    let v = theta / PI;
    return vec2(u,v);
}

// Reflects vector v about normal n: v - 2*(v·n)*n.
fn reflect(v: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return v - 2.0 * dot(v, n) * n;
}

fn null_hit_record() -> HitRecord {
    return HitRecord(false, 0.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), Material(null_texture(), 0), 0.0, 0.0);
}

fn null_texture() -> Texture {
    return Texture(vec3(0.0,0.0,0.0),0, 0.0, vec3(0.0,0.0,0.0), vec3(0.0,0.0,0.0));
}
// Samples the bound diffuse texture at the hit's (u, v) coordinates.
fn get_attenuation_image_hr(rec: HitRecord) -> vec3<f32> {
    return get_attenuation_image(rec.u, rec.v);
}

fn get_attenuation_image(u: f32, v: f32) -> vec3<f32> {
    let dims = textureDimensions(t_diffuse);
    let x = clamp(u32(u * f32(dims.x)), 0u, dims.x - 1u);
    let y = clamp(u32(v * f32(dims.y)), 0u, dims.y - 1u);
    return textureLoad(t_diffuse, vec2<u32>(x, y), 0).xyz;
}

// Returns the attenuation color for a texture at the hit point.
// Dispatches to solid, checker, or image sampling based on tex.kind.
fn get_attenuation(tex: Texture, rec: HitRecord) -> vec3<f32> {
    switch tex.kind { 
        case SOLID_COLOR: {
            return get_attenuation_solid(tex);
        }
        case CHECKER: {
            return get_attentuation_checker(tex, rec);
        }
        case IMAGE: {
            return get_attenuation_image_hr(rec);

        }
        default: {
            return vec3(0.0,0.0,0.0);
        }
    }
}

// Dispatches scattering to the appropriate BRDF based on material.kind.
// Returns a null ScatterRecord for unknown material kinds.
fn scatter(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    if material.kind == LAMBERTIAN {
        return scatter_lambertian(material, r, rec, seed);
    }
    if material.kind == METAL {
        return scatter_metal(material, r, rec, seed);
    }
    return ScatterRecord(false, vec3(0.0, 0.0, 0.0), Ray(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)));
}

// Lambertian (diffuse) scatter: shoots a random ray on the hemisphere around the normal.
fn scatter_lambertian(material: Material, r: Ray, rec: HitRecord, seed: vec3<f32>) -> ScatterRecord {
    let scatter_ray = random_vec3_on_hemisphere(rec.normal, seed);
    let scattered = Ray(rec.p, scatter_ray);
    let attenuation = get_attenuation(material.tex, rec);
    return ScatterRecord(true, attenuation, scattered);
}

// Metal scatter: perfectly reflects the incoming ray about the surface normal.
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

// Generates a random unit vector in the hemisphere oriented around `normal`.
// Uses sample_vec3 for the random offset, then flips if it lands in the wrong hemisphere.
fn random_vec3_on_hemisphere(normal: vec3<f32>, rng_seed: vec3<f32>) -> vec3<f32> {
    let p = normal + sample_vec3(rng_seed);
    var normed = normalize(p);
    if dot(normed, normal) < 0.0 {
        normed = -normed;
    }
    return normed;
}

// Generates a random vec3 in [-1, 1]^3 by hashing three offset seeds.
fn sample_vec3(rng_seed: vec3<f32>) -> vec3<f32> {
    let out = vec3<f32>(
        random_vec3(rng_seed + vec3<f32>(0.0, 1.0, 2.0)),
        random_vec3(rng_seed + vec3<f32>(3.0, 4.0, 5.0)),
        random_vec3(rng_seed + vec3<f32>(6.0, 7.0, 8.0))
    );
    return out * 2.0 - 1.0;
}

// Generates a random vec2 in [-0.5, 0.5]^2 for sub-pixel jitter.
fn sample_square(rng_seed: vec3<f32>) -> vec2<f32> {
    let sample = vec2<f32>(
        random_vec3(rng_seed + vec3<f32>(0.0, 1.0, 2.0)),
        random_vec3(rng_seed + vec3<f32>(3.0, 4.0, 5.0))
    );
    return sample - 0.5;
}

fn random_vec2(v: vec2<f32>) -> f32 { return float_construct(hash_vec2(vec2<u32>(bitcast<u32>(v.x), bitcast<u32>(v.y)))); }
fn random_vec3(v: vec3<f32>) -> f32 { return float_construct(hash_vec3(vec3<u32>(bitcast<u32>(v.x), bitcast<u32>(v.y), bitcast<u32>(v.z)))); }
// Wang/Jenkins integer hash — avalanches all bits of x.
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

// Extracts the upper-left 3x3 rotation/scale block from a 4x4 matrix.
fn mat_4_to_3(m: mat4x4<f32>) -> mat3x3<f32> {
    return mat3x3<f32>(
        vec3<f32>(m[0].xyz),
        vec3<f32>(m[1].xyz),
        vec3<f32>(m[2].xyz)
    );
}

fn cartesian_to_spherical(cart: vec3<f32>) -> vec3<f32> {
    let r = length(cart);
    let phi = atan(cart.y / cart.y);
    let theta = acos(cart.z / r);
    return vec3<f32>(r,theta,phi);
}
