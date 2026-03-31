fn main() {
    #[cfg(target_os = "macos")]
    {
        let plist_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("Info.plist");
        if plist_path.exists() {
            println!(
                "cargo:rustc-link-arg=-Wl,-sectcreate,__TEXT,__info_plist,{}",
                plist_path.display()
            );
        }
    }
}
