#define_import_path binds
#import lib::{
  Hitable
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
    @location(10) iteration: u32,
    @location(11) rotation: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> camera: Camera;

@group(1) @binding(0) var<storage,read> hitabble_list: array<Hitable>;

@group(2) @binding(0) var<storage,read_write> prev_frame: array<vec4<f32>>;

@group(3) @binding(0) var output_texture: texture_storage_2d<rgba8unorm, write>;
