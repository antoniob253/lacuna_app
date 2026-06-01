import SwiftUI

struct SendButtonView: View {
    let action: () -> Void
    /// Whether the user has Pro. When `false`, the button is decorated with a
    /// tiny lock badge so it's clear up-front that tapping leads to a paywall —
    /// avoids the "tap-then-paywall-surprise" friction.
    var isLocked: Bool = false
    @State private var sendTrigger = false
    @State private var isPressed = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Button {
                sendTrigger.toggle()
                withAnimation(Design.springSnappy) {
                    isPressed = true
                } completion: {
                    action()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(pulsing ? 0 : 0.25), lineWidth: 1)
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulsing ? 1.3 : 1.0)

                    Circle()
                        .fill(Design.fg)
                        .frame(width: 72, height: 72)

                    Image(systemName: "paperplane")
                        .font(.title2.weight(.light))
                        .foregroundStyle(Design.bg)

                    // Pro-required lock badge — small, top-trailing of the
                    // circle. Visible only for free users.
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Design.bg)
                            .padding(6)
                            .background(Design.fg)
                            .clipShape(.circle)
                            .overlay {
                                Circle().stroke(Design.bg, lineWidth: 1.5)
                            }
                            .offset(x: 28, y: -28)
                            .accessibilityHidden(true)
                    }
                }
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: sendTrigger)
            .accessibilityLabel(isLocked ? "send (requires lacuna +)" : "send")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }

            Text("send")
                .font(.caption)
                .tracking(Design.trackingButton)
                .foregroundStyle(.secondary)
        }
    }
}
