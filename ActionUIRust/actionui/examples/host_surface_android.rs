// A HostSurface client in Rust on Android: wgpu draws into the element named "demo.rust" of the
// ActionUI add-on test app (ActionUIAndroid/addon-testapp), on the element's native window. The
// background shifts color over time, and the finger leaves dots where it drags.
//
// On Android, ActionUI is the Kotlin library, so this is a shared library, not a program: the app
// loads it (System.loadLibrary("host_surface_android")) and calls the JNI function below on its main
// thread, which binds the delegate. Build (see BUILD_GUIDE.md, Android):
//   ACTIONUI_HOSTSURFACE_LIB_DIR=<folder of libactionui_hostsurface.so for arm64-v8a> \
//   cargo build -p actionui --example host_surface_android --features host-surface,wgpu \
//       --target aarch64-linux-android

// The library is empty elsewhere, so `cargo test` on macOS and Linux builds it without Android's libraries.
#![cfg(target_os = "android")]

use std::collections::HashMap;
use std::ffi::c_void;

use actionui::host_surface::wgpu_surface::{self, NextFrame};
use actionui::host_surface::{self, InputEvent, InputKind, SurfaceDelegate, SurfaceId, SurfaceInfo};

/// The most dots kept; older ones go first.
const MAX_DOTS: usize = 400;

const SHADER: &str = r#"
struct Screen { size: vec2<f32>, scale: f32, unused: f32 };
@group(0) @binding(0) var<uniform> screen: Screen;

struct Out { @builtin(position) position: vec4<f32>, @location(0) local: vec2<f32>, @location(1) color: vec4<f32> };

@vertex
fn vertex(@builtin(vertex_index) index: u32, @location(0) center: vec2<f32>, @location(1) radius: f32,
          @location(2) color: vec4<f32>) -> Out {
    var corners = array<vec2<f32>, 6>(vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0),
                                      vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0));
    let corner = corners[index];
    // Points to pixels, then to clip space (y down in points, up in clip space).
    let pixel = (center + corner * radius) * screen.scale;
    var out: Out;
    out.position = vec4(pixel.x / screen.size.x * 2.0 - 1.0, 1.0 - pixel.y / screen.size.y * 2.0, 0.0, 1.0);
    out.local = corner;
    out.color = color;
    return out;
}

@fragment
fn fragment(in: Out) -> @location(0) vec4<f32> {
    if dot(in.local, in.local) > 1.0 { discard; }
    return in.color;
}
"#;

struct Gpu {
    instance: wgpu::Instance,
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: Option<(wgpu::TextureFormat, wgpu::RenderPipeline)>,
}

impl Gpu {
    fn new(instance: wgpu::Instance, surface: &wgpu::Surface<'static>) -> Option<Gpu> {
        let options = wgpu::RequestAdapterOptions { compatible_surface: Some(surface), ..Default::default() };
        let adapter = pollster::block_on(instance.request_adapter(&options)).ok()?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu_surface::device_descriptor(&adapter))).ok()?;
        Some(Gpu { instance, adapter, device, queue, pipeline: None })
    }

    fn pipeline(&mut self, format: wgpu::TextureFormat) -> &wgpu::RenderPipeline {
        if self.pipeline.as_ref().is_none_or(|(made_for, _)| *made_for != format) {
            let module = self.device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("dots"),
                source: wgpu::ShaderSource::Wgsl(SHADER.into()),
            });
            let dots = wgpu::VertexBufferLayout {
                array_stride: 7 * 4,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32, 2 => Float32x4],
            };
            let pipeline = self.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("dots"),
                layout: None,
                vertex: wgpu::VertexState {
                    module: &module,
                    entry_point: Some("vertex"),
                    compilation_options: Default::default(),
                    buffers: &[Some(dots)],
                },
                fragment: Some(wgpu::FragmentState {
                    module: &module,
                    entry_point: Some("fragment"),
                    compilation_options: Default::default(),
                    targets: &[Some(format.into())],
                }),
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                multiview_mask: None,
                cache: None,
            });
            self.pipeline = Some((format, pipeline));
        }
        &self.pipeline.as_ref().expect("made above").1
    }
}

struct Canvas {
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    info: SurfaceInfo,
    suspended: bool,
}

#[derive(Default)]
struct RustCanvas {
    gpu: Option<Gpu>,
    canvases: HashMap<SurfaceId, Canvas>,
    /// x, y (points), radius (points), color.
    dots: Vec<[f32; 7]>,
}

impl RustCanvas {
    fn configure(&mut self, info: &SurfaceInfo) {
        let (Some(gpu), Some(canvas)) = (&self.gpu, self.canvases.get_mut(&info.id)) else {
            return;
        };
        canvas.info = info.clone();
        canvas.config.width = info.width_pixels;
        canvas.config.height = info.height_pixels;
        canvas.surface.configure(&gpu.device, &canvas.config);
    }

