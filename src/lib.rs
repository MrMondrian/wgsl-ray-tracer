use std::borrow::Cow;
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::{
    event::*,
    event_loop::EventLoop,
    window::Window,
};
use wgpu::util::DeviceExt;
pub mod camera;
use crate::camera::Camera;
pub mod hitable;
use crate::hitable::*;
use nalgebra::base::{Vector3,Vector4, Matrix4};
#[cfg(target_arch = "wasm32")]
use wasm_bindgen::prelude::*;
use log::*;


struct GpuInfo<'a> {
    surface: wgpu::Surface<'a>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: winit::dpi::PhysicalSize<u32>,
    render_pipeline: wgpu::RenderPipeline,
    camera: Camera,
    camera_buffer: wgpu::Buffer,
    vertex_buffer: wgpu::Buffer,
    camera_bind_group: wgpu::BindGroup,
    prev_pixels_bind_group: wgpu::BindGroup,
    hitable_list_bind_group: wgpu::BindGroup,
    need_redraw: bool,
    #[allow(dead_code)]
    window: &'a Window,
}

impl<'a> GpuInfo<'a> {
    async fn new(window: &'a Window, hitable_list: Vec<Hitable>) -> GpuInfo<'a> {
        info!("Initializing GPU");
        let mut size = window.inner_size();
        size.width = size.width.max(1);
        size.height = size.height.max(1);

        info!("Creating instance");
        let instance = wgpu::Instance::default();

        info!("Creating surface");
        let surface = instance.create_surface(window).unwrap();
        info!("Requesting adapter");
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                // Request an adapter which can render to our surface
                compatible_surface: Some(&surface),
            })
            .await
            .expect("Failed to find an appropriate adapter");

        
        
