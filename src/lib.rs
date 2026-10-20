use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "macos")]
mod models;

#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_apple_iap);

/// The App Store product sheet exists only on iOS; other platforms reject the call.
#[cfg(not(target_os = "ios"))]
#[tauri::command]
fn show_store_product() -> Result<(), String> {
    Err("unsupported".into())
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    #[allow(unused_mut)]
    let mut builder = Builder::new("apple-iap");

    #[cfg(target_os = "macos")]
    {
        builder = builder.invoke_handler(tauri::generate_handler![
            macos::list_products,
            macos::purchase_product,
            macos::finish_transaction,
            macos::sync_purchases,
            macos::current_entitlements,
            show_store_product
        ]);
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        builder = builder.invoke_handler(tauri::generate_handler![show_store_product]);
    }

    builder
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_apple_iap)?;
            }
            Ok(())
        })
        .build()
}
