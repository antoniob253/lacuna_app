import SwiftUI
import SwiftData

/// A streamlined single-screen capsule for the daily ritual:
/// type-text-and-seal-for-tomorrow, no decisions.
///
/// Parallel path to `CreateCapsuleView` — they share the underlying `Capsule`
/// model and notification scheduling, but `QuickCaptureView` collapses the
/// four-step flow into one. Used by the "✦ a letter to tomorrow" affordance
/// on the home screen.
struct QuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var textContent = ""
    @State private var cancelTrigger = false
    @State private var sealTrigger = false
    @State private var appeared = false
    @State private var sparkleBreathing = false

    /// Captured at mount so a slow user doesn't see "opens tomorrow" while
    /// midnight ticks past underneath them.
    private let unlockDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? Date.now.addingTimeInterval(86400)

    private var canSeal: Bool {
        !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unlockSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' HH:mm"
        return "opens \(formatter.string(from: unlockDate))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header: just a cancel — symmetric with the other sheets
                HStack {
                    Spacer()

                    Button {
                        cancelTrigger.toggle()
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
                .padding(.bottom, 24)

                // Title — sparkle prefix marks this as the daily-ritual path,
                // distinguishing it visually from the standard "new capsule"
                // sheet header.
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("✦")
                            .font(.title3.weight(.medium))
                            .tracking(Design.trackingWide)
                            .opacity(sparkleBreathing ? 0.5 : 1.0)
                        Text("letter to tomorrow")
                            .font(.title3.weight(.medium))
                            .tracking(Design.trackingWide)
                    }
                    Text(unlockSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .tracking(Design.trackingNormal)
                }
                .padding(.bottom, 28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                // Editor — reuses the same component as the standard flow, so
                // markdown roundtripping, writing prompts, keyboard toolbar,
                // and all keyboard-fix work apply identically here. We do NOT
                // auto-focus: the writing prompt placeholder + ✦ swap affordance
                // are only visible when the editor is unfocused, and they are
                // the highest-value scaffolding for the daily ritual. Showing
                // them first (even at the cost of one tap to enter the editor)
                // is the right tradeoff.
                TextContentEditor(textContent: $textContent)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)

                Spacer(minLength: 16)

                // Single committed action — no date picker, no type picker,
                // no title field. The user wrote a thought; tomorrow they see it.
                Button {
                    sealTrigger.toggle()
                    sealLetter()
                } label: {
                    Text("seal for tomorrow")
                        .font(.body.weight(.medium))
                        .tracking(Design.trackingButton)
                        .foregroundStyle(canSeal ? Design.bg : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSeal ? Design.fg : Design.surface)
                }
                .buttonStyle(.plain)
                .disabled(!canSeal)
                .sensoryFeedback(.success, trigger: sealTrigger)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(appeared ? 1 : 0)
                .accessibilityHint("seals your letter; it opens tomorrow at this hour")
            }
            .background(Design.bg.ignoresSafeArea())
            .overlay { FloatingParticlesView().allowsHitTesting(false).ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    sparkleBreathing = true
                }
            }
        }
    }

    private func sealLetter() {
        let capsule = Capsule(
            title: "",
            type: .text,
            textContent: textContent,
            imageData: nil,
            audioData: nil,
            unlocksAt: unlockDate
        )
        modelContext.insert(capsule)
        NotificationManager.scheduleCapsuleNotification(
            id: capsule.id.uuidString,
            title: "",
            unlockDate: unlockDate
        )
        dismiss()
    }
}
