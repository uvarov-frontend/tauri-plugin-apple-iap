use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_apple_iap);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("apple-iap")
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_apple_iap)?;
            }
            Ok(())
        })
        .build()
}