        info!("Requesting device");
        // Create the logical device and command queue
        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: None,
                    required_features: wgpu::Features::empty(),
                    // Make sure we use the texture resolution limits from the adapter, so we can support images the size of the swapchain.
                    required_limits: wgpu::Limits {
                        max_storage_buffer_binding_size: 512_u32 << 20,
                        ..Default::default()
                    },
                    memory_hints: wgpu::MemoryHints::MemoryUsage,
                },
                None,
            )
            .await
            .expect("Failed to create device");

        let config = surface
            .get_default_config(&adapter, size.width, size.height)
            .unwrap();
        surface.configure(&device, &config);


        let vertex_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("Vertex Buffer"),
                contents: bytemuck::cast_slice(VERTICES),
                usage: wgpu::BufferUsages::VERTEX,
            }
        );

        let camera = Camera::new(config.width, config.height as f32, Vector3::<f32>::zeros(), Matrix4::<f32>::identity());
        let camera_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("Camera Buffer"),
                contents: bytemuck::cast_slice(&[camera]),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            }
        );
        let camera_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                }
            ],
            label: Some("camera_bind_group_layout"),
        });

        let camera_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            layout: &camera_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer: &camera_buffer,
                        offset: 0,
                        size: None,
                    }),
                }
            ],
            label: Some("camera_bind_group"),
        });

        
        let hitable_list_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("Hitable List Buffer"),
                contents: bytemuck::cast_slice(hitable_list.as_slice()),
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            }
        );

        let hitable_list_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                }
            ],
            label: Some("hitable_list_bind_group_layout"),
        });

        let hitable_list_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            layout: &hitable_list_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer: &hitable_list_buffer,
                        offset: 0,
                        size: None,
                    }),
                }
            ],
            label: Some("hitable_list_bind_group"),
        });


        let monitor_size = window.current_monitor();
        let prev_pixels = match monitor_size {
            Some(monitor) => {
                let physical_size = monitor.size();
                vec![Vector4::<f32>::zeros(); physical_size.width as usize * physical_size.height as usize]
            }
            None => {
                vec![Vector4::<f32>::zeros(); size.width as usize * size.height as usize]
            }
        };
        let prev_pixels_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("Previous Pixels Buffer"),
                contents: bytemuck::cast_slice(prev_pixels.as_slice()),
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            }
        );

        let prev_pixels_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                }
            ],
            label: Some("prev_pixels_bind_group_layout"),
        });

        let prev_pixels_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            layout: &prev_pixels_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer: &prev_pixels_buffer,
                        offset: 0,
                        size: None,
                    }),
                }
            ],
            label: Some("prev_pixels_bind_group"),
        });        


        // Load the shaders from disk
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: None,
            source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(include_str!("shader.wgsl"))),
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[
                &camera_bind_group_layout,
                &hitable_list_bind_group_layout,
                &prev_pixels_bind_group_layout,
            ],
            push_constant_ranges: &[],
        });

        let swapchain_capabilities = surface.get_capabilities(&adapter);
        let swapchain_format = swapchain_capabilities.formats[0];

        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: None,
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                buffers: &[Vertex::desc()],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                compilation_options: Default::default(),
                targets: &[Some(swapchain_format.into())],
            }),
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        return Self {
            surface,
            device,
            queue,
            config,
            size,
            render_pipeline,
            camera,
            camera_buffer,
            vertex_buffer,
            camera_bind_group,
            hitable_list_bind_group,
            prev_pixels_bind_group,
            need_redraw: true,
            window,
        };
    }

    fn render(&mut self) -> Result<(), wgpu::SurfaceError> {

        if self.camera.iteration > 50 {
            return Ok(());
        }

        let frame = self.surface
            .get_current_texture()
            .expect("Failed to acquire next swap chain texture");
        let view = frame
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder =
            self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });
        self.set_encoder(&mut encoder, &view);
        let buffer: wgpu::CommandBuffer = encoder.finish();
        self.queue.submit(Some(buffer));
        frame.present();
        self.camera.iteration += 1;
        self.queue.write_buffer(&self.camera_buffer, 0, bytemuck::cast_slice(&[self.camera]));
        self.window.request_redraw();
        Ok(())
    }

    fn set_encoder(&self, encoder: &mut wgpu::CommandEncoder, view: &wgpu::TextureView) {
        let mut rpass =
            encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
        rpass.set_pipeline(&self.render_pipeline);
        rpass.set_bind_group(0, &self.camera_bind_group, &[]);
        rpass.set_bind_group(1, &self.hitable_list_bind_group, &[]);
        rpass.set_bind_group(2, &self.prev_pixels_bind_group, &[]);
        rpass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
        rpass.draw(0..VERTICES.len() as u32, 0..1);
    }

    fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        self.size = new_size;
        self.config.width = new_size.width;
        self.config.height = new_size.height;
        self.surface.configure(&self.device, &self.config);
        self.camera = Camera::new(self.config.width, self.config.height as f32, self.camera.center, self.camera.rotation);
        self.queue.write_buffer(&self.camera_buffer, 0, bytemuck::cast_slice(&[self.camera]));
    }

    fn handle_key(&mut self, event: &KeyEvent) {
        let speed = 0.1;
        let rotation3x3 = self.camera.rotation.fixed_view::<3, 3>(0, 0).clone();
        match event.physical_key {
            PhysicalKey::Code(KeyCode::KeyW) => {
                let move_local = Vector3::new(0.0, 0.0, -speed);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyS) => {
                // self.camera.center += Vector3::new(0.0, 0.0, speed);
                let move_local = Vector3::new(0.0, 0.0, speed);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyA) => {
                // self.camera.center += Vector3::new(-speed, 0.0, 0.0);
                let move_local = Vector3::new(-speed, 0.0, 0.0);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyD) => {
                // self.camera.center += Vector3::new(speed, 0.0, 0.0);
                let move_local = Vector3::new(speed, 0.0, 0.0);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyQ) => {
                // self.camera.center += Vector3::new(0.0, speed, 0.0);
                let move_local = Vector3::new(0.0, speed, 0.0);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyE) => {
                // self.camera.center += Vector3::new(0.0, -speed, 0.0);
                let move_local = Vector3::new(0.0, -speed, 0.0);
                let move_global = rotation3x3 * move_local;
                self.camera.center += move_global;
            }
            PhysicalKey::Code(KeyCode::KeyJ) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::y_axis(), 0.1);
            }
            PhysicalKey::Code(KeyCode::KeyL) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::y_axis(), -0.1);
            }
            PhysicalKey::Code(KeyCode::KeyI) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::x_axis(), 0.1);
            }
            PhysicalKey::Code(KeyCode::KeyK) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::x_axis(), -0.1);
            }
            PhysicalKey::Code(KeyCode::KeyU) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::z_axis(), 0.1);
            }
            PhysicalKey::Code(KeyCode::KeyO) => {
                self.camera.rotation = self.camera.rotation * Matrix4::from_axis_angle(&Vector3::z_axis(), -0.1);
            }
            PhysicalKey::Code(KeyCode::Space) => {
                self.camera.center = Vector3::zeros();
                self.camera.rotation = Matrix4::identity();
            }
            _ => {}
        }
        self.camera = Camera::new(self.config.width, self.config.height as f32, self.camera.center, self.camera.rotation);
        self.queue.write_buffer(&self.camera_buffer, 0, bytemuck::cast_slice(&[self.camera]));
        self.need_redraw = true;
        self.window.request_redraw();
    }   

 
}

