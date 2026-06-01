import SwiftUI
import SwiftData

struct SealedCapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let capsule: Capsule

    @State private var showDeleteConfirmation = false
    @State private var showReveal = false
    @State private var ceremonyDone = false
    @State private var appeared = false
    @State private var isReady = false
    @State private var openTrigger = false
    @State private var backTrigger = false
    @State private var deleteTrigger = false

    var body: some View {
        ZStack {
            // Normal sealed content
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let unlockable = now >= capsule.unlocksAt && capsule.openedAt == nil

                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 36) {
                            SealedCapsuleHeader(capsule: capsule, isReady: isReady, onOpenTap: {
                                openTrigger.toggle()
                                showReveal = true
                            })

                            CountdownView(targetDate: capsule.unlocksAt)
                                .padding(.vertical, 8)

                            CapsuleInfoCard(capsule: capsule)
                                .padding(.horizontal, 24)

                            if !isReady {
                                VStack(spacing: 10) {
                                    Image(systemName: "hourglass")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .accessibilityHidden(true)
                                    Text(capsule.isSent ? "you both must wait" : "you must wait")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .tracking(Design.trackingNormal)
                                }
                                .padding(.top, 8)
                                .transition(.opacity)
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .frame(minHeight: geo.size.height - 100)
                        .frame(maxWidth: .infinity)
                    }
                }
                .onChange(of: unlockable) { _, ready in
                    if ready && !isReady {
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                            isReady = true
                        }
                    }
                }
            }
            .overlay { FloatingParticlesView().ignoresSafeArea() }
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    Button {
                        backTrigger.toggle()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Design.bg)
                            .frame(width: 48, height: 48)
                            .background(Design.fg)
                            .clipShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: backTrigger)

                    Spacer()

                    Button {
                        deleteTrigger.toggle()
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Design.bg)
                            .frame(width: 48, height: 48)
                            .background(Design.fg)
                            .clipShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.warning, trigger: deleteTrigger)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .opacity(showReveal ? 0 : 1)
        }
        .background(Design.bg.ignoresSafeArea())
        .overlay {
            if showReveal {
                if ceremonyDone {
                    // After ceremony, show content in the same layout as normal opened view
                    OpenedCapsuleView(capsule: capsule)
                        .transition(.opacity)
                } else {
                    OpeningRevealView(
                        capsule: capsule,
                        onComplete: {
                            withAnimation(.easeOut(duration: 0.5)) {
                                ceremonyDone = true
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            let unlockable = Date.now >= capsule.unlocksAt && capsule.openedAt == nil
            if unlockable { isReady = true }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("let it go?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("annihilate", role: .destructive) {
                deleteCapsule()
            }
        } message: {
            Text("this moment will be lost in time. like tears in the rain. there is no undoing this.")
        }
    }

    private func deleteCapsule() {
        NotificationManager.cancelCapsuleNotification(id: capsule.id.uuidString)
        modelContext.delete(capsule)
        dismiss()
    }
}

extension Notification.Name {
    static let sealOneBack = Notification.Name("sealOneBack")
}

#Preview("received capsule — sealed") {
    NavigationStack {
        SealedCapsuleView(capsule: {
            let c = Capsule(
                title: "birthday surprise",
                type: .photo,
                textContent: nil,
                unlocksAt: Date.now.addingTimeInterval(86400),
                senderName: "sarah"
            )
            return c
        }())
    }
    .modelContainer(for: Capsule.self, inMemory: true)
}

#Preview("received capsule — ready") {
    NavigationStack {
        SealedCapsuleView(capsule: {
            let c = Capsule(
                title: "for you",
                type: .text,
                textContent: "hey, just wanted to say I'm proud of you.",
                unlocksAt: Date.now.addingTimeInterval(-60),
                senderName: "max"
            )
            return c
        }())
    }
    .modelContainer(for: Capsule.self, inMemory: true)
}
