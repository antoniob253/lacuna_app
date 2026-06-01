import SwiftUI

struct LandingView: View {
    let onOpenApp: () -> Void

    @State private var appeared = false
    @State private var pulsing = false
    @State private var tapTrigger = false

    var body: some View {
        ZStack {
            MessagesDesign.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(pulsing ? 0 : 0.2), lineWidth: 1)
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulsing ? 1.3 : 1.0)

                    Circle()
                        .fill(MessagesDesign.fg)
                        .frame(width: 70, height: 70)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(MessagesDesign.bg)
                }
                .contentShape(.circle)
                .onTapGesture { tapTrigger.toggle(); onOpenApp() }
                .sensoryFeedback(.impact(weight: .medium), trigger: tapTrigger)

                Text("lacuna")
                    .font(.title3.weight(.medium))
                    .tracking(MessagesDesign.trackingWide)

                Text("create a time capsule\nin the lacuna app, then send it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(MessagesDesign.trackingNormal)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Spacer()

                Button {
                    tapTrigger.toggle()
                    onOpenApp()
                } label: {
                    Text("open lacuna")
                        .font(.subheadline.weight(.medium))
                        .tracking(MessagesDesign.trackingButton)
                        .foregroundStyle(MessagesDesign.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MessagesDesign.fg)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: tapTrigger)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}
