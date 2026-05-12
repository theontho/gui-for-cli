use crate::app::ImGuiApp;
use anyhow::{Context, Result};
use glium::Surface;
use glutin::{
    config::ConfigTemplateBuilder,
    context::ContextAttributesBuilder,
    display::GetGlDisplay,
    prelude::*,
    surface::{SurfaceAttributesBuilder, WindowSurface},
};
use imgui::{FontConfig, FontId, FontSource};
use imgui_winit_support::winit::{dpi::LogicalSize, event_loop::EventLoop};
use raw_window_handle::HasWindowHandle;
use std::num::NonZeroU32;
use std::time::Instant;
use winit::{
    event::{Event, WindowEvent},
    window::{Window, WindowAttributes},
};

pub fn run_window(mut app: ImGuiApp) -> Result<()> {
    let (event_loop, window, display) = create_window(app.title())?;
    let (mut platform, mut imgui, fonts) = imgui_init(&window);
    let mut renderer = imgui_glium_renderer::Renderer::new(&mut imgui, &display)
        .context("initialize ImGui glium renderer")?;
    let mut last_frame = Instant::now();

    #[allow(deprecated)]
    event_loop
        .run(move |event, window_target| match event {
            Event::NewEvents(_) => {
                let now = Instant::now();
                imgui.io_mut().update_delta_time(now - last_frame);
                last_frame = now;
            }
            Event::AboutToWait => {
                if let Err(error) = platform.prepare_frame(imgui.io_mut(), &window) {
                    eprintln!("gui-for-cli-imgui: prepare frame failed: {error}");
                    window_target.exit();
                    return;
                }
                window.request_redraw();
            }
            Event::WindowEvent {
                event: WindowEvent::RedrawRequested,
                ..
            } => {
                let ui = imgui.frame();
                app.render(ui, &fonts);

                let mut target = display.draw();
                target.clear_color_srgb(0.94, 0.95, 0.97, 1.0);
                platform.prepare_render(ui, &window);
                let draw_data = imgui.render();
                if let Err(error) = renderer.render(&mut target, draw_data) {
                    eprintln!("gui-for-cli-imgui: render failed: {error}");
                    window_target.exit();
                    return;
                }
                if let Err(error) = target.finish() {
                    eprintln!("gui-for-cli-imgui: swap buffers failed: {error}");
                    window_target.exit();
                }
            }
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => {
                app.cancel_all_running();
                window_target.exit();
            }
            Event::WindowEvent {
                event: WindowEvent::Resized(new_size),
                ..
            } => {
                if new_size.width > 0 && new_size.height > 0 {
                    display.resize((new_size.width, new_size.height));
                }
                platform.handle_event(imgui.io_mut(), &window, &event);
            }
            event => platform.handle_event(imgui.io_mut(), &window, &event),
        })
        .context("run ImGui event loop")
}

pub(crate) struct ImGuiFonts {
    pub(crate) section: FontId,
}

fn create_window(title: &str) -> Result<(EventLoop<()>, Window, glium::Display<WindowSurface>)> {
    let event_loop = EventLoop::new().context("create event loop")?;
    let window_attributes = WindowAttributes::default()
        .with_title(format!("{title} - ImGui"))
        .with_inner_size(LogicalSize::new(1180, 760))
        .with_min_inner_size(LogicalSize::new(760, 520));

    let (window, config) = glutin_winit::DisplayBuilder::new()
        .with_window_attributes(Some(window_attributes))
        .build(&event_loop, ConfigTemplateBuilder::new(), |mut configs| {
            configs.next().expect("OpenGL config")
        })
        .map_err(|error| anyhow::anyhow!("create OpenGL window: {error}"))?;
    let window = window.ok_or_else(|| anyhow::anyhow!("OpenGL window was not created"))?;
    let raw_window_handle = window.window_handle().context("window handle")?.as_raw();
    let context_attributes = ContextAttributesBuilder::new().build(Some(raw_window_handle));
    let context = unsafe {
        config
            .display()
            .create_context(&config, &context_attributes)
            .map_err(|error| anyhow::anyhow!("create OpenGL context: {error}"))?
    };
    let size = window.inner_size();
    let surface_attributes = SurfaceAttributesBuilder::<WindowSurface>::new().build(
        raw_window_handle,
        NonZeroU32::new(size.width.max(1)).expect("nonzero width"),
        NonZeroU32::new(size.height.max(1)).expect("nonzero height"),
    );
    let surface = unsafe {
        config
            .display()
            .create_window_surface(&config, &surface_attributes)
            .map_err(|error| anyhow::anyhow!("create OpenGL surface: {error}"))?
    };
    let context = context
        .make_current(&surface)
        .map_err(|error| anyhow::anyhow!("make OpenGL context current: {error}"))?;
    let display = glium::Display::from_context_surface(context, surface)
        .map_err(|error| anyhow::anyhow!("create glium display: {error}"))?;
    Ok((event_loop, window, display))
}

fn imgui_init(
    window: &Window,
) -> (
    imgui_winit_support::WinitPlatform,
    imgui::Context,
    ImGuiFonts,
) {
    let mut imgui = imgui::Context::create();
    imgui.set_ini_filename(None);
    let mut platform = imgui_winit_support::WinitPlatform::new(&mut imgui);
    platform.attach_window(
        imgui.io_mut(),
        window,
        imgui_winit_support::HiDpiMode::Default,
    );
    let section = {
        let fonts = imgui.fonts();
        fonts.add_font(&[FontSource::DefaultFontData {
            config: Some(FontConfig {
                size_pixels: 17.0,
                ..FontConfig::default()
            }),
        }]);
        fonts.add_font(&[FontSource::DefaultFontData {
            config: Some(FontConfig {
                size_pixels: 21.0,
                ..FontConfig::default()
            }),
        }])
    };
    (platform, imgui, ImGuiFonts { section })
}
