import Combine
import Messages
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
    private var hosting: UIHostingController<AnyView>?
    private let receivedState = ReceivedState()
    /// Tracks the URL of the message currently rendered so we don't tear down
    /// and rebuild the SwiftUI hierarchy unless the selected message changes.
    private var currentMessageURL: URL?

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        present(for: conversation)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        if let conversation = activeConversation { present(for: conversation) }
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        present(for: conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        // Reset the in-flight state in place (don't replace the instance — the
        // SwiftUI view observes it; replacing would tear the @State animations).
        receivedState.phase = .idle
        receivedState.errorMessage = nil
        present(for: conversation)
    }

    // MARK: - UI

    private func present(for conversation: MSConversation) {
        let payload: ReceivedCapsulePayload? = {
            guard let url = conversation.selectedMessage?.url else { return nil }
            return MessagesPayloadCodec.decode(from: url)
        }()

        // Skip rebuild if the selected message hasn't actually changed. Avoids
        // resetting fade-in / breathe animations on every state-only refresh.
        let newURL = conversation.selectedMessage?.url
        if newURL == currentMessageURL, hosting != nil { return }
        currentMessageURL = newURL

        let root: AnyView
        if let payload {
            root = AnyView(
                ReceivedCapsuleView(
                    payload: payload,
                    state: receivedState,
                    onOpen: { [weak self] in
                        self?.handleOpenTap(payload: payload)
                    }
                )
            )
        } else {
            root = AnyView(LandingView(onOpenApp: { [weak self] in
                self?.openMainApp()
            }))
        }

        if let hosting {
            hosting.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
            hosting = host
        }
    }

    // MARK: - Open / download

    private func handleOpenTap(payload: ReceivedCapsulePayload) {
        // Single in-flight guard — prevents rapid double-taps on both inline
        // and CloudKit paths from firing multiple `extensionContext.open()` calls
        // or duplicate downloads.
        guard receivedState.phase == .idle else { return }

        switch payload.content {
        case .inline(let data):
            receivedState.phase = .downloading
            handoffAndOpen(data: data)

        case .cloudKit(let recordID, let key):
            receivedState.phase = .downloading
            receivedState.errorMessage = nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let data = try await CapsuleTransport.download(recordID: recordID, key: key)
                    self.handoffAndOpen(data: data)
                } catch let e as CapsuleTransport.TransportError {
                    self.receivedState.phase = .error
                    self.receivedState.errorMessage = e.errorDescription ?? "couldn't download"
                } catch {
                    self.receivedState.phase = .error
                    self.receivedState.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handoffAndOpen(data: Data) {
        let id = UUID().uuidString
        do {
            try MessagesAppGroup.writeIncoming(data: data, id: id)
            if let url = URL(string: "lacuna://import?id=\(id)") {
                extensionContext?.open(url) { [weak self] success in
                    if !success {
                        // Main app didn't open. Clean up the staged file and reset state.
                        Task { @MainActor in
                            _ = MessagesAppGroup.consumeIncoming(id: id)
                            self?.receivedState.phase = .error
                            self?.receivedState.errorMessage = "couldn't open lacuna"
                        }
                    }
                }
            }
        } catch {
            // App Group unavailable — embed bytes directly in the URL as fallback
            let base64 = data.base64EncodedString().urlPercentEncoded
            if let url = URL(string: "lacuna://import?d=\(base64)") {
                extensionContext?.open(url) { [weak self] success in
                    if !success {
                        Task { @MainActor in
                            self?.receivedState.phase = .error
                            self?.receivedState.errorMessage = "couldn't open lacuna"
                        }
                    }
                }
            }
        }
    }

    private func openMainApp() {
        if let url = URL(string: "lacuna://open") {
            extensionContext?.open(url, completionHandler: nil)
        }
    }
}

/// Mutable state shared between the controller and the SwiftUI view so the
/// "downloading…" / "error" transitions render without rebuilding the host.
@MainActor
final class ReceivedState: ObservableObject {
    enum Phase { case idle, downloading, error }
    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
}
