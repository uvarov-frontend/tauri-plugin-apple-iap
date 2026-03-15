import Foundation
import StoreKit
import SwiftRs

private struct ListProductsArgs: Decodable, Sendable {
  let productIds: [String]
}

private struct PurchaseProductArgs: Decodable, Sendable {
  let productId: String
  let appAccountToken: String?
}

private struct FinishTransactionArgs: Decodable, Sendable {
  let transactionId: String
}

private struct CurrentEntitlementsArgs: Decodable, Sendable {
  let productIds: [String]
}

private struct AppleIapProductPayload: Encodable, Sendable {
  let id: String
  let displayName: String
  let description: String
  let displayPrice: String
  let price: String
  let currencyCode: String
  let type: String
}

private struct AppleIapPurchasePayload: Encodable, Sendable {
  let status: String
  let transactionId: String?
  let originalTransactionId: String?
  let productId: String?
  let environment: String?
  let signedTransactionInfo: String?
}

private struct AppleIapEntitlementPayload: Encodable, Sendable {
  let transactionId: String
  let originalTransactionId: String?
  let productId: String
  let environment: String?
  let signedTransactionInfo: String
}

private struct SuccessEnvelope<T: Encodable>: Encodable {
  let data: T
}

private struct ErrorEnvelope: Encodable {
  let error: String
}

private final class BlockingResultBox<T: Sendable>: @unchecked Sendable {
  private let semaphore = DispatchSemaphore(value: 0)
  private var result: Result<T, Error>?

  func resolve(_ value: Result<T, Error>) {
    result = value
    semaphore.signal()
  }

  func wait() throws -> T {
    semaphore.wait()
    return try result!.get()
  }
}

@available(macOS 12.0, *)
private actor AppleIapRuntime {
  static let shared = AppleIapRuntime()

  private var cachedProducts: [String: Product] = [:]
  private var pendingTransactions: [String: Transaction] = [:]

  func listProducts(productIds: [String]) async throws -> [AppleIapProductPayload] {
    let normalizedIds = Array(
      Set(
        productIds
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    )
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
        if #available(macOS 13.0, *) {
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
      return AppleIapPurchasePayload(
        status: "pending",
        transactionId: nil,
        originalTransactionId: nil,
        productId: nil,
        environment: nil,
        signedTransactionInfo: nil
      )
    case .userCancelled:
      return AppleIapPurchasePayload(
        status: "cancelled",
        transactionId: nil,
        originalTransactionId: nil,
        productId: nil,
        environment: nil,
        signedTransactionInfo: nil
      )
    @unknown default:
      return AppleIapPurchasePayload(
        status: "unknown",
        transactionId: nil,
        originalTransactionId: nil,
        productId: nil,
        environment: nil,
        signedTransactionInfo: nil
      )
    }
  }

  func finishTransaction(transactionId: String) async throws -> Bool {
    let normalizedId = transactionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedId.isEmpty else { return false }
    guard let transaction = pendingTransactions.removeValue(forKey: normalizedId) else { return false }
    await transaction.finish()
    return true
  }

  func syncPurchases() async throws -> Bool {
    try await AppStore.sync()
    return true
  }

  func currentEntitlements(productIds: [String]) async -> [AppleIapEntitlementPayload] {
    let filter = Set(
      productIds
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
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
      if #available(macOS 13.0, *) {
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

private func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
  let box = BlockingResultBox<T>()

  Task {
    do {
      box.resolve(.success(try await operation()))
    } catch {
      box.resolve(.failure(error))
    }
  }

  return try box.wait()
}

private func decode<T: Decodable>(_ payload: SRString, as type: T.Type) throws -> T {
  let data = Data(payload.toString().utf8)
  return try JSONDecoder().decode(type, from: data)
}

private func encodeSuccess<T: Encodable>(_ value: T) -> SRString {
  do {
    let data = try JSONEncoder().encode(SuccessEnvelope(data: value))
    return SRString(String(decoding: data, as: UTF8.self))
  } catch {
    return encodeError(error)
  }
}

private func encodeError(_ error: Error) -> SRString {
  let message = error.localizedDescription
  let envelope = ErrorEnvelope(error: message)
  let data = (try? JSONEncoder().encode(envelope)) ?? Data("{\"error\":\"failed to encode error response\"}".utf8)
  return SRString(String(decoding: data, as: UTF8.self))
}

@_cdecl("apple_iap_macos_list_products")
public func appleIapMacOsListProducts(_ payload: SRString) -> SRString {
  do {
    let args = try decode(payload, as: ListProductsArgs.self)
    let products = try runBlocking {
      try await AppleIapRuntime.shared.listProducts(productIds: args.productIds)
    }
    return encodeSuccess(products)
  } catch {
    return encodeError(error)
  }
}

@_cdecl("apple_iap_macos_purchase_product")
public func appleIapMacOsPurchaseProduct(_ payload: SRString) -> SRString {
  do {
    let args = try decode(payload, as: PurchaseProductArgs.self)
    let purchase = try runBlocking {
      try await AppleIapRuntime.shared.purchase(
        productId: args.productId,
        appAccountToken: args.appAccountToken
      )
    }
    return encodeSuccess(purchase)
  } catch {
    return encodeError(error)
  }
}

@_cdecl("apple_iap_macos_finish_transaction")
public func appleIapMacOsFinishTransaction(_ payload: SRString) -> SRString {
  do {
    let args = try decode(payload, as: FinishTransactionArgs.self)
    let didFinish = try runBlocking {
      try await AppleIapRuntime.shared.finishTransaction(transactionId: args.transactionId)
    }
    return encodeSuccess(didFinish)
  } catch {
    return encodeError(error)
  }
}

@_cdecl("apple_iap_macos_sync_purchases")
public func appleIapMacOsSyncPurchases() -> SRString {
  do {
    let didSync = try runBlocking {
      try await AppleIapRuntime.shared.syncPurchases()
    }
    return encodeSuccess(didSync)
  } catch {
    return encodeError(error)
  }
}

@_cdecl("apple_iap_macos_current_entitlements")
public func appleIapMacOsCurrentEntitlements(_ payload: SRString) -> SRString {
  do {
    let args = try decode(payload, as: CurrentEntitlementsArgs.self)
    let entitlements = try runBlocking {
      await AppleIapRuntime.shared.currentEntitlements(productIds: args.productIds)
    }
    return encodeSuccess(entitlements)
  } catch {
    return encodeError(error)
  }
}
