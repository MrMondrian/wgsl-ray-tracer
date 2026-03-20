use nalgebra::Vector3;

/// A scene object that can be hit by a ray.
///
/// Currently the only supported kind is `0` (sphere). The `kind` field
/// mirrors the WGSL `SPHERE` constant and drives dispatch in the shader.
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Hitable {
    kind: u32,
    _padding: [u32; 3], // Padding to align with the next field
    sphere: Sphere,
    material: Material,
}

impl Hitable {
    /// Creates a new hitable with the given object kind, sphere geometry, and material.
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

/// Sphere geometry: center position and radius.
#[repr(C)]
#[derive(Copy, Clone, Debug,)]
pub struct Sphere {
    center: Vector3<f32>,
    radius: f32,
}

impl Sphere {
    /// Creates a sphere with the given center and radius.
    pub fn new(center: Vector3<f32>, radius: f32) -> Self {
        Self {
            center,
            radius,
        }
    }
}

unsafe impl bytemuck::Pod for Sphere {}
unsafe impl bytemuck::Zeroable for Sphere {}


/// Texture descriptor uploaded to the GPU.
///
/// `kind` selects the texture mode: `0` = solid color, `1` = checker, `2` = image.
/// Unused fields are zeroed for their respective kinds.
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Texture {
    albedo: Vector3<f32>,
    kind: u32,
    inv_scale: f32,
    _padding0: [u32; 3], // Pad to align `even` to 16-byte boundary (offset 32)
    even: Vector3<f32>,
    _padding1: u32,
    odd: Vector3<f32>,
    _padding2: u32,
}

impl Texture {
    /// Creates a solid-color texture with the given albedo.
    pub fn solid(albedo: Vector3<f32>) -> Self {
        Self {
            albedo,
            kind: 0,
            inv_scale: 0.0,
            _padding0: [0; 3],
            even: Vector3::new(0.0, 0.0, 0.0),
            _padding1: 0,
            odd: Vector3::new(0.0, 0.0, 0.0),
            _padding2: 0,
        }
    }

    /// Creates a 3D checker texture that alternates between `even` and `odd` colors.
    /// `scale` controls the size of the checker cells.
    pub fn checker(scale: f32, even: Vector3<f32>, odd: Vector3<f32>) -> Self {
        Self {
            albedo: Vector3::new(0.0, 0.0, 0.0),
            kind: 1, // CHECKER
            inv_scale: 1.0 / scale,
            _padding0: [0; 3],
            even,
            _padding1: 0,
            odd,
            _padding2: 0,
        }
    }

    /// Creates an image texture that samples from the bound diffuse texture (`t_diffuse`).
    pub fn image() -> Self {
        Self {
            albedo: Vector3::new(0.0, 0.0, 0.0),
            kind: 2, // CHECKER
            inv_scale: 0.0,
            _padding0: [0; 3],
            even: Vector3::new(0.0, 0.0, 0.0),
            _padding1: 0,
            odd: Vector3::new(0.0, 0.0, 0.0),
            _padding2: 0,
        }
    }
}

unsafe impl bytemuck::Pod for Texture {}
unsafe impl bytemuck::Zeroable for Texture {}

/// Material descriptor: a texture plus a scatter model kind.
///
/// `kind` selects the BRDF: `0` = Lambertian diffuse, `1` = metal (specular reflection).
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Material {
    tex: Texture,
    kind: u32,
    _padding: [u32; 3], // Pad to 32 bytes to match WGSL layout
}

impl Material {
    /// Creates a material with the given texture and scatter kind.
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
