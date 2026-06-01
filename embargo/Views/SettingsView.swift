import SwiftUI
import SwiftData
import AVFoundation
import RevenueCat

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.automatic.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(StoreManager.self) private var storeManager
    @Query private var allCapsules: [Capsule]
    @State private var appeared = false
    @State private var modeTrigger = false
    @State private var doneTrigger = false
    @State private var showPrivacyPolicy = false
    @State private var showPaywall = false
    @State private var cameraDenied = false
    @State private var micDenied = false
    @State private var feedbackFallbackShown = false

    private var selectedMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .automatic
    }

    private var people: [String] {
        let names = allCapsules.compactMap(\.senderName)
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("settings")
                        .font(.title3.weight(.medium))
                        .tracking(Design.trackingWide)

                    Spacer()

                    Button {
                        doneTrigger.toggle()
                        dismiss()
                    } label: {
                        Text("done")
                            .font(.body.weight(.medium))
                            .tracking(Design.trackingNormal)
                            .foregroundStyle(Design.bg)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Design.fg)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: doneTrigger)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)

                ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("appearance")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.5))
                            .tracking(Design.trackingWide)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Button {
                                    modeTrigger.toggle()
                                    withAnimation(Design.springSnappy) {
                                        appearanceMode = mode.rawValue
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: mode.iconName)
                                            .font(.body.weight(.light))
                                            .frame(width: 24)

                                        Text(mode.label)
                                            .font(.body)
                                            .tracking(Design.trackingNormal)

                                        Spacer()

                                        Circle()
                                            .strokeBorder(
                                                selectedMode == mode ? Color.primary : Color.primary.opacity(0.25),
                                                lineWidth: selectedMode == mode ? 6 : 1
                                            )
                                            .frame(width: 22, height: 22)
                                            .animation(Design.springSnappy, value: selectedMode)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("appearance: \(mode.label)")

                                if mode != AppearanceMode.allCases.last {
                                    Divider()
                                        .overlay(Design.divider)
                                        .padding(.leading, 58)
                                }
                            }
                        }
                        .background(Design.surface)
                        .clipShape(.rect(cornerRadius: Design.radiusMedium))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.radiusMedium)
                                .strokeBorder(Design.border, lineWidth: 1)
                        }
                    }

                    // Notifications warning (only if denied)
                    if notificationManager.notificationsDenied {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("notifications")
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.5))
                                .tracking(Design.trackingWide)
                                .padding(.leading, 4)

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "bell.slash")
                                        .font(.body.weight(.light))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("notifications are off")
                                            .font(.body)
                                            .tracking(Design.trackingNormal)
                                        Text("you won't know when capsules are ready.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .tracking(Design.trackingTight)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                                .background(Design.surface)
                                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                                        .strokeBorder(Design.border, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Camera denied
                    if cameraDenied {
                        permissionDeniedRow(
                            header: "camera",
                            icon: "camera",
                            title: "camera access is off",
                            detail: "you won't be able to take photos."
                        )
                    }

                    // Microphone denied
                    if micDenied {
                        permissionDeniedRow(
                            header: "microphone",
                            icon: "mic.slash",
                            title: "microphone access is off",
                            detail: "you won't be able to record voice notes."
                        )
                    }

                    // iCloud sync status
                    VStack(alignment: .leading, spacing: 14) {
                        Text("icloud")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.5))
                            .tracking(Design.trackingWide)
                            .padding(.leading, 4)

                        if FileManager.default.ubiquityIdentityToken != nil {
                            HStack(spacing: 14) {
                                Image(systemName: "cloud")
                                    .font(.body.weight(.light))
                                    .frame(width: 24)
                                Text("capsules synced across your devices")
                                    .font(.body)
                                    .tracking(Design.trackingNormal)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .background(Design.surface)
                            .clipShape(.rect(cornerRadius: Design.radiusMedium))
                            .overlay {
                                RoundedRectangle(cornerRadius: Design.radiusMedium)
                                    .strokeBorder(Design.border, lineWidth: 1)
                            }
                        } else {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "icloud.slash")
                                        .font(.body.weight(.light))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("icloud is off")
                                            .font(.body)
                                            .tracking(Design.trackingNormal)
                                        Text("capsules won't sync across your devices.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .tracking(Design.trackingTight)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                                .background(Design.surface)
                                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                                        .strokeBorder(Design.border, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Pro status
                    VStack(alignment: .leading, spacing: 14) {
                        Text("lacuna +")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.5))
                            .tracking(Design.trackingWide)
                            .padding(.leading, 4)

                        if storeManager.isPro {
                            HStack(spacing: 14) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.light))
                                    .frame(width: 24)
                                Text("lacuna + unlocked")
                                    .font(.body)
                                    .tracking(Design.trackingNormal)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                            .background(Design.surface)
                            .clipShape(.rect(cornerRadius: Design.radiusMedium))
                            .overlay {
                                RoundedRectangle(cornerRadius: Design.radiusMedium)
                                    .strokeBorder(Design.border, lineWidth: 1)
                            }
                        } else {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack {
                                    Text("upgrade to +")
                                        .font(.body)
                                        .tracking(Design.trackingNormal)
                                    Spacer()
                                    if let product = storeManager.proProduct {
                                        Text(product.localizedPriceString)
                                            .font(.subheadline.weight(.light))
                                            .tracking(Design.trackingNormal)
                                            .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.light))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(Design.surface)
                                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                                        .strokeBorder(Design.border, lineWidth: 1)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // People — quiet acknowledgment of connections
                    if !people.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("people")
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.5))
                                .tracking(Design.trackingWide)
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                ForEach(people.enumerated(), id: \.element) { index, name in
                                    HStack(spacing: 14) {
                                        Image(systemName: "person")
                                            .font(.body.weight(.light))
                                            .frame(width: 24)
                                        Text(name)
                                            .font(.body)
                                            .tracking(Design.trackingNormal)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)

                                    if index < people.count - 1 {
                                        Divider()
                                            .overlay(Design.divider)
                                            .padding(.leading, 58)
                                    }
                                }
                            }
                            .background(Design.surface)
                            .clipShape(.rect(cornerRadius: Design.radiusMedium))
                            .overlay {
                                RoundedRectangle(cornerRadius: Design.radiusMedium)
                                    .strokeBorder(Design.border, lineWidth: 1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("about")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.5))
                            .tracking(Design.trackingWide)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            aboutRow(label: "made by", value: "antonio baltic")

                            Divider()
                                .overlay(Design.divider)
                                .padding(.leading, 20)

                            aboutRow(label: "version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")

                            Divider()
                                .overlay(Design.divider)
                                .padding(.leading, 20)

                            Button {
                                showPrivacyPolicy = true
                            } label: {
                                HStack {
                                    Text("privacy policy")
                                        .font(.body)
                                        .tracking(Design.trackingNormal)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.light))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(Design.divider)
                                .padding(.leading, 20)

                            Button {
                                openFeedback()
                            } label: {
                                HStack {
                                    Text("send feedback")
                                        .font(.body)
                                        .tracking(Design.trackingNormal)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2.weight(.light))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("opens your mail app to write to the developer")
                        }
                        .background(Design.surface)
                        .clipShape(.rect(cornerRadius: Design.radiusMedium))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.radiusMedium)
                                .strokeBorder(Design.border, lineWidth: 1)
                        }
                    }

                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.4), value: appeared)
            }
            }
            .toolbar(.hidden, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .background(Design.bg.ignoresSafeArea())
            .overlay { FloatingParticlesView().ignoresSafeArea() }
            .sensoryFeedback(.selection, trigger: modeTrigger)
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
                    .environment(notificationManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(storeManager: storeManager, reason: .generic)
            }
            .alert("no mail app", isPresented: $feedbackFallbackShown) {
                Button("ok", role: .cancel) {}
            } message: {
                Text("we couldn't open mail on this device. the address antoniobaltic@icloud.com has been copied to your clipboard.")
            }
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            Task { await notificationManager.checkNotificationStatus() }
            checkPermissionStatuses()
        }
        .onChange(of: notificationManager.pendingCapsuleID) { _, id in
            if id != nil {
                showPrivacyPolicy = false
                dismiss()
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .tracking(Design.trackingNormal)
            Spacer()
            Text(value)
                .font(.body)
                .tracking(Design.trackingNormal)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func permissionDeniedRow(header: String, icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(header)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.5))
                .tracking(Design.trackingWide)
                .padding(.leading, 4)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.body.weight(.light))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                            .tracking(Design.trackingNormal)
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .tracking(Design.trackingTight)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Design.surface)
                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                        .strokeBorder(Design.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func checkPermissionStatuses() {
        cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        micDenied = AVAudioApplication.shared.recordPermission == .denied
    }

    private func openFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let subject = "lacuna feedback (v\(version) · build \(build))"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "lacuna%20feedback"
        guard let url = URL(string: "mailto:antoniobaltic@icloud.com?subject=\(encoded)") else { return }

        // If a mail client is set up, open it. Otherwise copy the address to
        // the clipboard and let the user know — never a dead tap.
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIPasteboard.general.string = "antoniobaltic@icloud.com"
            feedbackFallbackShown = true
        }
    }
}

#Preview("settings — notifications allowed") {
    SettingsPreview(denied: false, isPro: false)
}

#Preview("settings — notifications denied") {
    SettingsPreview(denied: true, isPro: false)
}

#Preview("settings — pro user") {
    SettingsPreview(denied: false, isPro: true)
}

private struct SettingsPreview: View {
    let denied: Bool
    let isPro: Bool

    @State private var notificationManager = NotificationManager.shared
    @State private var storeManager = StoreManager.shared

    var body: some View {
        SettingsView()
            .environment(notificationManager)
            .environment(storeManager)
            .onAppear {
                notificationManager.notificationsDenied = denied
                storeManager.isPro = isPro
            }
    }
}
