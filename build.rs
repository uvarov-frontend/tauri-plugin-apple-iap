const COMMANDS: &[&str] = &["list_products", "purchase_product", "finish_transaction", "sync_purchases", "current_entitlements"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
