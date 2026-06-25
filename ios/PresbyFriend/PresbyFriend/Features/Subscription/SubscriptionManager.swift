import StoreKit
import SwiftUI
import Combine

final class SubscriptionManager: ObservableObject {
    @Published var isProSubscriber: Bool = false
    @Published var products: [Product] = []
    @Published var dailyUseCount: Int = 0

    private let productIDs = [
        "com.presbyfriend.pro.monthly",
        "com.presbyfriend.pro.yearly",
    ]
    private let freeLimitPerDay = 10
    private let defaults = UserDefaults.standard

    init() {
        dailyUseCount = defaults.integer(forKey: "dailyUseCount")
        checkIfNewDay()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {}
    }

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    isProSubscriber = true
                    await transaction.finish()
                    return true
                }
            default:
                break
            }
        } catch {}
        return false
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        var restored = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if productIDs.contains(transaction.productID) {
                    isProSubscriber = true
                    restored = true
                }
            }
        }
        return restored
    }

    func incrementUse() -> Bool {
        checkIfNewDay()
        dailyUseCount += 1
        defaults.set(dailyUseCount, forKey: "dailyUseCount")

        if !isProSubscriber && dailyUseCount > freeLimitPerDay {
            return false
        }
        return true
    }

    private func checkIfNewDay() {
        let lastDate = defaults.object(forKey: "lastUseDate") as? Date ?? .distantPast
        if !Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            dailyUseCount = 0
            defaults.set(0, forKey: "dailyUseCount")
        }
        defaults.set(Date(), forKey: "lastUseDate")
    }
}
