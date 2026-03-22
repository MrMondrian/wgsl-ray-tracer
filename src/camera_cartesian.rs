use nalgebra::Vector3;
use crate::camera::Camera;

pub fn apply_move(camera: &mut Camera, move_global: Vector3<f32>) {
    camera.center += move_global;
}
