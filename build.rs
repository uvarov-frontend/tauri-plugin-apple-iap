const COMMANDS: &[&str] = &[
    "list_products",
    "purchase_product",
    "finish_transaction",
    "sync_purchases",
    "current_entitlements",
];

#[cfg(target_os = "macos")]
fn macos_swift_runtime_paths() -> Vec<std::path::PathBuf> {
    let swift_binary = std::process::Command::new("xcrun")
        .args(["--find", "swift"])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .filter(|path| !path.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/usr/bin/swift"));
    let mut paths = Vec::new();

    if let Some(toolchain_usr_dir) = swift_binary.parent().and_then(std::path::Path::parent) {
        let toolchain_runtime = toolchain_usr_dir.join("lib").join("swift").join("macosx");
        if toolchain_runtime.exists() {
            paths.push(toolchain_runtime);
        }
    }

    let system_runtime = std::path::PathBuf::from("/usr/lib/swift");
    if system_runtime.exists() {
        paths.push(system_runtime);
    }

    paths.sort();
    paths.dedup();
    paths
}

#[cfg(target_os = "macos")]
fn emit_macos_swift_runtime_metadata() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let paths = macos_swift_runtime_paths();
    if paths.is_empty() {
        return;
    }

    let encoded = paths
        .iter()
        .map(|path| path.display().to_string())
        .collect::<Vec<_>>()
        .join(";");

    println!("cargo:swift_runtime_paths={encoded}");
}

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
    emit_macos_swift_runtime_metadata();

    #[cfg(target_os = "macos")]
    link_macos_package();

    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
