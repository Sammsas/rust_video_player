fn main() {
    #[cfg(target_os = "windows")]
    {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("assets/app.ico");
        res.set("FileDescription", "Rust Video Player");
        res.set("ProductName", "Rust Video Player");
        res.set("CompanyName", "Your Company");
        res.set("LegalCopyright", "Copyright © 2026");
        res.set("OriginalFilename", "RustVideoPlayer.exe");
        res.set("InternalName", "RustVideoPlayer");
        res.set("FileVersion", "0.3.2");
        res.set("ProductVersion", "0.3.2");
        res.compile().expect("Windows resource 编译失败，请确认 assets/app.ico 存在");
    }
}
