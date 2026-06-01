import SwiftUI
import SwiftData

@main
struct LacunaApp: App {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.automatic.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var notificationManager = NotificationManager.shared
    @State private var storeManager = StoreManager.shared
    @State private var showOnboarding = false
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Capsule.self])
            let config = ModelConfiguration(
                "Capsules",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(
                for: schema,
                migrationPlan: CapsuleMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // Configure RevenueCat — must happen once, before any purchase calls
        StoreManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .overlay { FloatingParticlesView().ignoresSafeArea() }
                .environment(notificationManager)
                .environment(storeManager)
                .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
                .onAppear {
                    RatingManager.recordSession()

                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    } else {
                        notificationManager.requestPermission()

                        // Trigger 5: 5th app launch
                        if RatingManager.sessionCount == 5 {
                            // Small delay so the UI settles first
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                RatingManager.requestIfEligible()
                            }
                        }
                    }
                }
                .task {
                    await storeManager.loadProducts()
                    await storeManager.checkEntitlement()
                    storeManager.listenForTransactions()

                    // Best-effort: clean up our own expired transport records in the
                    // CloudKit public DB. Runs detached so launch isn't blocked.
                    Task.detached(priority: .background) {
                        await CapsuleTransport.sweepExpiredRecords()
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                    guard let scene = notification.object as? UIWindowScene else { return }
                    setupToastWindow(in: scene)
                }
                .onChange(of: notificationManager.inAppNotification) { _, notification in
                    updateToastContent(notification: notification)
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(onComplete: {
                        showOnboarding = false
                    })
                    .environment(notificationManager)
                    .environment(storeManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
                }
        }
        .modelContainer(container)
    }

    private func handleIncomingURL(_ url: URL) {
        // Four entry points all funnel through here:
        //   1. .capsule file opened from another app (Files, AirDrop, WhatsApp share, etc.)
        //   2. lacuna://import?id=<uuid> — handed off from the iMessage extension via App Group
        //   3. lacuna://import?d=<base64> — extension fallback when App Group write failed
        //   4. lacuna://capsule?d=<base64> — direct capsule URL tapped (rare; safety net)
        let context = container.mainContext

        if url.scheme == "lacuna" {
            handleLacunaURL(url, context: context)
            return
        }

        applyImportResult(CapsuleImporter.importCapsule(from: url, modelContext: context))
    }

    private func handleLacunaURL(_ url: URL, context: ModelContext) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = (url.host ?? "").lowercased()

        // lacuna://open — extension's "go to app" link with no payload
        if host == "open" { return }

        guard host == "import" || host == "capsule" else { return }

        let items = comps.queryItems ?? []

        // Path A: payload staged in App Group by the extension
        if let id = items.first(where: { $0.name == "id" })?.value,
           let data = MessagesAppGroup.consumeIncoming(id: id) {
            applyImportResult(CapsuleImporter.importCapsule(from: data, modelContext: context))
            // Sweep stale staged payloads opportunistically
            MessagesAppGroup.purgeOlderThan(7 * 24 * 60 * 60)
            return
        }

        // Path B: payload encoded directly into the URL (extension fallback / direct tap)
        if let raw = items.first(where: { $0.name == "d" })?.value {
            let normalized = raw
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            var padded = normalized
            while padded.count % 4 != 0 { padded += "=" }
            if let data = Data(base64Encoded: padded) {
                applyImportResult(CapsuleImporter.importCapsule(from: data, modelContext: context))
            }
        }
    }

    private func applyImportResult(_ result: CapsuleImporter.ImportResult) {
        switch result {
        case .imported(let capsule):
            let senderName = capsule.senderName ?? "someone"
            announceImport(
                capsule: capsule,
                title: "time capsule received from \(senderName)",
                navigate: true
            )
            // Trigger 4: After importing a received capsule
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                RatingManager.requestIfEligible()
            }

        case .alreadyExists(let capsule):
            // Toast but don't yank the user into a deep view — they already
            // imported this once, no need to interrupt whatever they were doing.
            let senderName = capsule.senderName ?? "someone"
            announceImport(
                capsule: capsule,
                title: "you already have this capsule from \(senderName)",
                navigate: false
            )

        case .malformed:
            // Show a brief toast so the user doesn't think nothing happened.
            // No capsule ID to navigate to.
            withAnimation(Design.springSnappy) {
                notificationManager.inAppNotification = InAppNotification(
                    capsuleID: "",
                    customTitle: "couldn't open this capsule"
                )
            }
        }
    }

    /// Show the receive toast and optionally navigate to the capsule. Navigation
    /// uses the existing `pendingCapsuleID` channel so HomeView's nav handler
    /// does the routing — works even if the user is currently in onboarding,
    /// settings, etc.
    private func announceImport(capsule: Capsule, title: String, navigate: Bool) {
        let notification = InAppNotification(
            capsuleID: capsule.id.uuidString,
            customTitle: title
        )
        withAnimation(Design.springSnappy) {
            notificationManager.inAppNotification = notification
        }
        guard navigate else { return }
        // Brief delay so the toast lands first, then navigate
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            notificationManager.pendingCapsuleID = capsule.id.uuidString
        }
    }

    private func setupToastWindow(in scene: UIWindowScene) {
        ToastWindow.shared.show(in: scene) {
            ToastOverlayView(notificationManager: notificationManager)
                .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
        }
    }

    private func updateToastContent(notification: InAppNotification?) {
        ToastWindow.shared.update {
            ToastOverlayView(notificationManager: notificationManager)
                .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
        }
    }
}

/// Thin wrapper view that lives in the toast UIWindow
private struct ToastOverlayView: View {
    @Bindable var notificationManager: NotificationManager

    var body: some View {
        VStack {
            if let notification = notificationManager.inAppNotification {
                InAppToastView(
                    notification: notification,
                    onDismiss: {
                        withAnimation(Design.springSnappy) {
                            notificationManager.inAppNotification = nil
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
            Spacer()
        }
        .animation(Design.springSnappy, value: notificationManager.inAppNotification)
    }
}
