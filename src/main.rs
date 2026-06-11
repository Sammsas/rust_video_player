#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use anyhow::{anyhow, Context, Result};
use eframe::egui;
use gstreamer as gst;
use gstreamer_app as gst_app;
use gst::prelude::*;
use gst_app::prelude::*;
use std::{fs, path::{Path, PathBuf}, sync::{Arc, mpsc::{self, Receiver, Sender}}, time::{Duration, Instant}};
use url::Url;

const APP_NAME: &str = "Rust Video Player";
const APP_VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() -> eframe::Result<()> {
    setup_embedded_gstreamer();
    gst::init().expect("GStreamer 初始化失败：请确认 exe 同级目录存在 gstreamer/bin 和 gstreamer/lib/gstreamer-1.0，或系统已安装 GStreamer");

    let icon = eframe::icon_data::from_png_bytes(include_bytes!("../assets/app.png")).expect("无法加载内置窗口图标");
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title(format!("{APP_NAME} v{APP_VERSION}"))
            .with_inner_size([980.0, 640.0])
            .with_min_inner_size([720.0, 480.0])
            .with_icon(Arc::new(icon)),
        ..Default::default()
    };
    eframe::run_native(APP_NAME, options, Box::new(|cc| Box::new(VideoPlayerApp::new(cc))))
}

#[derive(Clone)]
struct VideoFrame { width: usize, height: usize, rgba: Vec<u8> }

enum PlayerEvent { Eos, Error(String), StateChanged(String) }

struct VideoPlayerApp {
    player: EmbeddedGstPlayer,
    frame_rx: Receiver<VideoFrame>,
    texture: Option<egui::TextureHandle>,
    selected_path: Option<PathBuf>,
    status: String,
    is_playing: bool,
    is_paused: bool,
    volume: f64,
    duration: u64,
    position: u64,
    seeking_value: u64,
    is_dragging_slider: bool,
    last_tick: Instant,
    last_video_size: Option<(usize, usize)>,
}

impl VideoPlayerApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        cc.egui_ctx.set_visuals(egui::Visuals::dark());
        let (frame_tx, frame_rx) = mpsc::channel::<VideoFrame>();
        let player = EmbeddedGstPlayer::new(frame_tx).expect("无法创建 GStreamer 嵌入式播放器");
        Self { player, frame_rx, texture: None, selected_path: None, status: "请选择一个视频文件".to_owned(), is_playing: false, is_paused: false, volume: 0.8, duration: 0, position: 0, seeking_value: 0, is_dragging_slider: false, last_tick: Instant::now(), last_video_size: None }
    }

    fn open_file(&mut self, path: PathBuf) {
        match self.player.open(&path) {
            Ok(_) => { self.selected_path = Some(path.clone()); self.status = format!("已打开：{}", path.display()); self.is_playing = true; self.is_paused = false; self.position = 0; self.seeking_value = 0; self.texture = None; self.last_video_size = None; }
            Err(err) => self.status = format!("打开失败：{err:#}"),
        }
    }

    fn receive_latest_frame(&mut self, ctx: &egui::Context) {
        let mut latest = None;
        while let Ok(frame) = self.frame_rx.try_recv() { latest = Some(frame); }
        if let Some(frame) = latest {
            let image = egui::ColorImage::from_rgba_unmultiplied([frame.width, frame.height], &frame.rgba);
            match &mut self.texture {
                Some(texture) => texture.set(image, egui::TextureOptions::LINEAR),
                None => self.texture = Some(ctx.load_texture("video-frame", image, egui::TextureOptions::LINEAR)),
            }
            self.last_video_size = Some((frame.width, frame.height));
        }
    }

    fn refresh_state(&mut self) {
        while let Some(event) = self.player.poll_event() {
            match event {
                PlayerEvent::Eos => { self.status = "播放结束".to_owned(); self.is_playing = false; self.is_paused = false; }
                PlayerEvent::Error(msg) => { self.status = format!("播放错误：{msg}"); self.is_playing = false; self.is_paused = false; }
                PlayerEvent::StateChanged(name) => self.status = name,
            }
        }
        if self.last_tick.elapsed() >= Duration::from_millis(200) {
            self.position = self.player.position_seconds();
            self.duration = self.player.duration_seconds().unwrap_or(0);
            if !self.is_dragging_slider { self.seeking_value = self.position; }
            self.last_tick = Instant::now();
        }
    }
}

