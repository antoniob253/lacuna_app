import SwiftUI
import SwiftData
import PhotosUI
import MessageUI

struct CreateCapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(StoreManager.self) private var storeManager
    @Query(sort: \Capsule.createdAt) private var allCapsules: [Capsule]

    @State private var step = CreateStep.selectType
    @State private var selectedType: CapsuleType?
    @State private var title = ""
    @State private var textContent = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var audioFileName: String?
    @State private var unlockDate = Date.now.addingTimeInterval(86400)
    @State private var audioManager = AudioManager()
    @State private var typeTrigger = false
    @State private var stepTrigger = false
    @State private var goingForward = true
    @State private var cancelTrigger = false
    @State private var swipeBackTrigger = false
    @State private var shareFileURL: URL?
    @State private var pendingSenderName = ""
    @State private var paywallReason: PaywallReason?
    @State private var whisperAppeared = false
    @State private var whisperBreathing = false
    @State private var isPreparingSend = false
    @State private var sendErrorMessage: String?

    private var canProceed: Bool {
        switch step {
        case .selectType: selectedType != nil
        case .addContent: hasContent
        case .pickDate: unlockDate > Date.now
        case .confirm: true
        }
    }

    private var activeSealedTextCount: Int {
        allCapsules.filter { $0.isLocal && $0.isSealed && $0.type == .text }.count
    }

    private var activeSealedPhotoCount: Int {
        allCapsules.filter { $0.isLocal && $0.isSealed && $0.type == .photo }.count
    }

    private var activeSealedVoiceCount: Int {
        allCapsules.filter { $0.isLocal && $0.isSealed && $0.type == .voice }.count
    }

    private var hasContent: Bool {
        switch selectedType {
        case .text: !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo: imageData != nil
        case .voice: audioFileName != nil && !audioManager.isRecording
        case nil: false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Text("new capsule")
                        .font(.title3.weight(.medium))
                        .tracking(Design.trackingWide)

                    Spacer()

                    Button {
                        cancelTrigger.toggle()
                        cleanup()
                        dismiss()
                    } label: {
                        Text("cancel")
                            .font(.body.weight(.medium))
                            .tracking(Design.trackingNormal)
                            .foregroundStyle(Design.bg)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Design.fg)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: cancelTrigger)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)

                StepProgressBar(currentStep: step)

                Group {
                    switch step {
                    case .selectType:
                        TypeSelectionStep(
                            selectedType: $selectedType,
                            typeTrigger: $typeTrigger
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                    case .addContent:
                        ContentInputStep(
                            selectedType: selectedType,
                            textContent: $textContent,
                            selectedPhoto: $selectedPhoto,
                            imageData: $imageData,
                            audioFileName: $audioFileName,
                            audioManager: audioManager
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                    case .pickDate:
                        DateSelectionStep(unlockDate: $unlockDate)
                            .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                    case .confirm:
                        ConfirmSealStep(
                            title: $title,
                            selectedType: selectedType,
                            unlockDate: unlockDate,
                            onSeal: { sealCapsule() },
                            onSend: { senderName in sendCapsule(senderName: senderName) },
                            canSend: storeManager.canSend,
                            onSendPaywall: {
                                paywallReason = .sendGated
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            // Swipe right to go back
                            if value.translation.width > 80, abs(value.translation.height) < 50, step.rawValue > 0 {
                                if let prev = CreateStep(rawValue: step.rawValue - 1) {
                                    swipeBackTrigger.toggle()
                                    goingForward = false
                                    withAnimation(Design.springSnappy) {
                                        step = prev
                                    }
                                }
                            }
                        }
                )
                .background(Design.bg)

                if step == .selectType {
                    Text("who exactly made\nthe choice though?")
                        .font(.caption)
                        .tracking(Design.trackingWide)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(.primary.opacity(whisperAppeared ? (whisperBreathing ? 0.15 : 0.4) : 0))
                        .offset(y: whisperAppeared ? 0 : 8)
                        .padding(.bottom, 40)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.2).delay(1.0)) { whisperAppeared = true }
                            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(2.2)) { whisperBreathing = true }
                        }
                }

                if step != .confirm {
                    Button(step == .selectType ? "i made my choice" : "continue") {
                        // Check pro limits when advancing from type selection
                        if step == .selectType, let type = selectedType {
                            if !storeManager.canCreate(type: type, activeSealedText: activeSealedTextCount, activeSealedPhoto: activeSealedPhotoCount, activeSealedVoice: activeSealedVoiceCount) {
                                if type == .text {
                                    paywallReason = .textLimit
                                } else if type == .photo {
                                    paywallReason = .photoLimit
                                } else {
                                    paywallReason = .voiceGated
                                }
                                return
                            }
                        }
                        stepTrigger.toggle()
                        goingForward = true
                        withAnimation(Design.springSnappy) {
                            if let next = CreateStep(rawValue: step.rawValue + 1) {
                                step = next
                            }
                        }
                    }
                    .font(.body.weight(.medium))
                    .tracking(Design.trackingButton)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canProceed ? Design.fg : Design.surface)
                    .foregroundStyle(canProceed ? Design.bg : .secondary)
                    .clipShape(.rect(cornerRadius: Design.radiusMedium))
                    .disabled(!canProceed)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .sensoryFeedback(.impact(weight: .light), trigger: stepTrigger)
                }
            }
            .background(Design.bg.ignoresSafeArea())
            .overlay { FloatingParticlesView().allowsHitTesting(false).ignoresSafeArea() }
            .overlay {
                if isPreparingSend {
                    PreparingSendOverlay()
                        .transition(.opacity)
                }
            }
            .animation(Design.springSnappy, value: isPreparingSend)
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(step != .selectType)
            .sensoryFeedback(.selection, trigger: typeTrigger)
            .sensoryFeedback(.selection, trigger: swipeBackTrigger)
            .sheet(item: $paywallReason) { reason in
                PaywallView(storeManager: storeManager, reason: reason)
            }
            .alert(
                "couldn't send",
                isPresented: Binding(
                    get: { sendErrorMessage != nil },
                    set: { if !$0 { sendErrorMessage = nil } }
                )
            ) {
                Button("share another way") {
                    sendErrorMessage = nil
                    let capsule = makeTempCapsule(senderName: pendingSenderName)
                    presentFileShareSheet(senderName: pendingSenderName, capsule: capsule)
                }
                Button("cancel", role: .cancel) {}
            } message: {
                Text(sendErrorMessage ?? "")
            }
            .onChange(of: notificationManager.pendingCapsuleID) { _, id in
                if id != nil {
                    cleanup()
                    dismiss()
                }
            }
        }
    }

    private func sealCapsule() {
        // Convert audio file to inline Data for iCloud sync
        let audioData: Data? = if let audioFileName, selectedType == .voice {
            audioManager.loadAudioData(for: audioFileName)
        } else {
            nil
        }

        let capsule = Capsule(
            title: title,
            type: selectedType ?? .text,
            textContent: selectedType == .text ? textContent : nil,
            imageData: selectedType == .photo ? imageData : nil,
            audioData: audioData,
            unlocksAt: unlockDate
        )
        modelContext.insert(capsule)
        NotificationManager.scheduleCapsuleNotification(
            id: capsule.id.uuidString,
            title: title,
            unlockDate: unlockDate
        )

        // Trigger 3: After sealing the 2nd capsule — user is hooked
        let totalLocal = allCapsules.filter(\.isLocal).count + 1
        if totalLocal == 2 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                RatingManager.requestIfEligible()
            }
        }

        dismiss()
    }

    private func sendCapsule(senderName: String) {
        pendingSenderName = senderName

        // Build a temp capsule for routing decisions (not yet inserted into DB)
        let tempCapsule = makeTempCapsule(senderName: senderName)

        // If the device can't send messages (no iMessage/SMS), skip the prompt
        // and go straight to the file share sheet.
        let imessageAvailable = iMessageSender.availability() == .available

        Task { @MainActor in
            // Let the modal close before presenting the next sheet
            try? await Task.sleep(for: .milliseconds(600))
            if imessageAvailable {
                presentRoutingChoice(senderName: senderName, capsule: tempCapsule)
            } else {
                presentFileShareSheet(senderName: senderName, capsule: tempCapsule)
            }
        }
    }

    private func makeTempCapsule(senderName: String) -> Capsule {
        let audioData: Data? = if let audioFileName, selectedType == .voice {
            audioManager.loadAudioData(for: audioFileName)
        } else {
            nil
        }
        return Capsule(
            title: title,
            type: selectedType ?? .text,
            textContent: selectedType == .text ? textContent : nil,
            imageData: selectedType == .photo ? imageData : nil,
            audioData: audioData,
            unlocksAt: unlockDate,
            isSent: true
        )
    }

    private func topPresentedVC() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Asks the user how to send: iMessage rich card vs. share to other apps.
    private func presentRoutingChoice(senderName: String, capsule: Capsule) {
        guard let topVC = topPresentedVC() else { return }

        let alert = UIAlertController(title: "send your time capsule", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "via imessage", style: .default) { _ in
            self.presentMessagesComposer(senderName: senderName, capsule: capsule)
        })
        alert.addAction(UIAlertAction(title: "via other apps", style: .default) { _ in
            self.presentFileShareSheet(senderName: senderName, capsule: capsule)
        })
        alert.addAction(UIAlertAction(title: "cancel", style: .cancel))

        // iPad popover anchoring
        if let pop = alert.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 40, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        topVC.present(alert, animated: true)
    }

    /// Presents `MFMessageComposeViewController` with an attached `MSMessage` so
    /// the recipient sees a Lacuna-branded card that opens our iMessage extension.
    /// For payloads that don't fit inline (photos, longer voice notes), this
    /// uploads an encrypted blob to CloudKit first — hence the async prepare step.
    private func presentMessagesComposer(senderName: String, capsule: Capsule) {
        isPreparingSend = true

        Task { @MainActor in
            let coordinator = MessagesComposerCoordinator(
                cloudKitRecordID: nil,
                onCompleted: { sent in
                    if sent { self.saveSentCapsule() }
                }
            )
            ConfirmRoutingHolder.shared.retain(coordinator)

            do {
                let prepared = try await iMessageSender.prepareSend(
                    capsule: capsule,
                    senderName: senderName,
                    delegate: coordinator
                )
                // Pass the record ID through to the coordinator so it can clean
                // up the upload if the user cancels the composer.
                coordinator.cloudKitRecordID = prepared.cloudKitRecordID

                isPreparingSend = false

                guard let topVC = topPresentedVC() else {
                    // We can't actually present the composer — likely the user
                    // navigated away during the upload. Clean up the orphan
                    // CloudKit record so we don't leave ciphertext sitting in
                    // Apple's public DB for nobody.
                    if let id = prepared.cloudKitRecordID {
                        Task.detached { await CapsuleTransport.delete(recordID: id) }
                    }
                    ConfirmRoutingHolder.shared.release(coordinator)
                    return
                }
                topVC.present(prepared.composer, animated: true)
            } catch {
                ConfirmRoutingHolder.shared.release(coordinator)
                isPreparingSend = false
                sendErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// Presents the existing file-based share sheet for non-iMessage apps.
    private func presentFileShareSheet(senderName: String, capsule: Capsule) {
        guard let fileURL = CapsuleExporter.export(capsule: capsule, senderName: senderName) else { return }
        shareFileURL = fileURL

        guard let topVC = topPresentedVC() else { return }

        let shareItem = CapsuleShareItem(fileURL: fileURL, unlockDate: unlockDate)
        let appStoreLink = "https://apps.apple.com/app/lacuna-time-capsule/id6761478231"
        let message = "i sealed a time capsule for you. download lacuna to open it: \(appStoreLink)"
        let activityVC = UIActivityViewController(activityItems: [message, shareItem], applicationActivities: nil)
        // iMessage is excluded here on purpose — the iMessage path is handled separately
        // via `presentMessagesComposer` so we send a rich MSMessage card instead of a file.
        activityVC.excludedActivityTypes = [.message]
        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            try? FileManager.default.removeItem(at: fileURL)
            self.shareFileURL = nil
            if completed { self.saveSentCapsule() }
        }

        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 40, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
    }

    private func saveSentCapsule() {
        let audioData: Data? = if let audioFileName, selectedType == .voice {
            audioManager.loadAudioData(for: audioFileName)
        } else {
            nil
        }

        // Only called after share sheet completes successfully
        let capsule = Capsule(
            title: title,
            type: selectedType ?? .text,
            textContent: selectedType == .text ? textContent : nil,
            imageData: selectedType == .photo ? imageData : nil,
            audioData: audioData,
            unlocksAt: unlockDate,
            isSent: true
        )
        modelContext.insert(capsule)

        // Intentionally NO local notification for sent capsules — the recipient's
        // own copy will notify them at unlock time. Notifying the sender that
        // "the wait is over" is misleading: they can't open it from the sent
        // section anyway.

        dismiss()
    }

    private func cleanup() {
        if audioManager.isRecording { audioManager.stopRecording() }
        if audioManager.isPlaying { audioManager.stopPlayback() }
        if let audioFile = audioFileName { audioManager.deleteAudioFile(named: audioFile) }
    }
}

// MARK: - iMessage composer plumbing

/// MFMessageComposeViewController demands a delegate; SwiftUI views can't be one
/// directly. This NSObject coordinator bridges back to a closure on completion,
/// and cleans up the CloudKit record if the user cancels (so we don't leave
/// orphan ciphertext on Apple's servers).
final class MessagesComposerCoordinator: NSObject, MFMessageComposeViewControllerDelegate {
    var cloudKitRecordID: String?
    private let onCompleted: (Bool) -> Void

    init(cloudKitRecordID: String?, onCompleted: @escaping (Bool) -> Void) {
        self.cloudKitRecordID = cloudKitRecordID
        self.onCompleted = onCompleted
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        let sent = (result == .sent)

        // If the user didn't actually send, drop the staged ciphertext.
        if !sent, let recordID = cloudKitRecordID {
            Task { await CapsuleTransport.delete(recordID: recordID) }
        }

        controller.dismiss(animated: true) {
            self.onCompleted(sent)
            ConfirmRoutingHolder.shared.release(self)
        }
    }
}

/// Tiny lifetime holder for transient delegate objects so they survive across
/// the modal presentation without leaking. Released in the completion callback.
final class ConfirmRoutingHolder {
    static let shared = ConfirmRoutingHolder()
    private var live: [ObjectIdentifier: AnyObject] = [:]

    func retain(_ object: AnyObject) {
        live[ObjectIdentifier(object)] = object
    }

    func release(_ object: AnyObject) {
        live.removeValue(forKey: ObjectIdentifier(object))
    }
}

/// Full-screen dim + spinner shown while we encrypt+upload a media capsule
/// before opening the iMessage composer. Blocks taps so the user can't double-fire.
private struct PreparingSendOverlay: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(pulsing ? 0 : 0.3), lineWidth: 1)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulsing ? 1.4 : 1.0)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text("preparing your capsule...")
                    .font(.caption)
                    .tracking(Design.trackingWide)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { /* swallow taps */ }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("preparing your capsule")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
