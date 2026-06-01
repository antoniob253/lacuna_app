import SwiftUI

struct ReceivedCapsuleView: View {
    let payload: ReceivedCapsulePayload
    @ObservedObject var state: ReceivedState
    let onOpen: () -> Void

    @State private var appeared = false
    @State private var pulsing = false
    @State private var openTrigger = false

    var body: some View {
        ZStack {
            MessagesDesign.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(pulsing ? 0 : 0.25), lineWidth: 1)
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulsing ? 1.3 : 1.0)

                    Circle()
                        .fill(MessagesDesign.fg)
                        .frame(width: 76, height: 76)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(MessagesDesign.bg)
                }
                .accessibilityHidden(true)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("a time capsule from \(payload.metadata.senderName)")
                        .font(.subheadline.weight(.medium))
                        .tracking(MessagesDesign.trackingWide)
                        .multilineTextAlignment(.center)

                    Text(payload.metadata.titleOrType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .tracking(MessagesDesign.trackingNormal)

                    Text(payload.metadata.unlockSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .tracking(MessagesDesign.trackingNormal)
                        .padding(.top, 2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .accessibilityElement(children: .combine)

                Spacer()

                bottomAction
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: state.phase)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }

    @ViewBuilder
    private var bottomAction: some View {
        switch state.phase {
        case .idle:
            Button {
                openTrigger.toggle()
                onOpen()
            } label: {
                Text("open in lacuna")
                    .font(.body.weight(.medium))
                    .tracking(MessagesDesign.trackingButton)
                    .foregroundStyle(MessagesDesign.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(MessagesDesign.fg)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: openTrigger)
            .accessibilityLabel("open in lacuna")
            .accessibilityHint("imports this time capsule into your lacuna app")

        case .downloading:
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(MessagesDesign.bg)
                Text("opening...")
                    .font(.body.weight(.medium))
                    .tracking(MessagesDesign.trackingButton)
                    .foregroundStyle(MessagesDesign.bg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(MessagesDesign.fg)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("opening capsule")
            .accessibilityAddTraits(.updatesFrequently)

        case .error:
            VStack(spacing: 10) {
                if let msg = state.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .tracking(MessagesDesign.trackingNormal)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                Button {
                    // Reset to idle before re-trying so the open path doesn't
                    // bail out on its phase guard.
                    state.phase = .idle
                    state.errorMessage = nil
                    openTrigger.toggle()
                    onOpen()
                } label: {
                    Text("try again")
                        .font(.body.weight(.medium))
                        .tracking(MessagesDesign.trackingButton)
                        .foregroundStyle(MessagesDesign.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MessagesDesign.fg)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: openTrigger)
                .accessibilityLabel("try again")
            }
        }
    }
}