impl eframe::App for VideoPlayerApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.receive_latest_frame(ctx);
        self.refresh_state();

        egui::TopBottomPanel::top("top_bar").show(ctx, |ui| {
            ui.horizontal_wrapped(|ui| { ui.heading(format!("{APP_NAME} v{APP_VERSION}")); ui.separator(); ui.label("GitHub Actions 自动构建版"); });
        });

        egui::TopBottomPanel::bottom("control_bar").resizable(false).show(ctx, |ui| {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                if ui.button("打开视频").clicked() {
                    if let Some(path) = rfd::FileDialog::new().add_filter("视频文件", &["mp4","mkv","avi","mov","webm","flv","wmv","m4v"]).pick_file() { self.open_file(path); }
                }
                if ui.button("播放").clicked() { match self.player.play() { Ok(_) => { self.is_playing = true; self.is_paused = false; }, Err(err) => self.status = format!("播放失败：{err:#}"), } }
                if ui.button("暂停/继续").clicked() {
                    if self.is_paused { match self.player.play() { Ok(_) => { self.is_paused = false; self.is_playing = true; }, Err(err) => self.status = format!("继续失败：{err:#}"), } }
                    else { match self.player.pause() { Ok(_) => self.is_paused = true, Err(err) => self.status = format!("暂停失败：{err:#}"), } }
                }
                if ui.button("停止").clicked() { match self.player.stop() { Ok(_) => { self.is_playing = false; self.is_paused = false; self.position = 0; self.seeking_value = 0; self.texture = None; }, Err(err) => self.status = format!("停止失败：{err:#}"), } }
                ui.separator();
                let filename = self.selected_path.as_ref().and_then(|p| p.file_name()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "未选择文件".to_owned());
                ui.label(filename);
            });
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                if ui.button("-10s").clicked() { let target = self.position.saturating_sub(10); if self.player.seek_to_seconds(target).is_ok() { self.position = target; self.seeking_value = target; } }
                let max = self.duration.max(1);
                let response = ui.add(egui::Slider::new(&mut self.seeking_value, 0..=max).show_value(false).text("进度"));
                self.is_dragging_slider = response.dragged();
                if response.drag_released() || response.clicked() { if self.player.seek_to_seconds(self.seeking_value).is_ok() { self.position = self.seeking_value; } self.is_dragging_slider = false; }
                if ui.button("+10s").clicked() { let target = if self.duration > 0 { (self.position + 10).min(self.duration) } else { self.position + 10 }; if self.player.seek_to_seconds(target).is_ok() { self.position = target; self.seeking_value = target; } }
                ui.label(format!("{} / {}", format_time(self.position), format_time(self.duration)));
            });
            ui.horizontal(|ui| {
                ui.label("音量"); let old_volume = self.volume; ui.add(egui::Slider::new(&mut self.volume, 0.0..=2.0).show_value(false)); ui.label(format!("{:.0}%", self.volume * 100.0));
                if (old_volume - self.volume).abs() > f64::EPSILON { self.player.set_volume(self.volume); }
                ui.separator(); ui.label(if self.is_paused { "已暂停" } else if self.is_playing { "播放中" } else { "未播放" }); ui.separator(); ui.label(&self.status);
            });
            ui.add_space(8.0);
        });

        egui::CentralPanel::default().show(ctx, |ui| {
            let available = ui.available_size(); let rect = ui.allocate_space(available).1; let painter = ui.painter_at(rect); painter.rect_filled(rect, 0.0, egui::Color32::BLACK);
            if let Some(texture) = &self.texture {
                let (w,h) = self.last_video_size.unwrap_or((16,9)); let video_aspect = w as f32 / h as f32; let area_aspect = rect.width() / rect.height();
                let size = if area_aspect > video_aspect { egui::vec2(rect.height() * video_aspect, rect.height()) } else { egui::vec2(rect.width(), rect.width() / video_aspect) };
                let image_rect = egui::Rect::from_center_size(rect.center(), size);
                painter.image(texture.id(), image_rect, egui::Rect::from_min_max(egui::Pos2::ZERO, egui::pos2(1.0, 1.0)), egui::Color32::WHITE);
            } else {
                painter.text(rect.center(), egui::Align2::CENTER_CENTER, "打开视频后，画面会嵌入显示在这里", egui::FontId::proportional(22.0), egui::Color32::LIGHT_GRAY);
            }
        });
        ctx.request_repaint_after(Duration::from_millis(16));
    }
}

impl Drop for VideoPlayerApp { fn drop(&mut self) { let _ = self.player.stop(); } }

struct EmbeddedGstPlayer { playbin: gst::Element, bus: gst::Bus }

