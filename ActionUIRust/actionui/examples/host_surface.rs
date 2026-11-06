// A sketch pad: ActionUI draws the window and its controls, and this program draws the canvas
// itself, with wgpu, into the window's HostSurface element. Drag to draw; the controls set the
// color and the brush size, clear the canvas, and hide it (the drawing survives); Backspace
// removes the last stroke.
//
//   cargo run --example host_surface --features host-surface,wgpu
//
// SKETCH_DEMO=1 starts with a sample stroke, for a screenshot without drawing by hand.
// SKETCH_VERBOSE=1 prints the surface events.
//
// It shows the HostSurface client contract: build the renderer on "created", resize on
// "changed", draw only when asked for a frame, stop while suspended, and drop everything on
// "destroyed". It draws on the main thread, from frame callbacks, and only when something
// changed (the element's "continuous" is false).

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use actionui::host_surface::wgpu_surface::{self, NextFrame};
use actionui::host_surface::{Cursor, InputEvent, InputKind, SurfaceDelegate, SurfaceHandle, SurfaceId, SurfaceInfo};
use actionui::{App, Window};

const UI: &str = include_str!("host_surface.json");
const SURFACE_NAME: &str = "sketch.canvas";

// The element IDs in the JSON.
const COLOR: i64 = 10;
const SIZE: i64 = 11;
const STATUS: i64 = 14;
const HIDE: i64 = 13;
const CANVAS: i64 = 20;

const BACKGROUND: wgpu::Color = wgpu::Color { r: 0.98, g: 0.97, b: 0.94, a: 1.0 };

/// One round dab of paint, in points from the canvas's top-left corner.
#[derive(Clone, Copy)]
struct Dab {
    x: f32,
    y: f32,
    radius: f32,
    color: [f32; 4],
}

/// The drawing and the brush, shared by the canvas and the controls.
struct Sketch {
    strokes: Vec<Vec<Dab>>,
    color: [f32; 4],
    radius: f32,
    /// The last point of the stroke in progress.
    last: Option<(f32, f32)>,
    window: Option<Window>,
    /// The live canvases, to ask for a frame when the drawing changes.
    surfaces: Vec<SurfaceId>,
}

impl Sketch {
    fn changed(&self) {
        for surface in &self.surfaces {
            surface.request_frame();
        }
        if let Some(window) = &self.window {
            let count = self.strokes.len();
            let text = match count {
                0 => "No strokes".to_string(),
                1 => "1 stroke".to_string(),
                _ => format!("{count} strokes"),
            };
            let _ = window.set_string(STATUS, &text);
        }
    }

    /// Dabs from the last point to (x, y), close enough to look like a line.
    fn stroke_to(&mut self, x: f32, y: f32) {
        let (from_x, from_y) = self.last.unwrap_or((x, y));
        let distance = ((x - from_x).powi(2) + (y - from_y).powi(2)).sqrt();
        let step = (self.radius * 0.35).max(0.5);
        let count = (distance / step).ceil().max(1.0) as usize;
        let dab = Dab { x, y, radius: self.radius, color: self.color };
        let Some(stroke) = self.strokes.last_mut() else {
            return;
        };
        for index in 1..=count {
            let t = index as f32 / count as f32;
            stroke.push(Dab { x: from_x + (x - from_x) * t, y: from_y + (y - from_y) * t, ..dab });
        }
        self.last = Some((x, y));
    }
}

fn color_named(name: &str) -> [f32; 4] {
    match name {
        "red" => [0.85, 0.18, 0.16, 1.0],
        "green" => [0.16, 0.62, 0.30, 1.0],
        "blue" => [0.15, 0.36, 0.85, 1.0],
        _ => [0.12, 0.12, 0.14, 1.0],
    }
}

// MARK: - The renderer

const SHADER: &str = r#"
struct Screen { size: vec2f, scale: f32, pad: f32 };
@group(0) @binding(0) var<uniform> screen: Screen;

struct Out {
    @builtin(position) position: vec4f,
    @location(0) local: vec2f,
    @location(1) color: vec4f,
};

// Six corners of a square around each dab; its center and radius are in points.
@vertex fn vs(@builtin(vertex_index) index: u32,
              @location(0) center: vec2f, @location(1) radius: f32, @location(2) color: vec4f) -> Out {
    let corners = array(vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0),
                        vec2f(-1.0, 1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0));
    let corner = corners[index];
    let pixel = (center + corner * radius) * screen.scale;
    var out: Out;
    out.position = vec4f(pixel.x / screen.size.x * 2.0 - 1.0, 1.0 - pixel.y / screen.size.y * 2.0, 0.0, 1.0);
    out.local = corner;
    out.color = color;
    return out;
}

