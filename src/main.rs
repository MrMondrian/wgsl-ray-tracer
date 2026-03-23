use wgsl::{ray_tracer, Shader};

#[cfg_attr(target_arch="wasm32", wasm_bindgen(start))]
pub fn main() {
    let args: Vec<String> = std::env::args().collect();
    let shader = if args.iter().any(|a| a == "--minkowski") {
        Shader::SphericalMinkowski
    } else if args.iter().any(|a| a == "--ellis" || a == "--spherical") {
        Shader::SphericalEllis
    } else {
        Shader::Cartesian
    };

    ray_tracer(shader);
}
