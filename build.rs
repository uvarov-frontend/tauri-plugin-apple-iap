const COMMANDS: &[&str] = &[
    "list_products",
    "purchase_product",
    "finish_transaction",
    "sync_purchases",
    "current_entitlements",
];

#[cfg(target_os = "macos")]
fn link_macos_package() {
    use std::path::PathBuf;

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("missing CARGO_MANIFEST_DIR"));
    let package_dir = manifest_dir.join("macos");
    let sdk_root = std::env::var_os("SDKROOT");

    std::env::remove_var("SDKROOT");
    swift_rs::SwiftLinker::new("12.0")
        .with_ios("15.0")
        .with_package("AppleIapMacOS", &package_dir)
        .link();
    if let Some(root) = sdk_root {
        std::env::set_var("SDKROOT", root);
    }

    println!("cargo:rerun-if-changed={}", package_dir.display());
}

fn main() {
    #[cfg(target_os = "macos")]
    link_macos_package();

    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
