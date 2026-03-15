# tauri-plugin-apple-iap

Native Apple In-App Purchase plugin for Tauri Apple applications.

`tauri-plugin-apple-iap` provides direct access to StoreKit 2 product loading, purchases, transaction finishing, App Store sync, and current entitlements.

| Platform | Supported |
| -------- | --------- |
| Linux    | -         |
| Windows  | -         |
| macOS    | ✓         |
| Android  | -         |
| iOS      | ✓         |

## Install

_This plugin requires Rust **1.77.2+**._

Add dependency in `src-tauri/Cargo.toml`:

```toml
[dependencies]
tauri-plugin-apple-iap = "1"
```

Or use a Git/path dependency in a monorepo setup:

```toml
[dependencies]
tauri-plugin-apple-iap = { path = "../../../tauri-plugin-apple-iap" }
```

## Setup

### 1. Register the plugin in Rust

`src-tauri/src/lib.rs`:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_apple_iap::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 2. Enable permissions in capability

Add plugin permissions to your capability file, for example `src-tauri/capabilities/default.json`:

```json
{
  "identifier": "default",
  "description": "Default capability",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "apple-iap:default"
  ]
}
```

`apple-iap:default` includes:

- `allow-list-products`
- `allow-purchase-product`
- `allow-finish-transaction`
- `allow-sync-purchases`
- `allow-current-entitlements`

### 3. Apple platform requirements

- Minimum iOS version: `15.0`
- Minimum macOS version: `12.0`
- The app must have valid In-App Purchase products configured in App Store Connect.
- Use Apple Development / Distribution signing as appropriate for device testing or App Store uploads.

## JavaScript usage

No separate guest JS package is required.

```ts
import { invoke } from "@tauri-apps/api/core";

export async function listProducts(productIds: string[]) {
  return invoke("plugin:apple-iap|list_products", { productIds });
}

export async function purchaseProduct(productId: string, appAccountToken?: string) {
  return invoke("plugin:apple-iap|purchase_product", {
    productId,
    appAccountToken
  });
}

export async function finishTransaction(transactionId: string) {
  return invoke("plugin:apple-iap|finish_transaction", { transactionId });
}

export async function syncPurchases() {
  return invoke("plugin:apple-iap|sync_purchases");
}

export async function currentEntitlements(productIds: string[] = []) {
  return invoke("plugin:apple-iap|current_entitlements", { productIds });
}
```

## Command contracts

- `plugin:apple-iap|list_products`
  - args: `{ productIds: string[] }`
- `plugin:apple-iap|purchase_product`
  - args: `{ productId: string; appAccountToken?: string }`
- `plugin:apple-iap|finish_transaction`
  - args: `{ transactionId: string }`
- `plugin:apple-iap|sync_purchases`
  - args: none
- `plugin:apple-iap|current_entitlements`
  - args: `{ productIds?: string[] }`

## Notes

- This plugin was fully developed with the help of AI.
- This plugin is focused on StoreKit 2 for iOS and macOS only.
- It returns verified transaction JWS payloads so your backend can validate purchases with the App Store Server API.

## License

MIT or Apache-2.0, where applicable.
