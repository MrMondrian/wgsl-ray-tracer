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
    get_sphere_uv,
    cartesian_to_spherical,
    SphericalRay,
    ray_to_spherical,
    PI,
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

const DT: f32 = 1.0;
const BOUND: f32 = 1000;
const MAX_LOOPS: u32 = 1000;
const B: f32 = 1.0;

struct State {
    x: vec4<f32>,
    p: vec4<f32>
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
    let ray = Ray(ray_origin, normalize(ray_direction));
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
    // var curr_ray = ray;
    var i: u32 = 0;
    let origin_spherical = cartesian_to_spherical(ray.origin);
    let x = vec4<f32>(0.0,origin_spherical);
    let p = init_p(x, ray.direction);
    var state = State(x, p);
    while i < MAX_LOOPS && abs(state.x[1]) < BOUND {
        state = step_ray(state);
        i++;
    }
    let u = fract(state.x[3] / (2*PI) + 1.0);
    let v = clamp(state.x[2] / PI, 0.0, 1.0);
    let tex_index = select(0u, 1u, state.x[1] < 0.0);
    let color = get_attenuation_image(u, v, tex_index);
    return vec4<f32>(color, 1.0);
}

fn init_p(x: vec4<f32>, direction: vec3<f32>) ->  vec4<f32> {
    let l = x[1];
    let theta = x[2];
    let phi = x[3];

    let dir = normalize(direction);

    // Spherical basis vectors
    let sin_t = sin(theta);
    let cos_t = cos(theta);
    let sin_p = sin(phi);
    let cos_p = cos(phi);

    let r_hat     = vec3<f32>(sin_t * cos_p, sin_t * sin_p, cos_t);
    let theta_hat = vec3<f32>(cos_t * cos_p, cos_t * sin_p, -sin_t);
    let phi_hat   = vec3<f32>(-sin_p, cos_p, 0.0);

    // Angular scale factor for Ellis: sqrt(b^2 + l^2)
    let rho = sqrt(B * B + l * l);

    let pt      = -1.0; // Energy constant (null geodesic)
    let pl      = dot(dir, r_hat);
    let p_theta = rho * dot(dir, theta_hat);
    let p_phi   = rho * sin_t * dot(dir, phi_hat);

    return vec4<f32>(pt, pl, p_theta, p_phi);
}

fn step_ray(state: State) -> State {
    let x = state.x;
    let p = state.p;
    let x_dot = get_x_dot(x, p);
    let p_dot = get_p_dot(x, p );
    let x_new = x + DT * x_dot;
    let p_new = p + DT * p_dot;
    return State(x_new, p_new);
}

fn get_x_dot(x: vec4<f32>, p: vec4<f32>) -> vec4<f32> {
    return inverse_metric_tensor_ellis_spherical(x) * p;
}

fn get_p_dot(x: vec4<f32>, p: vec4<f32>) -> vec4<f32> {
    var p_dot = vec4<f32>(0,0,0,0);
    for(var i = 0; i < 4; i++) {
        p_dot[i] = -0.5 * dot(p, partial_derivative_inverse_metric_tensor_ellis_spherical(u32(i), x) * p);
    }
    return p_dot;
}

fn metric_tensor_minkowski_spherical(x: vec4<f32>) -> mat4x4<f32> {
    let r = x[1];
    let theta = x[2];
    let r_squared = r * r;
    let sin_theta = sin(theta);
    let sin_squared_theta = sin_theta * sin_theta;
    return mat4x4<f32> (
        -1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, r_squared, 0.0,
        0.0 , 0.0, 0.0, r_squared * sin_squared_theta
    );
}

fn inverse_metric_tensor_minkowski_spherical(x: vec4<f32>) -> mat4x4<f32> {
    let r = x[1];
    let theta = x[2];
    let r_squared = max(r * r, 1e-6);
    let sin_theta = sin(theta);
    let sin_squared_theta = max(sin_theta * sin_theta, 1e-6);
    return mat4x4<f32> (
        -1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0 / r_squared, 0.0,
        0.0 , 0.0, 0.0, 1.0 / (r_squared * sin_squared_theta)
    );
}

fn partial_derivative_inverse_metric_tensor_minkowski_spherical(u: u32, x: vec4<f32>) -> mat4x4<f32> {
    let r = x[1];
    let theta = x[2]; 
    
    let r3 = max(r * r * r, 1e-9);
    let sin_t = sin(theta);
    let sin2_t = max(sin_t * sin_t, 1e-6);
    let sin3_t = max(sin2_t * abs(sin_t), 1e-9);
    let cos_t = cos(theta);

    // Default to zero matrix
    var dg = mat4x4<f32>(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

    switch u {
        case 1u: { // d/dr
            dg[2][2] = -2.0 / r3;
            dg[3][3] = -2.0 / (r3 * sin2_t);
        }
        case 2u: { // d/dtheta
            dg[3][3] = (-2.0 * cos_t) / (max(r * r, 1e-6) * sin3_t);
        }
        default: { 
            // case 0 (time) and case 3 (phi) remain zero
        }
    }
    return dg;
}

fn metric_tensor_ellis_spherical(x: vec4<f32>) -> mat4x4<f32> {
    let l = x[1];
    let theta = x[2];
    let b_l_squared = B * B + l * l;
    let sin_theta = sin(theta);
    let sin_squared_theta = sin_theta * sin_theta;
    return mat4x4<f32> (
        -1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, b_l_squared, 0.0,
        0.0 , 0.0, 0.0, b_l_squared * sin_squared_theta
    );
}

fn inverse_metric_tensor_ellis_spherical(x: vec4<f32>) -> mat4x4<f32> {
    let l = x[1];
    let theta = x[2];
    let b_l_squared = B * B + l * l;
    let sin_theta = sin(theta);
    let sin_squared_theta = max(sin_theta * sin_theta, 1e-6);
    return mat4x4<f32> (
        -1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0 / b_l_squared, 0.0,
        0.0 , 0.0, 0.0, 1.0 / (b_l_squared * sin_squared_theta)
    );
}

fn partial_derivative_inverse_metric_tensor_ellis_spherical(u: u32, x: vec4<f32>) -> mat4x4<f32> {
    let l = x[1];
    let theta = x[2]; 
    
    let R2 = l * l + B * B;
    let R4 = max(R2 * R2, 1e-9); // R^4 for the denominator
    
    let sin_t = sin(theta);
    let cos_t = cos(theta);
    let sin2_t = max(sin_t * sin_t, 1e-6);
    let sin3_t = sin2_t * sin_t;

    var dg = mat4x4<f32>(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

    switch u {
        case 1u: { // d/dl (Radial Change)
            let common_deriv = (-2.0 * l) / R4;
            dg[2][2] = common_deriv;             // d/dl of (1/R^2)
            dg[3][3] = common_deriv / sin2_t;    // d/dl of (1/(R^2 * sin^2))
        }
        case 2u: { // d/dtheta (Angular Change)
            // Only the phi component depends on theta
            dg[3][3] = (-2.0 * cos_t) / (R2 * sin3_t);
        }
        default: {
            // d/dt and d/dphi are 0 (Static and Axisymmetric)
        }
    }
    return dg;
}
