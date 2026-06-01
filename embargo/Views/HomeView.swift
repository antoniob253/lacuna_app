import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(StoreManager.self) private var storeManager
    @Query(sort: \Capsule.createdAt, order: .reverse) private var allCapsules: [Capsule]
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.automatic.rawValue
    @State private var showCreateSheet = false
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var capsuleToDelete: Capsule?
    @State private var createTrigger = false
    @State private var settingsTrigger = false
    @State private var archiveTrigger = false
    @State private var navigationPath = NavigationPath()
    @State private var rowTapTrigger = false
    @State private var showAllSent = false
    @State private var appeared = false
    @State private var showQuickCapture = false
    @State private var quickCaptureTrigger = false
    @State private var letterPaywall: PaywallReason?
    @State private var letterBreathing = false
    @State private var letterPressed = false
    /// Initial `true` means the shockwave overlay starts at its "expanded +
    /// invisible" state, so it's hidden by default. A tap snaps it to `false`
    /// (visible at pill size) then animates it back to `true`.
    @State private var letterShockExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("pendingFirstCapsule") private var pendingFirstCapsule = false

    /// Count of active sealed text capsules the user has created locally —
    /// the free-tier limit is 3. Mirrored from `CreateCapsuleView`'s logic
    /// because the "letter to tomorrow" path bypasses the normal type-select
    /// gate, so we need to enforce the same limit here.
    private var activeSealedTextCount: Int {
        allCapsules.filter { $0.isLocal && $0.isSealed && $0.type == .text }.count
    }

    private var canCreateLetter: Bool {
        storeManager.isPro || activeSealedTextCount < 3
    }

    // MARK: - Filtered sections (active capsules only)

    private func readyCapsules(now: Date) -> [Capsule] {
        allCapsules
            .filter { $0.isLocal && $0.isSealed && now >= $0.unlocksAt }
            .sorted { $0.unlocksAt < $1.unlocksAt }
    }

    private func receivedCapsules(now: Date) -> [Capsule] {
        allCapsules
            .filter { $0.isReceived && $0.isSealed }
            .sorted { $0.unlocksAt < $1.unlocksAt }
    }

    private func sealedCapsules(now: Date) -> [Capsule] {
        allCapsules
            .filter { $0.isLocal && $0.isSealed && now < $0.unlocksAt }
            .sorted { $0.unlocksAt < $1.unlocksAt }
    }

    private var sentCapsules: [Capsule] {
        allCapsules
            .filter { $0.isSent && $0.isSealed }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Are there any active (non-opened) capsules to show?
    private var hasActiveCapsules: Bool {
        allCapsules.contains { $0.isSealed || $0.isSent }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Leading space compensates for the trailing kerning whitespace
                // that `.kerning(Design.trackingWide)` adds after every letter,
                // so the wide-tracked title sits visually centered. Don't remove.
                Text(storeManager.isPro ? " lacuna +" : " lacuna")
                    .font(.title3.weight(.medium))
                    .kerning(Design.trackingWide)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if !hasActiveCapsules {
                    if pendingFirstCapsule {
                        // Hide empty state during onboarding→create transition
                        Design.bg.ignoresSafeArea()
                    } else {
                        EmptyStateView(onIconTap: { showCreateSheet = true })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Cross-fade with the list when the user opens their
                            // last sealed capsule — the empty state should
                            // ease in, not pop in.
                            .transition(.opacity)
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let now = context.date
                        let ready = readyCapsules(now: now)
                        let received = receivedCapsules(now: now)
                        let sealed = sealedCapsules(now: now)
                        let sent = sentCapsules

                        List {
                            // 1. Ready — most urgent (no header, tagged inline)
                            if !ready.isEmpty {
                                capsuleRows(ready)
                            }

                            // 2. Received — from friends (sealed only)
                            if !received.isEmpty {
                                sectionHeader("received", isFirst: ready.isEmpty)
                                capsuleRows(received)
                            }

                            // 3. Sealed — your own, still waiting
                            if !sealed.isEmpty {
                                sectionHeader("sealed", isFirst: ready.isEmpty && received.isEmpty)
                                capsuleRows(sealed)
                            }

                            // 4. Sent — collapsed to 3
                            if !sent.isEmpty {
                                sectionHeader("sent", isFirst: ready.isEmpty && received.isEmpty && sealed.isEmpty)

                                let displayed = showAllSent ? sent : Array(sent.prefix(3))
                                capsuleRows(displayed, showSentLabel: false)

                                if sent.count > 3 {
                                    Button {
                                        withAnimation(Design.springSnappy) { showAllSent.toggle() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(showAllSent ? "show less" : "show all (\(sent.count))")
                                                .font(.caption)
                                                .tracking(Design.trackingNormal)
                                            Image(systemName: showAllSent ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 8, weight: .medium))
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // Bottom margin large enough that the last capsule row,
                    // when the user fully scrolls down, rests JUST above the
                    // "letter to tomorrow" pill (pill top sits ~131pt above
                    // safe-area bottom). 150pt gives a touch of breathing
                    // room above the pill — no overlap.
                    .contentMargins(.bottom, 150, for: .scrollContent)
                    .mask(
                        VStack(spacing: 0) {
                            Color.black
                            // Fade gradient widened to 150pt so any row that
                            // scrolls behind the pill during mid-scroll is
                            // already well-faded by the time it gets there.
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 150)
                        }
                    )
                    // Matches the EmptyStateView transition so the swap is a
                    // smooth fade rather than an instant pop when the user's
                    // capsule set collapses to zero (or grows from zero).
                    .transition(.opacity)
                }
            }
            // Scoped to `hasActiveCapsules` so the cross-fade only fires when
            // the list↔empty-state branch swaps. Other state changes inside
            // this view tree don't inherit this animation.
            .animation(.easeInOut(duration: 0.45), value: hasActiveCapsules)
            .background(Design.bg.ignoresSafeArea())
            .onAppear {
                appeared = true
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Capsule.self) { capsule in
                if capsule.isOpened {
                    OpenedCapsuleView(capsule: capsule)
                } else {
                    SealedCapsuleView(capsule: capsule)
                }
            }
            .onChange(of: navigationPath) {
                rowTapTrigger.toggle()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: rowTapTrigger)
            .overlay(alignment: .bottom) {
                VStack(spacing: 12) {
                    // "✦ a letter to tomorrow" — quiet daily-ritual entry point.
                    // Breathes like the existing whispers, but tappable. Routes
                    // to QuickCaptureView, or to the paywall when the free-tier
                    // text-capsule limit is hit (subtle lock badge then signals
                    // the gate before the tap).
                    letterToTomorrowWhisper

                    // Existing toolbar — settings, archive, create
                    HStack(alignment: .bottom, spacing: 16) {
                        Spacer()

                        Button {
                            settingsTrigger.toggle()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Design.bg)
                                .frame(width: 44, height: 44)
                                .background(Design.fg)
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: settingsTrigger)

                        Button {
                            archiveTrigger.toggle()
                            showArchive = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Design.bg)
                                .frame(width: 44, height: 44)
                                .background(Design.fg)
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: archiveTrigger)

                        Button {
                            createTrigger.toggle()
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Design.bg)
                                .frame(width: 52, height: 52)
                                .background(Design.fg)
                                .clipShape(.circle)
                                .overlay {
                                    AddButtonPulse()
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 32)
                .sensoryFeedback(.impact(weight: .medium), trigger: createTrigger)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(notificationManager)
                    .environment(storeManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCapsuleView()
                    .environment(notificationManager)
                    .environment(storeManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .sheet(isPresented: $showArchive) {
                ArchiveView()
                    .environment(notificationManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .sheet(isPresented: $showQuickCapture) {
                QuickCaptureView()
                    .environment(notificationManager)
                    .environment(storeManager)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .sheet(item: $letterPaywall) { reason in
                PaywallView(storeManager: storeManager, reason: reason)
                    .preferredColorScheme(AppearanceResolver.resolve(rawValue: appearanceMode))
            }
            .confirmationDialog(
                "let it go?",
                isPresented: Binding(
                    get: { capsuleToDelete != nil },
                    set: { if !$0 { capsuleToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("annihilate", role: .destructive) {
                    if let capsule = capsuleToDelete {
                        deleteCapsule(capsule)
                    }
                }
            } message: {
                Text("this moment will be lost in time. like tears in the rain. there is no undoing this.")
            }
            .sensoryFeedback(.warning, trigger: capsuleToDelete)
            .onChange(of: pendingFirstCapsule) { _, pending in
                if pending {
                    Task { @MainActor in
                        // Wait for fullScreenCover dismiss animation to complete
                        try? await Task.sleep(for: .milliseconds(350))
                        pendingFirstCapsule = false
                        showCreateSheet = true
                    }
                }
            }
            .onChange(of: notificationManager.pendingCapsuleID) { _, capsuleID in
                guard let capsuleID else { return }
                guard let capsule = allCapsules.first(where: { $0.id.uuidString == capsuleID }) else {
                    notificationManager.pendingCapsuleID = nil
                    return
                }

                showSettings = false
                showCreateSheet = false
                showArchive = false

                navigationPath = NavigationPath()

                // Sheets dismiss in ~350ms; 450ms gives a touch of breathing
                // room without making the user wait perceptibly.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    navigationPath.append(capsule)
                    notificationManager.pendingCapsuleID = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sealOneBack)) { _ in
                // Delay to let the reveal dismiss complete
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    showCreateSheet = true
                }
            }
        }
    }

    // MARK: - "✦ a letter to tomorrow" pill

    @ViewBuilder
    private var letterToTomorrowWhisper: some View {
        Button {
            quickCaptureTrigger.toggle()  // fires haptic + shockwave
            // Press squeeze: 120ms in → completion → 180ms back. The sheet
            // (or paywall) opens on the completion edge so the user sees the
            // visual response land before the next surface rises.
            withAnimation(.easeInOut(duration: 0.12)) {
                letterPressed = true
            } completion: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    letterPressed = false
                }
                if canCreateLetter {
                    showQuickCapture = true
                } else {
                    // Same paywall reason as the type-select "text limit" gate
                    // so the user sees consistent messaging across both paths.
                    letterPaywall = .textLimit
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("✦ a letter to tomorrow")
                    .font(.caption)
                    .tracking(Design.trackingWide)
                    .foregroundStyle(.primary.opacity(letterBreathing ? 0.55 : 0.85))
                    // Pin to a single line at natural width — animating opacity
                    // on a wrapped, tracked Text causes the wrap point to
                    // micro-shift each frame, making the trailing line wobble.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if !canCreateLetter {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary.opacity(letterBreathing ? 0.45 : 0.70))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            // Angular outline — same geometric language as Design.radius* (0).
            // The breathing border is the resting affordance: a pure whisper
            // reads as ambient text, an outlined pill reads as a control.
            .overlay {
                Rectangle()
                    .strokeBorder(
                        Color.primary.opacity(letterBreathing ? 0.18 : 0.35),
                        lineWidth: 1
                    )
            }
            // Tap shockwave — a second rectangle that snaps to the pill's exact
            // bounds at tap moment, then expands outward (1.4×) and fades.
            // Like dropping a stone into still water, but rectangular to match
            // the pill's geometry.
            .overlay {
                Rectangle()
                    .stroke(Color.primary.opacity(0.55), lineWidth: 1.5)
                    .scaleEffect(letterShockExpanded ? 1.4 : 1.0)
                    .opacity(letterShockExpanded ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onChange(of: quickCaptureTrigger) {
                        guard !reduceMotion else { return }
                        // Snap to "ready to animate" instantly, without
                        // animation — otherwise the reset would itself animate
                        // and we'd see the rectangle flying inward first.
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { letterShockExpanded = false }
                        withAnimation(.easeOut(duration: 0.55)) {
                            letterShockExpanded = true
                        }
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(letterPressed ? 0.96 : 1.0)
        .sensoryFeedback(.impact(weight: .medium), trigger: quickCaptureTrigger)
        .accessibilityLabel(canCreateLetter ? "a letter to tomorrow" : "a letter to tomorrow (requires lacuna +)")
        .accessibilityHint("seal a thought that opens tomorrow")
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                letterBreathing = true
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, isFirst: Bool) -> some View {
        Text(title)
            .font(.caption)
            .tracking(Design.trackingWide)
            .foregroundStyle(.primary.opacity(0.5))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: isFirst ? 12 : 24, leading: 20, bottom: 6, trailing: 20))
    }

    private func capsuleRows(_ capsules: [Capsule], showSentLabel: Bool = true) -> some View {
        ForEach(capsules.enumerated(), id: \.element.id) { index, capsule in
            NavigationLink(value: capsule) {
                CapsuleRowView(capsule: capsule, showSentLabel: showSentLabel)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.05), value: appeared)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("delete", systemImage: "trash", role: .destructive) {
                    capsuleToDelete = capsule
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func deleteCapsule(_ capsule: Capsule) {
        NotificationManager.cancelCapsuleNotification(id: capsule.id.uuidString)
        modelContext.delete(capsule)
        capsuleToDelete = nil
    }
}

