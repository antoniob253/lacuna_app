import Foundation
import RevenueCat
import Observation

@Observable
@MainActor
final class StoreManager: NSObject, PurchasesDelegate {
    static let shared = StoreManager()
    static let entitlementID = "Lacuna +"
    static let apiKey = "appl_DsUPCPuPNrVvkfBsNfXYGNblWAr"

    /// DEBUG-only override so the developer can exercise Pro-gated flows
    /// (send, camera, unlimited capsules) without paying themselves.
    /// This constant is wrapped in `#if DEBUG` so it physically does not
    /// exist in TestFlight or App Store builds — there is no risk of
    /// shipping a Pro bypass to real users.
    #if DEBUG
    private static let debugProOverride = true
    #endif

    var isPro = false
    var proProduct: StoreProduct?
    var purchaseInProgress = false
    private var currentOffering: Offering?

    private override init() {
        super.init()
        #if DEBUG
        if Self.debugProOverride { isPro = true }
        #endif
    }

    // MARK: - Configuration (call once at app launch)

    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        Purchases.shared.delegate = self
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
            // Get the first available package's product (our lifetime IAP)
            proProduct = currentOffering?.availablePackages.first?.storeProduct
        } catch {
            // Products unavailable — user stays on free tier
        }
    }

    // MARK: - Check Entitlement

    func checkEntitlement() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateProStatus(from: customerInfo)
        } catch {
            // Can't verify — keep current state
        }
    }

    // MARK: - Purchase

    func purchase() async -> Bool {
        guard let package = currentOffering?.availablePackages.first else { return false }
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
            if userCancelled { return false }
            updateProStatus(from: customerInfo)
            return isPro
        } catch {
            return false
        }
    }

    // MARK: - Restore

    enum RestoreResult {
        case restored
        case noPurchaseFound
        case cancelled
        case failed
    }

    func restore() async -> RestoreResult {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateProStatus(from: customerInfo)
            return isPro ? .restored : .noPurchaseFound
        } catch let error as NSError {
            // Detect user cancellation across Apple error domains
            if error is CancellationError { return .cancelled }
            let domain = error.domain
            if domain == "AMSErrorDomain" || domain == "ASDErrorDomain" { return .cancelled }
            if domain == "SKErrorDomain" && error.code == 2 { return .cancelled }
            if error.localizedDescription.localizedCaseInsensitiveContains("cancel") { return .cancelled }
            return .failed
        }
    }

    // MARK: - Transaction Listener (RevenueCat delegate)

    func listenForTransactions() {
        // RevenueCat handles this via PurchasesDelegate — nothing to start manually.
        // The delegate method purchases(_:receivedUpdated:) is called automatically.
    }

    // PurchasesDelegate — called whenever customer info changes
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.updateProStatus(from: customerInfo)
        }
    }

    // MARK: - Limit Checking (unchanged)

    func canCreate(type: CapsuleType, activeSealedText: Int, activeSealedPhoto: Int, activeSealedVoice: Int) -> Bool {
        if isPro { return true }
        switch type {
        case .text: return activeSealedText < 3
        case .photo: return activeSealedPhoto < 1
        case .voice: return activeSealedVoice < 1
        }
    }

    var canSend: Bool { isPro }
    var canUseCamera: Bool { isPro }

    // MARK: - Private

    private func updateProStatus(from customerInfo: CustomerInfo) {
        let real = customerInfo.entitlements[Self.entitlementID]?.isActive == true
        #if DEBUG
        isPro = real || Self.debugProOverride
        #else
        isPro = real
        #endif
    }
}