impl EmbeddedGstPlayer {
    fn new(frame_tx: Sender<VideoFrame>) -> Result<Self> {
        let playbin = gst::ElementFactory::make("playbin").name("rust-embedded-video-player").build().context("无法创建 playbin，请确认 GStreamer 插件已安装")?;
        let appsink = gst::ElementFactory::make("appsink").name("video-appsink").build().context("无法创建 appsink，请确认 GStreamer app 插件可用")?.downcast::<gst_app::AppSink>().map_err(|_| anyhow!("video sink 不是 AppSink"))?;
        let caps = gst::Caps::builder("video/x-raw").field("format", "RGBA").build();
        appsink.set_caps(Some(&caps)); appsink.set_property("emit-signals", true); appsink.set_property("sync", true); appsink.set_property("max-buffers", 2u32); appsink.set_property("drop", true);
        appsink.set_callbacks(gst_app::AppSinkCallbacks::builder().new_sample(move |sink| {
            let sample = match sink.pull_sample() { Ok(sample) => sample, Err(_) => return Err(gst::FlowError::Eos) };
            let caps = sample.caps().ok_or(gst::FlowError::Error)?; let structure = caps.structure(0).ok_or(gst::FlowError::Error)?;
            let width = structure.get::<i32>("width").map_err(|_| gst::FlowError::Error)? as usize; let height = structure.get::<i32>("height").map_err(|_| gst::FlowError::Error)? as usize;
            let buffer = sample.buffer().ok_or(gst::FlowError::Error)?; let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?; let data = map.as_slice();
            let expected = width.saturating_mul(height).saturating_mul(4); if data.len() < expected { return Err(gst::FlowError::Error); }
            let _ = frame_tx.send(VideoFrame { width, height, rgba: data[..expected].to_vec() }); Ok(gst::FlowSuccess::Ok)
        }).build());
        playbin.set_property("video-sink", &appsink); playbin.set_property("volume", 0.8f64);
        let bus = playbin.bus().context("无法获取 GStreamer bus")?; Ok(Self { playbin, bus })
    }
    fn open(&self, path: &Path) -> Result<()> { let uri = path_to_uri(path)?; self.stop()?; self.playbin.set_property("uri", &uri); self.play() }
    fn play(&self) -> Result<()> { self.playbin.set_state(gst::State::Playing).context("设置播放状态失败")?; Ok(()) }
    fn pause(&self) -> Result<()> { self.playbin.set_state(gst::State::Paused).context("设置暂停状态失败")?; Ok(()) }
    fn stop(&self) -> Result<()> { self.playbin.set_state(gst::State::Null).context("停止播放失败")?; Ok(()) }
    fn seek_to_seconds(&self, seconds: u64) -> Result<()> { self.playbin.seek_simple(gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT, gst::ClockTime::from_seconds(seconds)).with_context(|| format!("跳转到 {seconds} 秒失败"))?; Ok(()) }
    fn position_seconds(&self) -> u64 { self.playbin.query_position::<gst::ClockTime>().unwrap_or(gst::ClockTime::ZERO).seconds() }
    fn duration_seconds(&self) -> Option<u64> { self.playbin.query_duration::<gst::ClockTime>().map(|t| t.seconds()) }
    fn set_volume(&self, volume: f64) { self.playbin.set_property("volume", volume.clamp(0.0, 2.0)); }
    fn poll_event(&self) -> Option<PlayerEvent> {
        let msg = self.bus.timed_pop(gst::ClockTime::ZERO)?;
        match msg.view() {
            gst::MessageView::Eos(..) => Some(PlayerEvent::Eos),
            gst::MessageView::Error(err) => { let mut message = err.error().to_string(); if let Some(debug) = err.debug() { message.push_str(&format!("\n调试信息：{debug}")); } Some(PlayerEvent::Error(message)) }
            gst::MessageView::StateChanged(state) => { if let Some(src) = msg.src() { if src.name() == "rust-embedded-video-player" { return Some(PlayerEvent::StateChanged(format!("状态：{:?} → {:?}", state.old(), state.current()))); } } None }
            _ => None,
        }
    }
}

fn path_to_uri(path: &Path) -> Result<String> {
    let absolute_path = fs::canonicalize(path).with_context(|| format!("找不到文件：{}", path.display()))?;
    let url = Url::from_file_path(&absolute_path).map_err(|_| anyhow!("无法将文件路径转换为 URI：{}", absolute_path.display()))?;
    Ok(url.to_string())
}

fn format_time(total_seconds: u64) -> String {
    let hours = total_seconds / 3600; let minutes = (total_seconds % 3600) / 60; let seconds = total_seconds % 60;
    if hours > 0 { format!("{:02}:{:02}:{:02}", hours, minutes, seconds) } else { format!("{:02}:{:02}", minutes, seconds) }
}

fn setup_embedded_gstreamer() {
    #[cfg(target_os = "windows")]
    {
        use std::env;
        let exe_path = match env::current_exe() { Ok(path) => path, Err(_) => return };
        let app_dir = match exe_path.parent() { Some(dir) => dir.to_path_buf(), None => return };
        let gst_root = app_dir.join("gstreamer"); let gst_bin = gst_root.join("bin"); let gst_plugins = gst_root.join("lib").join("gstreamer-1.0");
        if gst_bin.exists() && gst_plugins.exists() {
            let old_path = env::var("PATH").unwrap_or_default(); env::set_var("PATH", format!("{};{}", gst_bin.display(), old_path));
            env::set_var("GST_PLUGIN_PATH", &gst_plugins); env::set_var("GST_PLUGIN_SYSTEM_PATH_1_0", &gst_plugins); env::set_var("GST_REGISTRY", app_dir.join("gst-registry.bin"));
        }
    }
}
