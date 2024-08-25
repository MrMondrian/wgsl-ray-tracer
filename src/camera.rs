use glam::Vec3;

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct Camera {
    pub aspect_ratio: f32,
    pub image_width: u32,
    pub image_height: f32,
    _pad1: f32,  // Padding to align center to 16 bytes
    pub center: Vec3,
    _pad2: f32,  // Padding to align pixel00_loc to 16 bytes
    pub pixel00_loc: Vec3,
    _pad3: f32,  // Padding to align pixel_delta_u to 16 bytes
    pub pixel_delta_u: Vec3,
    _pad4: f32,  // Padding to align pixel_delta_v to 16 bytes
    pub pixel_delta_v: Vec3,
    pub samples_per_pixel: u32,
    pub pixels_sample_scale: f32,
    pub max_depth: u32, // if this needs to be > 100 edit the shader
    _pad5: f32,
    _pad6: f32,  // Padding to align Camera to 16 bytes
}

impl Camera {


    pub fn new() -> Self {
        let aspect_ratio = 16.0 / 9.0;
        let image_width = 1280;
        let focal_length: f32 = 1.0;
        let view_height: f32 = 2.0;
        let center = Vec3::ZERO;
        let samples_per_pixel = 3;
        let max_depth = 10;
        let pixels_sample_scale = 1.0 / (samples_per_pixel as f32);
        let image_height: u32 = (image_width as f32 / aspect_ratio) as u32;
        let view_width: f32 = view_height * (image_width as f32 / image_height as f32);
        let viewport_u = Vec3::new(view_width, 0.0, 0.0);
        let viewport_v = Vec3::new(0.0, -view_height, 0.0);
        let pixel_delta_u = viewport_u / image_width as f32;
        let pixel_delta_v = viewport_v / image_height as f32;
        let view_upper_left = center - Vec3::new(0.0, 0.0, focal_length) - viewport_u / 2.0 - viewport_v / 2.0;
        let pixel00_loc = view_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);

        Self {
            aspect_ratio,
            image_width,
            image_height: image_height as f32, // Changed to f32 to match the struct definition
            _pad1: 0.0,
            center,
            _pad2: 0.0,
            pixel00_loc,
            _pad3: 0.0,
            pixel_delta_u,
            _pad4: 0.0,
            pixel_delta_v,
            samples_per_pixel,
            pixels_sample_scale,
            max_depth,
            _pad5: 0.0,
            _pad6: 0.0,
        }
    }

    pub fn update(self: &mut Self, aspect_ratio: f32, image_width: u32) {
        self.aspect_ratio = aspect_ratio;
        self.image_width = image_width;
        self.image_height = image_width as f32 / aspect_ratio;
    }


}

unsafe impl bytemuck::Pod for Camera {}
unsafe impl bytemuck::Zeroable for Camera {}