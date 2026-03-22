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

#import binds_spherical::{
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

const DT_INIT: f32 = 1.0;
const DT_MIN: f32 = 0.01;
const DT_MAX: f32 = 10.0;
const TOL: f32 = 1e-4;
const BOUND: f32 = 1000;
const MAX_LOOPS: u32 = 1000;
const B: f32 = 1.0;

struct State {
    x: vec4<f32>,
    p: vec4<f32>
}

struct AdaptiveState {
    state: State,
    dt: f32,
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
    let x = vec4<f32>(0.0, camera.l, origin_spherical.y, origin_spherical.z);
    let p = init_p(x, ray.direction);
    var adaptive = AdaptiveState(State(x, p), DT_INIT);
    while i < MAX_LOOPS && abs(adaptive.state.x[1]) < BOUND {
        adaptive = step_rk24_adaptive(adaptive.state, adaptive.dt);
        i++;
    }
    let state = adaptive.state;
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


fn step_rk24_adaptive(state: State, dt: f32) -> AdaptiveState {
    let x = state.x;
    let p = state.p;

    // k1: slopes at start
    let k1_x = get_x_dot(x, p);
    let k1_p = get_p_dot(x, p);

    // k2: slopes at midpoint (shared by RK2 and RK4)
    let x_mid = x + 0.5 * dt * k1_x;
    let p_mid = p + 0.5 * dt * k1_p;
    let k2_x = get_x_dot(x_mid, p_mid);
    let k2_p = get_p_dot(x_mid, p_mid);

    // RK2 estimate (midpoint rule)
    let x_rk2 = x + dt * k2_x;
    let p_rk2 = p + dt * k2_p;

    // k3, k4: additional RK4 stages
    let x_mid2 = x + 0.5 * dt * k2_x;
    let p_mid2 = p + 0.5 * dt * k2_p;
    let k3_x = get_x_dot(x_mid2, p_mid2);
    let k3_p = get_p_dot(x_mid2, p_mid2);

    let x_end = x + dt * k3_x;
    let p_end = p + dt * k3_p;
    let k4_x = get_x_dot(x_end, p_end);
    let k4_p = get_p_dot(x_end, p_end);

    // RK4 estimate
    let x_rk4 = x + (dt / 6.0) * (k1_x + 2.0 * k2_x + 2.0 * k3_x + k4_x);
    let p_rk4 = p + (dt / 6.0) * (k1_p + 2.0 * k2_p + 2.0 * k3_p + k4_p);

    // Error: max component of |RK4 - RK2|
    let ex = abs(x_rk4 - x_rk2);
    let ep = abs(p_rk4 - p_rk2);
    let error = max(max(max(ex.x, ex.y), max(ex.z, ex.w)),
                    max(max(ep.x, ep.y), max(ep.z, ep.w)));

    // Scale next dt: error ~ O(dt^2) for RK2, so exponent is 1/3
    var new_dt = dt;
    if error > 1e-10 {
        new_dt = dt * clamp(0.9 * pow(TOL / error, 1.0 / 3.0), 0.1, 4.0);
    } else {
        new_dt = dt * 2.0;
    }
    new_dt = clamp(new_dt, DT_MIN, DT_MAX);

    return AdaptiveState(State(x_rk4, p_rk4), new_dt);
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
