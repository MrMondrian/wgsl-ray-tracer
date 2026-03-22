use nalgebra::Vector3;
use crate::camera::Camera;

pub fn apply_move(camera: &mut Camera, move_global: Vector3<f32>) {
    let center_len = camera.center.norm();
    if center_len < 1e-6 {
        return;
    }
    let radial_dir = camera.center / center_len;
    let radial = move_global.dot(&radial_dir);
    let transverse = move_global - radial * radial_dir;
    camera.l += radial;
    camera.center += transverse;
    let new_len = camera.center.norm();
    if new_len > 1e-6 {
        camera.center = camera.center / new_len * camera.l.abs().max(1.0);
    }
}
