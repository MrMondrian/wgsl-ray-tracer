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


fn ray_color(ray: Ray)  -> vec4<f32> {
    let t = hit_sphere(vec3(0.0, 0.0, -1.0), 0.5, ray);
    if t > 0.0 {
        let N = normalize(at(ray, t) - vec3(0.0, 0.0, -1.0));
        return vec4<f32>(0.5*(N.x+1.0), 0.5*(N.y+1.0), 0.5*(N.z+1.0), 1.0);
    }
    let unit_direction = normalize(ray.direction);
    let a = 0.5*(unit_direction.y + 1.0);
    let color =  (1.0-a)*vec3(1.0, 1.0, 1.0) + a*vec3(0.5, 0.7, 1.0);
    return vec4<f32>(color, 1.0);
}

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
}

fn at(ray: Ray, t: f32) -> vec3<f32> {
    return ray.origin + t * ray.direction;
}

fn hit_sphere(center: vec3<f32>, radius: f32, r: Ray) -> f32 {
    let oc = r.origin - center;
    let a = dot(r.direction, r.direction);
    let b = 2.0 * dot(oc, r.direction);
    let c = dot(oc, oc) - radius*radius;
    let discriminant = b*b - 4.0*a*c;
    if discriminant < 0.0 {
        return -1.0;
    } else {
        return (-b - sqrt(discriminant)) / (2.0*a);
    }
}