@fragment fn fs(input: Out) -> @location(0) vec4f {
    let distance = length(input.local);
    if (distance > 1.0) {
        discard;
    }
    // A soft edge one pixel wide, whatever the radius.
    let edge = clamp((1.0 - distance) / max(fwidth(distance), 0.0001), 0.0, 1.0);
    return vec4f(input.color.rgb, input.color.a * edge);
}
"#;

/// What every canvas shares: the device and the pipeline.
struct Gpu {
    instance: wgpu::Instance,
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: Option<(wgpu::TextureFormat, wgpu::RenderPipeline)>,
}

impl Gpu {
    fn new() -> Gpu {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            // Metal on macOS; on Linux, where the canvas is a frame sink, whatever renders offscreen.
            backends: if cfg!(target_os = "macos") { wgpu::Backends::METAL } else { wgpu::Backends::PRIMARY | wgpu::Backends::GL },
            ..wgpu::InstanceDescriptor::new_without_display_handle()
        });
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default()))
            .expect("no wgpu adapter");
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu_surface::device_descriptor(&adapter)))
            .expect("no wgpu device");
        Gpu { instance, adapter, device, queue, pipeline: None }
    }

    fn pipeline(&mut self, format: wgpu::TextureFormat) -> &wgpu::RenderPipeline {
        if self.pipeline.as_ref().is_none_or(|(made_for, _)| *made_for != format) {
            let module = self.device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("sketch"),
                source: wgpu::ShaderSource::Wgsl(SHADER.into()),
            });
            let dab_layout = wgpu::VertexBufferLayout {
                array_stride: 7 * 4,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32, 2 => Float32x4],
            };
            let pipeline = self.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("sketch"),
                layout: None,
                vertex: wgpu::VertexState {
                    module: &module,
                    entry_point: Some("vs"),
                    compilation_options: Default::default(),
                    buffers: &[Some(dab_layout)],
                },
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                fragment: Some(wgpu::FragmentState {
                    module: &module,
                    entry_point: Some("fs"),
                    compilation_options: Default::default(),
                    targets: &[Some(wgpu::ColorTargetState {
                        format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                }),
                multiview_mask: None,
                cache: None,
            });
            self.pipeline = Some((format, pipeline));
        }
        &self.pipeline.as_ref().expect("made above").1
    }
}

/// Where a canvas draws: a wgpu surface on the native handle (macOS), or an offscreen texture whose
/// pixels go to a frame sink (Linux).
enum Target {
    Native(wgpu::Surface<'static>),
    Sink(wgpu_surface::FrameSink),
}

/// One canvas: a wgpu surface (or frame sink) on one HostSurface.
struct Canvas {
    target: Target,
    config: wgpu::SurfaceConfiguration,
    /// The element's surface, to create the wgpu surface again if it is lost.
    info: SurfaceInfo,
    scale: f32,
    suspended: bool,
}

impl Canvas {
    fn configure(&mut self, gpu: &Gpu, info: &SurfaceInfo) {
        self.info = info.clone();
        self.scale = info.scale as f32;
        self.config.width = info.width_pixels;
        self.config.height = info.height_pixels;
        match &mut self.target {
            Target::Native(surface) => surface.configure(&gpu.device, &self.config),
            Target::Sink(sink) => sink.configure(&gpu.device, info.width_pixels, info.height_pixels),
        }
    }

