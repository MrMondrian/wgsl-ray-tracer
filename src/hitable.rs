use nalgebra::Vector3;

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Hitable {
    kind: u32,
    _padding: [u32; 3], // Padding to align with the next field
    sphere: Sphere,
    material: Material,
}


impl Hitable {
    pub fn new(kind: u32, sphere: Sphere, material: Material) -> Self {
        Self {
            kind,
            _padding: [0; 3],
            sphere,
            material,
        }
    }
}

unsafe impl bytemuck::Pod for Hitable {}
unsafe impl bytemuck::Zeroable for Hitable {}

#[repr(C)]
#[derive(Copy, Clone, Debug,)]
pub struct Sphere {
    center: Vector3<f32>,
    radius: f32,
}

impl Sphere {
    pub fn new(center: Vector3<f32>, radius: f32) -> Self {
        Self {
            center,
            radius,
        }
    }
}

unsafe impl bytemuck::Pod for Sphere {}
unsafe impl bytemuck::Zeroable for Sphere {}


#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Texture {
    albedo: Vector3<f32>,
    kind: u32,
}

impl Texture {
    pub fn new(albedo: Vector3<f32>, kind: u32) -> Self {
        Self {
            albedo,
            kind,
        }
    }
}

unsafe impl bytemuck::Pod for Texture {}
unsafe impl bytemuck::Zeroable for Texture {}

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Material {
    tex: Texture,
    kind: u32,
    _padding: [u32; 3], // Pad to 32 bytes to match WGSL layout
}

impl Material {
    pub fn new(tex: Texture, kind: u32) -> Self {
        Self {
            tex,
            kind,
            _padding: [0; 3],
        }
    }
}

unsafe impl bytemuck::Pod for Material {}
unsafe impl bytemuck::Zeroable for Material {}
