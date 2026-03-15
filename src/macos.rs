use serde::de::DeserializeOwned;
use swift_rs::{swift, SRString};
use tauri::async_runtime::spawn_blocking;

use crate::models::{
    AppleIapEntitlementPayload, AppleIapProductPayload, AppleIapPurchasePayload,
    CurrentEntitlementsArgs, FinishTransactionArgs, ListProductsArgs, PurchaseProductArgs,
};

swift!(fn apple_iap_macos_list_products(payload: &SRString) -> SRString);
swift!(fn apple_iap_macos_purchase_product(payload: &SRString) -> SRString);
swift!(fn apple_iap_macos_finish_transaction(payload: &SRString) -> SRString);
swift!(fn apple_iap_macos_sync_purchases() -> SRString);
swift!(fn apple_iap_macos_current_entitlements(payload: &SRString) -> SRString);

#[derive(Debug, serde::Deserialize)]
#[serde(untagged)]
enum BridgeResponse<T> {
    Success { data: T },
    Error { error: String },
}

fn decode_response<T: DeserializeOwned>(response: SRString) -> Result<T, String> {
    let raw = response.as_str();
    let parsed: BridgeResponse<T> = serde_json::from_str(raw)
        .map_err(|error| format!("invalid macOS bridge response: {error}"))?;

    match parsed {
        BridgeResponse::Success { data } => Ok(data),
        BridgeResponse::Error { error } => Err(error),
    }
}

fn invoke_with_payload<T, P>(
    payload: &P,
    call: unsafe fn(&SRString) -> SRString,
) -> Result<T, String>
where
    T: DeserializeOwned,
    P: serde::Serialize,
{
    let payload = serde_json::to_string(payload)
        .map_err(|error| format!("failed to encode macOS request: {error}"))?;
    let payload: SRString = payload.as_str().into();
    decode_response(unsafe { call(&payload) })
}

fn invoke_without_payload<T>(call: unsafe fn() -> SRString) -> Result<T, String>
where
    T: DeserializeOwned,
{
    decode_response(unsafe { call() })
}

async fn run_blocking<T, F>(work: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    spawn_blocking(work)
        .await
        .map_err(|error| format!("failed to join macOS StoreKit task: {error}"))?
}

#[tauri::command]
pub async fn list_products(
    product_ids: Vec<String>,
) -> Result<Vec<AppleIapProductPayload>, String> {
    run_blocking(move || {
        invoke_with_payload(
            &ListProductsArgs { product_ids },
            apple_iap_macos_list_products,
        )
    })
    .await
}

#[tauri::command]
pub async fn purchase_product(
    product_id: String,
    app_account_token: Option<String>,
) -> Result<AppleIapPurchasePayload, String> {
    run_blocking(move || {
        invoke_with_payload(
            &PurchaseProductArgs {
                product_id,
                app_account_token,
            },
            apple_iap_macos_purchase_product,
        )
    })
    .await
}

#[tauri::command]
pub async fn finish_transaction(transaction_id: String) -> Result<bool, String> {
    run_blocking(move || {
        invoke_with_payload(
            &FinishTransactionArgs { transaction_id },
            apple_iap_macos_finish_transaction,
        )
    })
    .await
}

#[tauri::command]
pub async fn sync_purchases() -> Result<(), String> {
    run_blocking(|| invoke_without_payload::<bool>(apple_iap_macos_sync_purchases))
        .await
        .map(|_| ())
}

#[tauri::command]
pub async fn current_entitlements(
    product_ids: Vec<String>,
) -> Result<Vec<AppleIapEntitlementPayload>, String> {
    run_blocking(move || {
        invoke_with_payload(
            &CurrentEntitlementsArgs { product_ids },
            apple_iap_macos_current_entitlements,
        )
    })
    .await
}
