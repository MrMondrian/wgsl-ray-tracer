#define_import_path geodesic

fn init_p(x: vec4<f32>, direction: vec3<f32>) -> vec4<f32> {
    let r = x[1];
    let theta = x[2];
    let phi = x[3];

    let dir = normalize(direction);

    let sin_t = sin(theta);
    let cos_t = cos(theta);
    let sin_p = sin(phi);
    let cos_p = cos(phi);

    let r_hat     = vec3<f32>(sin_t * cos_p, sin_t * sin_p, cos_t);
    let theta_hat = vec3<f32>(cos_t * cos_p, cos_t * sin_p, -sin_t);
    let phi_hat   = vec3<f32>(-sin_p, cos_p, 0.0);

    let pt      = -1.0; // Energy constant (null geodesic)
    let pl      = dot(dir, r_hat);
    let p_theta = r * dot(dir, theta_hat);
    let p_phi   = r * sin_t * dot(dir, phi_hat);

    return vec4<f32>(pt, pl, p_theta, p_phi);
}

fn inverse_metric_tensor(x: vec4<f32>) -> mat4x4<f32> {
    let r = x[1];
    let theta = x[2];
    let r_squared = max(r * r, 1e-6);
    let sin_theta = sin(theta);
    let sin_squared_theta = max(sin_theta * sin_theta, 1e-6);
    return mat4x4<f32>(
        -1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0 / r_squared, 0.0,
        0.0, 0.0, 0.0, 1.0 / (r_squared * sin_squared_theta)
    );
}

fn partial_derivative_inverse_metric_tensor(u: u32, x: vec4<f32>) -> mat4x4<f32> {
    let r = x[1];
    let theta = x[2];

    let r3 = max(r * r * r, 1e-9);
    let sin_t = sin(theta);
    let sin2_t = max(sin_t * sin_t, 1e-6);
    let sin3_t = max(sin2_t * abs(sin_t), 1e-9);
    let cos_t = cos(theta);

    var dg = mat4x4<f32>(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

    switch u {
        case 1u: { // d/dr
            dg[2][2] = -2.0 / r3;
            dg[3][3] = -2.0 / (r3 * sin2_t);
        }
        case 2u: { // d/dtheta
            dg[3][3] = (-2.0 * cos_t) / (max(r * r, 1e-6) * sin3_t);
        }
        default: {}
    }
    return dg;
}
