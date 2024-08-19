use glam::Vec3;

#[repr(C)]
#[derive(Copy, Clone, Debug,)]
pub struct Hittable {
    kind: u32,
    _padding: [u32; 3], // Padding to align with the next field
    sphere: Sphere,
}


impl Hittable {
    pub fn new(kind: u32, sphere: Sphere) -> Self {
        Self {
            kind,
            _padding: [0; 3],
            sphere,
        }
    }
}

unsafe impl bytemuck::Pod for Hittable {}
unsafe impl bytemuck::Zeroable for Hittable {}

#[repr(C)]
#[derive(Copy, Clone, Debug,)]
pub struct Sphere {
    center: Vec3,
    radius: f32,
}

impl Sphere {
    pub fn new(center: Vec3, radius: f32) -> Self {
        Self {
            center,
            radius,
        }
    }
}

unsafe impl bytemuck::Pod for Sphere {}
unsafe impl bytemuck::Zeroable for Sphere {}

const SPHERE: u32 = 0;