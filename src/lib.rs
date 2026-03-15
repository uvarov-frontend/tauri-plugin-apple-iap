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
            macos::current_entitlements
        ]);
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