    fn draw(&mut self, id: SurfaceId, seconds: f64) {
        let (Some(gpu), Some(canvas)) = (&mut self.gpu, self.canvases.get_mut(&id)) else {
            return;
        };
        if canvas.suspended {
            return;
        }
        let frame = match wgpu_surface::next_frame(&canvas.surface) {
            NextFrame::Draw(frame) => frame,
            NextFrame::Skip => return,
            NextFrame::Reconfigure | NextFrame::Recreate => {
                canvas.surface.configure(&gpu.device, &canvas.config);
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        let phase = (seconds * 0.3).sin() * 0.5 + 0.5;
        let background = wgpu::Color { r: 0.10 + 0.25 * phase, g: 0.12, b: 0.35 - 0.2 * phase, a: 1.0 };
        let screen = [canvas.config.width as f32, canvas.config.height as f32, canvas.info.scale as f32, 0.0];
        let pipeline = gpu.pipeline(canvas.config.format).clone();
        let screen_buffer = buffer(&gpu.device, wgpu::BufferUsages::UNIFORM, &screen);
        let bind_group = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &pipeline.get_bind_group_layout(0),
            entries: &[wgpu::BindGroupEntry { binding: 0, resource: screen_buffer.as_entire_binding() }],
        });
        let dots: Vec<f32> = self.dots.iter().flatten().copied().collect();
        let dot_buffer = (!dots.is_empty()).then(|| buffer(&gpu.device, wgpu::BufferUsages::VERTEX, &dots));
        let mut encoder = gpu.device.create_command_encoder(&Default::default());
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(background), store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            if let Some(dot_buffer) = &dot_buffer {
                pass.set_pipeline(&pipeline);
                pass.set_bind_group(0, &bind_group, &[]);
                pass.set_vertex_buffer(0, dot_buffer.slice(..));
                pass.draw(0..6, 0..self.dots.len() as u32);
            }
        }
        gpu.queue.submit([encoder.finish()]);
        gpu.queue.present(frame);
    }
}

fn buffer(device: &wgpu::Device, usage: wgpu::BufferUsages, values: &[f32]) -> wgpu::Buffer {
    use wgpu::util::DeviceExt;
    let bytes: Vec<u8> = values.iter().flat_map(|value| value.to_ne_bytes()).collect();
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: &bytes, usage })
}

impl SurfaceDelegate for RustCanvas {
    fn created(&mut self, info: &SurfaceInfo) {
        let instance = match &self.gpu {
            Some(gpu) => gpu.instance.clone(),
            None => wgpu::Instance::new(wgpu::InstanceDescriptor {
                backends: wgpu::Backends::VULKAN | wgpu::Backends::GL,
                ..wgpu::InstanceDescriptor::new_without_display_handle()
            }),
        };
        // Safety: the surface is dropped in destroyed, before it returns.
        let surface = match unsafe { wgpu_surface::create(&instance, info) } {
            Ok(surface) => surface,
            Err(error) => {
                log(&format!("created: {error}"));
                return;
            }
        };
        if self.gpu.is_none() {
            self.gpu = Gpu::new(instance, &surface);
        }
        let Some(gpu) = &self.gpu else {
            log("created: no wgpu adapter or device");
            return;
        };
        let Some(mut config) = surface.get_default_config(&gpu.adapter, info.width_pixels, info.height_pixels) else {
            log("created: the surface does not work with this adapter");
            return;
        };
        config.format = config.format.remove_srgb_suffix();
        log(&format!("created {:?} {}x{} px, {:?}", info.id, info.width_pixels, info.height_pixels, gpu.adapter.get_info().backend));
        self.canvases.insert(info.id, Canvas { surface, config, info: info.clone(), suspended: false });
        self.configure(info);
        let _ = info.id.set_continuous(true);
    }

    fn changed(&mut self, info: &SurfaceInfo) {
        log(&format!("changed {:?} {}x{} px", info.id, info.width_pixels, info.height_pixels));
        self.configure(info);
    }

    fn suspended(&mut self, info: &SurfaceInfo) {
        log(&format!("suspended {:?}", info.id));
        if let Some(canvas) = self.canvases.get_mut(&info.id) {
            canvas.suspended = true;
        }
    }

    fn resumed(&mut self, info: &SurfaceInfo) {
        log(&format!("resumed {:?}", info.id));
        if let Some(canvas) = self.canvases.get_mut(&info.id) {
            canvas.suspended = false;
        }
    }

    fn destroyed(&mut self, info: &SurfaceInfo) {
        log(&format!("destroyed {:?}", info.id));
        // Drops the wgpu surface before the native window goes.
        self.canvases.remove(&info.id);
    }

    fn frame(&mut self, surface: SurfaceId, timestamp: f64) {
        self.draw(surface, timestamp);
    }

    fn input(&mut self, _surface: SurfaceId, event: &InputEvent) {
        if matches!(event.kind, InputKind::PointerDown | InputKind::PointerDrag) {
            if self.dots.len() == MAX_DOTS {
                self.dots.remove(0);
            }
            let hue = (self.dots.len() % 3) as f32;
            self.dots.push([event.x as f32, event.y as f32, 10.0, 1.0, 0.75 + 0.1 * hue, 0.3, 1.0]);
        }
    }
}

fn log(message: &str) {
    #[link(name = "log")]
    unsafe extern "C" {
        fn __android_log_write(priority: i32, tag: *const std::ffi::c_char, text: *const std::ffi::c_char) -> i32;
    }
    if let Ok(text) = std::ffi::CString::new(message) {
        // ANDROID_LOG_INFO.
        unsafe { __android_log_write(4, c"HostSurfaceRust".as_ptr(), text.as_ptr()) };
    }
}

/// `HostSurfaceRustDemo.nativeBind()` in the add-on test app: binds the delegate to "demo.rust".
/// Called on the main thread. Returns JNI_TRUE (1) when bound.
#[unsafe(no_mangle)]
pub extern "C" fn Java_com_abracode_actionui_addontest_HostSurfaceRustDemo_nativeBind(
    _env: *mut c_void,
    _class: *mut c_void,
) -> u8 {
    match host_surface::set_delegate("demo.rust", RustCanvas::default()) {
        Ok(()) => 1,
        Err(error) => {
            log(&format!("bind: {error}"));
            0
        }
    }
}
