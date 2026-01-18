use wgsl::ray_tracer;
// use wgsl::hitable::*;
// use nalgebra::Vector3;

#[cfg_attr(target_arch="wasm32", wasm_bindgen(start))]
pub fn main() {

    ray_tracer();
}
