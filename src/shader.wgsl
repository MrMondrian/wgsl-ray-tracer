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

@group(0) @binding(0) var<uniform> frame_data: vec2<u32>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let center = vec3(0.0, 0.0, 0.0);

    let aspect_ratio = 16.0/9.0;
    let image_width = f32(frame_data.x);
    let focal_length = 1.0;
    let view_height = 2.0;
    let image_height = f32(frame_data.y);
    let view_width = view_height * (image_width / image_height);


    let viewport_u = vec3(view_width,0.0,0.0);
    let viewport_v = vec3(0.0,-view_height,0.0);

    let pixel_delta_u = viewport_u / image_width;
    let pixel_delta_v = viewport_v / image_height;

    let view_upper_left = center - vec3(0.0,0.0,focal_length) - viewport_u/2.0 - viewport_v/2.0;

    let pixel00_loc = view_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);

    let x = in.tex_coords.x * image_width;
    let y = in.tex_coords.y * image_height;

    let pixel_loc = pixel00_loc + x * pixel_delta_u + y * pixel_delta_v;

    let ray_origin = center;
    let ray_direction = pixel_loc - ray_origin;
    let ray = Ray(ray_origin, ray_direction);
    return ray_color(ray);

}


fn ray_color(r: Ray)  -> vec4<f32> {
    let unit_direction = normalize(r.direction);
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
