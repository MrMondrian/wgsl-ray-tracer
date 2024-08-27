use wgsl::ray_tracer;
use wgsl::hitable::*;
use nalgebra::Vector3;

fn main() {

    let sphere1 = Sphere::new(Vector3::new(0.0, 0.0, -1.2), 0.5);
    let material1 = Material::new(Vector3::new(0.8, 0.3, 0.3), 0);
    let sphere2: Sphere = Sphere::new(Vector3::new(0.0, -100.5, -1.0), 100.0);
    let material2 = Material::new(Vector3::new(0.8, 0.8, 0.0), 0);
    let sphere3: Sphere = Sphere::new(Vector3::new(-1.0, 0.0, -1.0), 0.5);
    let material3 = Material::new(Vector3::new(0.8, 0.6, 0.2), 1);
    let sphere4: Sphere = Sphere::new(Vector3::new(1.0, 0.0, -1.0), 0.5);
    let material4 = Material::new(Vector3::new(0.8, 0.8, 0.8), 1);
    
    let hitable1 = Hitable::new(0, sphere1, material1);
    let hitable2 = Hitable::new(0, sphere2, material2);
    let hitable3 = Hitable::new(0, sphere3, material3);
    let hitable4 = Hitable::new(0, sphere4, material4);

    let hitable_list = vec![hitable1, hitable2, hitable3, hitable4];

    ray_tracer(hitable_list);
}