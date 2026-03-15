use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListProductsArgs {
    pub product_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurchaseProductArgs {
    pub product_id: String,
    pub app_account_token: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinishTransactionArgs {
    pub transaction_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CurrentEntitlementsArgs {
    pub product_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleIapProductPayload {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub display_price: String,
    pub price: String,
    pub currency_code: String,
    pub r#type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleIapPurchasePayload {
    pub status: String,
    pub transaction_id: Option<String>,
    pub original_transaction_id: Option<String>,
    pub product_id: Option<String>,
    pub environment: Option<String>,
    pub signed_transaction_info: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleIapEntitlementPayload {
    pub transaction_id: String,
    pub original_transaction_id: Option<String>,
    pub product_id: String,
    pub environment: Option<String>,
    pub signed_transaction_info: String,
}
