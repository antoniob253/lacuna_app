import SwiftUI

struct ConfirmSealStep: View {
    @Binding var title: String
    let selectedType: CapsuleType?
    let unlockDate: Date
    let onSeal: () -> Void
    let onSend: (String) -> Void
    let canSend: Bool
    let onSendPaywall: () -> Void
    @State private var appeared = false
    @State private var showSendNameInput = false
    @State private var sendPulsing = false
    @AppStorage("senderName") private var savedSenderName = ""
    @State private var senderNameInput = ""
    @State private var cancelTrigger = false
    @State private var sendTrigger = false

    private enum Field: Hashable { case title, senderName }
    @FocusState private var focusedField: Field?

    private func submitSenderName() {
        let name = senderNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        sendTrigger.toggle()
        savedSenderName = name
        focusedField = nil
        showSendNameInput = false
        onSend(name)
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("ready to seal?")
                .font(.title2.weight(.light))
                .tracking(Design.trackingNormal)

            VStack(spacing: 16) {
                TextField("title (optional)", text: $title)
                    .font(.body)
                    .tracking(Design.trackingNormal)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(16)
                    .background(Design.surface)
                    .clipShape(.rect(cornerRadius: Design.radiusMedium))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.radiusMedium)
                            .strokeBorder(Design.border, lineWidth: 1)
                    }

                VStack(spacing: 14) {
                    SummaryRow(icon: selectedType?.iconName ?? "questionmark", label: "type", value: selectedType?.label ?? "—")
                    Divider().overlay(Design.divider)
                    SummaryRow(icon: "calendar", label: "opens", value: Design.formatDateTime(unlockDate))
                    Divider().overlay(Design.divider)
                    SummaryRow(icon: "lock.fill", label: "status", value: "ready to seal")
                }
                .padding(20)
                .background(Design.surface)
                .clipShape(.rect(cornerRadius: Design.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.radiusLarge)
                        .strokeBorder(Design.border, lineWidth: 1)
                }
            }
            .padding(.horizontal, 24)

            Text("you will not be able to view the content\nor change the date after sealing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .tracking(Design.trackingNormal)

            Spacer()

            // Seal + Send buttons
            HStack(spacing: 40) {
                SealButtonView(action: {
                    focusedField = nil
                    onSeal()
                })

                SendButtonView(action: {
                    focusedField = nil
                    if canSend {
                        senderNameInput = savedSenderName
                        showSendNameInput = true
                    } else {
                        onSendPaywall()
                    }
                }, isLocked: !canSend)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("done") { focusedField = nil }
                    .font(.body.weight(.medium))
                    .tracking(Design.trackingNormal)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                appeared = true
            }
        }
        .onChange(of: showSendNameInput) { _, showing in
            if showing {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    focusedField = .senderName
                }
            } else {
                focusedField = nil
            }
        }
        .overlay {
            if showSendNameInput {
                // Dimmed backdrop
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        focusedField = nil
                        showSendNameInput = false
                    }

                // Custom name prompt
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Text("your name?")
                            .font(.title3.weight(.medium))
                            .tracking(Design.trackingWide)

                        Text("so the recipient will see who this\ntime capsule is from, when the time comes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .tracking(Design.trackingNormal)
                            .multilineTextAlignment(.center)
                    }

                    TextField("enter your name", text: $senderNameInput)
                        .font(.body)
                        .tracking(Design.trackingNormal)
                        .focused($focusedField, equals: .senderName)
                        .submitLabel(.go)
                        .onSubmit { submitSenderName() }
                        .padding(14)
                        .background(Design.surface)
                        .clipShape(.rect(cornerRadius: Design.radiusMedium))
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.radiusMedium)
                                .strokeBorder(Design.border, lineWidth: 1)
                        }

                    HStack(spacing: 12) {
                        Button {
                            cancelTrigger.toggle()
                            focusedField = nil
                            showSendNameInput = false
                        } label: {
                            Text("cancel")
                                .font(.subheadline.weight(.medium))
                                .tracking(Design.trackingButton)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Design.surface)
                                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                                        .strokeBorder(Design.border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: cancelTrigger)

                        Button {
                            submitSenderName()
                        } label: {
                            Text("send")
                                .font(.subheadline.weight(.medium))
                                .tracking(Design.trackingButton)
                                .foregroundStyle(Design.bg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.primary)
                                .clipShape(.rect(cornerRadius: Design.radiusMedium))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.radiusMedium)
                                        .stroke(Color.primary.opacity(sendPulsing ? 0 : 0.25), lineWidth: 1)
                                        .scaleEffect(x: sendPulsing ? 1.06 : 1.0, y: sendPulsing ? 1.15 : 1.0)
                                }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .medium), trigger: sendTrigger)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                sendPulsing = true
                            }
                        }
                    }
                }
                .padding(24)
                .background(Design.bg)
                .clipShape(.rect(cornerRadius: Design.radiusLarge))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.radiusLarge)
                        .strokeBorder(Design.border, lineWidth: 1)
                }
                .padding(.horizontal, 32)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(Design.springSnappy, value: showSendNameInput)
    }
}
