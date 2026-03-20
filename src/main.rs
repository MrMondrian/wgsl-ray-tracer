use wgsl::{ray_tracer, Shader};

#[cfg_attr(target_arch="wasm32", wasm_bindgen(start))]
pub fn main() {
    let shader = std::env::args()
        .find(|a| a == "--spherical")
        .map(|_| Shader::Spherical)
        .unwrap_or(Shader::Cartesian);

    ray_tracer(shader);
}