    fn draw(&mut self, gpu: &mut Gpu, sketch: &Sketch) {
        let (frame, view) = match &mut self.target {
            Target::Sink(sink) => match sink.view() {
                Some(view) => (None, view),
                None => return,
            },
            Target::Native(surface) => match wgpu_surface::next_frame(surface) {
                NextFrame::Draw(frame) => {
                    let view = frame.texture.create_view(&Default::default());
                    (Some(frame), view)
                }
                NextFrame::Skip => return,
                NextFrame::Reconfigure => {
                    surface.configure(&gpu.device, &self.config);
                    self.info.id.request_frame();
                    return;
                }
                NextFrame::Recreate => {
                    // Safety: the info is the live surface's; the old wgpu surface is replaced here.
                    if let Ok(new_surface) = unsafe { wgpu_surface::create(&gpu.instance, &self.info) } {
                        *surface = new_surface;
                        surface.configure(&gpu.device, &self.config);
                        self.info.id.request_frame();
                    }
                    return;
                }
            },
        };
        let dabs: Vec<f32> = sketch
            .strokes
            .iter()
            .flatten()
            .flat_map(|dab| [dab.x, dab.y, dab.radius, dab.color[0], dab.color[1], dab.color[2], dab.color[3]])
            .collect();
        let screen = [self.config.width as f32, self.config.height as f32, self.scale, 0.0];
        let screen_buffer = buffer(&gpu.device, wgpu::BufferUsages::UNIFORM, &screen);
        let dab_buffer = (!dabs.is_empty()).then(|| buffer(&gpu.device, wgpu::BufferUsages::VERTEX, &dabs));
        let format = self.config.format;
        let pipeline = gpu.pipeline(format).clone();
        let bind_group = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &pipeline.get_bind_group_layout(0),
            entries: &[wgpu::BindGroupEntry { binding: 0, resource: screen_buffer.as_entire_binding() }],
        });
        let mut encoder = gpu.device.create_command_encoder(&Default::default());
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(BACKGROUND), store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            if let Some(dab_buffer) = &dab_buffer {
                pass.set_pipeline(&pipeline);
                pass.set_bind_group(0, &bind_group, &[]);
                pass.set_vertex_buffer(0, dab_buffer.slice(..));
                pass.draw(0..6, 0..(dabs.len() / 7) as u32);
            }
        }
        match (&mut self.target, frame) {
            (Target::Sink(sink), _) => {
                sink.present(&gpu.device, &gpu.queue, encoder);
            }
            (Target::Native(_), Some(frame)) => {
                gpu.queue.submit([encoder.finish()]);
                gpu.queue.present(frame);
            }
            (Target::Native(_), None) => {}
        }
    }
}

fn buffer(device: &wgpu::Device, usage: wgpu::BufferUsages, values: &[f32]) -> wgpu::Buffer {
    use wgpu::util::DeviceExt;
    let bytes: Vec<u8> = values.iter().flat_map(|value| value.to_ne_bytes()).collect();
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: &bytes, usage })
}

// MARK: - The delegate

struct SketchCanvas {
    sketch: Rc<RefCell<Sketch>>,
    gpu: Option<Gpu>,
    canvases: HashMap<SurfaceId, Canvas>,
    verbose: bool,
}

impl SketchCanvas {
    fn note(&self, event: &str, info: &SurfaceInfo) {
        if self.verbose {
            eprintln!("[sketch] {event} {:?} {}x{} px at scale {}", info.id, info.width_pixels, info.height_pixels, info.scale);
        }
    }
}

impl SurfaceDelegate for SketchCanvas {
    fn created(&mut self, info: &SurfaceInfo) {
        self.note("created", info);
        let gpu = self.gpu.get_or_insert_with(Gpu::new);
        let (target, config) = if info.handle == SurfaceHandle::FrameSink {
            let sink = match wgpu_surface::FrameSink::new(info) {
                Ok(sink) => sink,
                Err(error) => {
                    eprintln!("{error}");
                    return;
                }
            };
            let config = wgpu::SurfaceConfiguration {
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
                format: wgpu_surface::FrameSink::FORMAT,
                width: info.width_pixels,
                height: info.height_pixels,
                present_mode: wgpu::PresentMode::Fifo,
                desired_maximum_frame_latency: 2,
                alpha_mode: wgpu::CompositeAlphaMode::Opaque,
                view_formats: vec![],
                color_space: Default::default(),
            };
            (Target::Sink(sink), config)
        } else {
            // Safety: the surface is dropped in destroyed, before it returns.
            let surface = match unsafe { wgpu_surface::create(&gpu.instance, info) } {
                Ok(surface) => surface,
                Err(error) => {
                    eprintln!("{error}");
                    return;
                }
            };
            let Some(mut config) = surface.get_default_config(&gpu.adapter, info.width_pixels, info.height_pixels) else {
                eprintln!("the canvas surface does not work with this adapter");
                return;
            };
            // The colors below are sRGB values; a non-sRGB format shows them as written.
            config.format = config.format.remove_srgb_suffix();
            (Target::Native(surface), config)
        };
        let mut canvas = Canvas { target, config, info: info.clone(), scale: info.scale as f32, suspended: false };
        canvas.configure(gpu, info);
        self.canvases.insert(info.id, canvas);
        self.sketch.borrow_mut().surfaces.push(info.id);
        let _ = info.id.set_cursor(Cursor::Crosshair);
        info.id.request_frame();
    }