async fn run(hitable_list: Vec<Hitable>) {
    info!("Running");
    let event_loop = EventLoop::new().unwrap();
    #[allow(unused_mut)]
    let mut builder = winit::window::WindowBuilder::new();
        // .with_inner_size(winit::dpi::LogicalSize::new(1280.0, 720.0));
    #[cfg(target_arch = "wasm32")]
    {
        info!("Setting canvas");
        use wasm_bindgen::JsCast;
        use winit::platform::web::WindowBuilderExtWebSys;
        let canvas = web_sys::window()
            .unwrap()
            .document()
            .unwrap()
            .get_element_by_id("canvas")
            .unwrap()
            .dyn_into::<web_sys::HtmlCanvasElement>()
            .unwrap();
        builder = builder.with_canvas(Some(canvas));
    }
    info!("Building window");
    let window = builder.build(&event_loop).unwrap();
    info!("Creating GPU info");
    let mut gpu_info = GpuInfo::new(&window, hitable_list).await;

    #[cfg(target_arch = "wasm32")]
    {
        // Winit prevents sizing with CSS, so we have to set
        // the size manually when on web.
        info!("Setting window size");
        use winit::dpi::PhysicalSize;
        let _ = window.request_inner_size(PhysicalSize::new(450, 400));

        use winit::platform::web::WindowExtWebSys;
        web_sys::window()
            .and_then(|win| win.document())
            .and_then(|doc| {
                let dst = doc.get_element_by_id("ray-tracer")?;
                let canvas = web_sys::Element::from(window.canvas()?);
                dst.append_child(&canvas).ok()?;
                Some(())
            })
            .expect("Couldn't append canvas to document body.");
    }
    info!("Starting event loop");
    event_loop
        .run(move |event, target| {
            // Have the closure take ownership of the resources.
            // `event_loop.run` never returns, therefore we must do this to ensure
            // the resources are properly cleaned up.
            let _ = &gpu_info;

            if let Event::WindowEvent {
                window_id: _,
                event,
            } = event
            {
                match event {
                    WindowEvent::Resized(new_size) => {
                        info!("Resized to {:?}", new_size);
                        gpu_info.resize(new_size);
                    }
                    WindowEvent::RedrawRequested => {
                        info!("Redraw requested");
                        gpu_info.render().unwrap();
                    }
                    WindowEvent::CloseRequested => target.exit(),
                    WindowEvent::KeyboardInput { event, .. } => {
                        info!("Keyboard input");
                        gpu_info.handle_key(&event);
                    }
                    _ => {}
                };
            }
        })
        .unwrap();

}

#[cfg_attr(target_arch="wasm32", wasm_bindgen(start))]
pub fn ray_tracer() {

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

    #[cfg(target_arch = "wasm32")]
    {
        console_log::init().expect("could not initialize logger");
        wasm_bindgen_futures::spawn_local(run(hitable_list));
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        env_logger::init();
        pollster::block_on(run(hitable_list));
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex {
    position: [f32; 2],
    tex_coords: [f32; 2], // NEW!
}


impl Vertex {
    fn desc() -> wgpu::VertexBufferLayout<'static> {
        use std::mem;
        wgpu::VertexBufferLayout {
            array_stride: mem::size_of::<Vertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x2,
                },
                wgpu::VertexAttribute {
                    offset: mem::size_of::<[f32; 2]>() as wgpu::BufferAddress,
                    shader_location: 1,
                    format: wgpu::VertexFormat::Float32x2, // NEW!
                },
            ]
        }
    }
}

const VERTICES: &[Vertex] = &[
    Vertex {
        position: [-1.0, 1.0],
        tex_coords: [0.0, 0.0],
    },
    Vertex {
        position: [-1.0, -1.0],
        tex_coords: [0.0, 1.0],
    },
    Vertex {
        position: [1.0, -1.0],
        tex_coords: [1.0, 1.0],
    },
    Vertex {
        position: [-1.0, 1.0],
        tex_coords: [0.0, 0.0],
    },
    Vertex {
        position: [1.0, -1.0],
        tex_coords: [1.0, 1.0],
    },
    Vertex {
        position: [1.0, 1.0],
        tex_coords: [1.0, 0.0],
    },
];