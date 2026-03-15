import Foundation
import StoreKit
import Tauri

private struct ListProductsArgs: Decodable {
  let productIds: [String]
}

private struct PurchaseProductArgs: Decodable {
  let productId: String
  let appAccountToken: String?
}

private struct FinishTransactionArgs: Decodable {
  let transactionId: String
}

private struct CurrentEntitlementsArgs: Decodable {
  let productIds: [String]
}

struct AppleIapProductPayload: Encodable {
  let id: String
  let displayName: String
  let description: String
  let displayPrice: String
  let price: String
  let currencyCode: String
  let type: String
}

struct AppleIapPurchasePayload: Encodable {
  let status: String
  let transactionId: String?
  let originalTransactionId: String?
  let productId: String?
  let environment: String?
  let signedTransactionInfo: String?
}

struct AppleIapEntitlementPayload: Encodable {
  let transactionId: String
  let originalTransactionId: String?
  let productId: String
  let environment: String?
  let signedTransactionInfo: String
}

@available(iOS 15.0, *)
actor AppleIapRuntime {
  static let shared = AppleIapRuntime()

  private var cachedProducts: [String: Product] = [:]
  private var pendingTransactions: [String: Transaction] = [:]

  func listProducts(productIds: [String]) async throws -> [AppleIapProductPayload] {
    let normalizedIds = Array(Set(productIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    guard !normalizedIds.isEmpty else { return [] }

    let products = try await Product.products(for: normalizedIds)
    for product in products {
      cachedProducts[product.id] = product
    }

    let order = Dictionary(uniqueKeysWithValues: normalizedIds.enumerated().map { ($0.element, $0.offset) })

    return products
      .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
      .map(Self.serializeProduct)
  }

  func purchase(productId: String, appAccountToken: String?) async throws -> AppleIapPurchasePayload {
    let product = try await getProduct(productId: productId)
    let result: Product.PurchaseResult

    if let rawToken = appAccountToken?.trimmingCharacters(in: .whitespacesAndNewlines), !rawToken.isEmpty {
      guard let token = UUID(uuidString: rawToken) else {
        throw AppleIapError.invalidAppAccountToken
      }
      result = try await product.purchase(options: [.appAccountToken(token)])
    } else {
      result = try await product.purchase()
    }

    switch result {
    case .success(let verificationResult):
      switch verificationResult {
      case .verified(let transaction):
        let transactionId = String(transaction.id)
        pendingTransactions[transactionId] = transaction
        let environment: String?
        if #available(iOS 16.0, *) {
          environment = String(describing: transaction.environment)
        } else {
          environment = nil
        }
        return AppleIapPurchasePayload(
          status: "success",
          transactionId: transactionId,
          originalTransactionId: String(transaction.originalID),
          productId: transaction.productID,
          environment: environment,
          signedTransactionInfo: verificationResult.jwsRepresentation
        )
      case .unverified(_, let error):
        throw AppleIapError.unverified(error.localizedDescription)
      }
    case .pending:
      return AppleIapPurchasePayload(status: "pending", transactionId: nil, originalTransactionId: nil, productId: nil, environment: nil, signedTransactionInfo: nil)
    case .userCancelled:
      return AppleIapPurchasePayload(status: "cancelled", transactionId: nil, originalTransactionId: nil, productId: nil, environment: nil, signedTransactionInfo: nil)
    @unknown default:
      return AppleIapPurchasePayload(status: "unknown", transactionId: nil, originalTransactionId: nil, productId: nil, environment: nil, signedTransactionInfo: nil)
    }
  }

  func finishTransaction(transactionId: String) async throws -> Bool {
    let normalizedId = transactionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedId.isEmpty else { return false }
    guard let transaction = pendingTransactions.removeValue(forKey: normalizedId) else { return false }
    await transaction.finish()
    return true
  }

  func syncPurchases() async throws {
    try await AppStore.sync()
  }

  func currentEntitlements(productIds: [String]) async -> [AppleIapEntitlementPayload] {
    let filter = Set(productIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    var payloads: [AppleIapEntitlementPayload] = []

    for await verificationResult in Transaction.currentEntitlements {
      guard case .verified(let transaction) = verificationResult else {
        continue
      }

      if !filter.isEmpty && !filter.contains(transaction.productID) {
        continue
      }

      if transaction.revocationDate != nil {
        continue
      }

      let environment: String?
      if #available(iOS 16.0, *) {
        environment = String(describing: transaction.environment)
      } else {
        environment = nil
      }

      payloads.append(
        AppleIapEntitlementPayload(
          transactionId: String(transaction.id),
          originalTransactionId: String(transaction.originalID),
          productId: transaction.productID,
          environment: environment,
          signedTransactionInfo: verificationResult.jwsRepresentation
        )
      )
    }

    return payloads.sorted { lhs, rhs in
      if lhs.productId == rhs.productId {
        return lhs.transactionId > rhs.transactionId
      }
      return lhs.productId < rhs.productId
    }
  }

  private func getProduct(productId: String) async throws -> Product {
    let normalizedId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedId.isEmpty else {
      throw AppleIapError.productIdRequired
    }

    if let cached = cachedProducts[normalizedId] {
      return cached
    }

    let products = try await Product.products(for: [normalizedId])
    guard let product = products.first else {
      throw AppleIapError.productNotFound(normalizedId)
    }

    cachedProducts[normalizedId] = product
    return product
  }

  private static func serializeProduct(_ product: Product) -> AppleIapProductPayload {
    AppleIapProductPayload(
      id: product.id,
      displayName: product.displayName,
      description: product.description,
      displayPrice: product.displayPrice,
      price: NSDecimalNumber(decimal: product.price).stringValue,
      currencyCode: product.priceFormatStyle.currencyCode,
      type: String(describing: product.type)
    )
  }
}

private enum AppleIapError: LocalizedError {
  case productIdRequired
  case productNotFound(String)
  case invalidAppAccountToken
  case unverified(String)

  var errorDescription: String? {
    switch self {
    case .productIdRequired:
      return "productId is required"
    case .productNotFound(let productId):
      return "Product not found: \(productId)"
    case .invalidAppAccountToken:
      return "appAccountToken must be a valid UUID"
    case .unverified(let message):
      return "Apple transaction is unverified: \(message)"
    }
  }
}

class AppleIapPlugin: Plugin {
  @objc public func listProducts(_ invoke: Invoke) {
    guard #available(iOS 15.0, *) else {
      invoke.reject("Apple In-App Purchases require iOS 15 or later")
      return
    }

    Task {
      do {
        let args = try invoke.parseArgs(ListProductsArgs.self)
        invoke.resolve(try await AppleIapRuntime.shared.listProducts(productIds: args.productIds))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func purchaseProduct(_ invoke: Invoke) {
    guard #available(iOS 15.0, *) else {
      invoke.reject("Apple In-App Purchases require iOS 15 or later")
      return
    }

    Task {
      do {
        let args = try invoke.parseArgs(PurchaseProductArgs.self)
        invoke.resolve(try await AppleIapRuntime.shared.purchase(productId: args.productId, appAccountToken: args.appAccountToken))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func finishTransaction(_ invoke: Invoke) {
    guard #available(iOS 15.0, *) else {
      invoke.reject("Apple In-App Purchases require iOS 15 or later")
      return
    }

    Task {
      do {
        let args = try invoke.parseArgs(FinishTransactionArgs.self)
        invoke.resolve(try await AppleIapRuntime.shared.finishTransaction(transactionId: args.transactionId))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func syncPurchases(_ invoke: Invoke) {
    guard #available(iOS 15.0, *) else {
      invoke.reject("Apple In-App Purchases require iOS 15 or later")
      return
    }

    Task {
      do {
        try await AppleIapRuntime.shared.syncPurchases()
        invoke.resolve()
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }

  @objc public func currentEntitlements(_ invoke: Invoke) {
    guard #available(iOS 15.0, *) else {
      invoke.reject("Apple In-App Purchases require iOS 15 or later")
      return
    }

    Task {
      do {
        let args = try invoke.parseArgs(CurrentEntitlementsArgs.self)
        invoke.resolve(await AppleIapRuntime.shared.currentEntitlements(productIds: args.productIds))
      } catch {
        invoke.reject(error.localizedDescription)
      }
    }
  }
}

extension AppleIapPlugin: @unchecked Sendable {}

@_cdecl("init_plugin_apple_iap")
func initPlugin() -> Plugin {
  AppleIapPlugin()
}