    fn changed(&mut self, info: &SurfaceInfo) {
        self.note("changed", info);
        if let (Some(gpu), Some(canvas)) = (&self.gpu, self.canvases.get_mut(&info.id)) {
            canvas.configure(gpu, info);
            info.id.request_frame();
        }
    }

    fn suspended(&mut self, info: &SurfaceInfo) {
        self.note("suspended", info);
        if let Some(canvas) = self.canvases.get_mut(&info.id) {
            canvas.suspended = true;
        }
    }

    fn resumed(&mut self, info: &SurfaceInfo) {
        self.note("resumed", info);
        if let Some(canvas) = self.canvases.get_mut(&info.id) {
            canvas.suspended = false;
            info.id.request_frame();
        }
    }

    fn destroyed(&mut self, info: &SurfaceInfo) {
        self.note("destroyed", info);
        // Drops the wgpu surface while the layer is still valid.
        self.canvases.remove(&info.id);
        self.sketch.borrow_mut().surfaces.retain(|surface| *surface != info.id);
    }

    fn frame(&mut self, surface: SurfaceId, _timestamp: f64) {
        let (Some(gpu), Some(canvas)) = (self.gpu.as_mut(), self.canvases.get_mut(&surface)) else {
            return;
        };
        if !canvas.suspended {
            canvas.draw(gpu, &self.sketch.borrow());
        }
    }

    fn input(&mut self, _surface: SurfaceId, event: &InputEvent) {
        let mut sketch = self.sketch.borrow_mut();
        match event.kind {
            InputKind::PointerDown if event.button == 0 => {
                sketch.strokes.push(Vec::new());
                sketch.last = None;
                sketch.stroke_to(event.x as f32, event.y as f32);
            }
            InputKind::PointerDrag if sketch.last.is_some() => {
                sketch.stroke_to(event.x as f32, event.y as f32);
            }
            InputKind::PointerUp | InputKind::PointerCancel => {
                sketch.last = None;
            }
            InputKind::KeyDown if event.code == "Backspace" || event.code == "Delete" => {
                sketch.strokes.pop();
            }
            _ => return,
        }
        sketch.changed();
    }
}

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    if !actionui::running_from_bundle() {
        app.set_name("Sketch")?;
    }
    let sketch = Rc::new(RefCell::new(Sketch {
        strokes: Vec::new(),
        color: color_named("ink"),
        radius: 6.0,
        last: None,
        window: None,
        surfaces: Vec::new(),
    }));
    if std::env::var_os("SKETCH_DEMO").is_some() {
        let mut demo = sketch.borrow_mut();
        demo.strokes.push(Vec::new());
        for step in 0..=120 {
            let t = step as f32 / 120.0;
            let (x, y) = (40.0 + 520.0 * t, 240.0 + 120.0 * (t * std::f32::consts::TAU).sin());
            demo.radius = 4.0 + 10.0 * t;
            demo.stroke_to(x, y);
        }
        demo.last = None;
        demo.radius = 6.0;
    }
    app.set_surface_delegate(SURFACE_NAME, SketchCanvas {
        sketch: sketch.clone(),
        gpu: None,
        canvases: HashMap::new(),
        verbose: std::env::var_os("SKETCH_VERBOSE").is_some(),
    })?;
    let window = app.present_window_from_json(UI, Some("Sketch"))?;
    sketch.borrow_mut().window = Some(window.clone());

    let state = sketch.clone();
    app.on_action("sketch.color", move |action| {
        let name = action.window.get_string(COLOR).ok().flatten().unwrap_or_default();
        state.borrow_mut().color = color_named(&name);
    });
    let state = sketch.clone();
    app.on_action("sketch.size", move |action| {
        if let Ok(Some(size)) = action.window.get_double(SIZE) {
            state.borrow_mut().radius = size as f32;
        }
    });
    let state = sketch.clone();
    app.on_action("sketch.clear", move |_| {
        let mut sketch = state.borrow_mut();
        sketch.strokes.clear();
        sketch.changed();
    });
    app.on_action("sketch.hide", move |action| {
        let hidden = action.window.get_bool(HIDE).ok().flatten().unwrap_or(false);
        let _ = action.window.set_property(CANVAS, "hidden", &hidden);
    });

    app.run()
}
