import SwiftUI

struct CapsuleRowView: View {
    let capsule: Capsule
    var showSentLabel = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let isReady = capsule.isSealed && now >= capsule.unlocksAt

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: capsule.type.iconName)
                        .font(.body.weight(.light))
                        .foregroundStyle(Design.bg)
                        .frame(width: 36, height: 36)
                        .background(Color.primary)
                        .clipShape(.circle)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(capsule.title.isEmpty ? capsule.type.label : capsule.title)
                            .font(.body.weight(.medium))
                            .tracking(Design.trackingNormal)
                            .lineLimit(1)

                        // Social label
                        if let sender = capsule.senderName {
                            Text("from \(sender)")
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.6))
                                .tracking(Design.trackingTight)
                        } else if capsule.isSent && showSentLabel {
                            Text("sent")
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.6))
                                .tracking(Design.trackingTight)
                        }

                        // Status line
                        if capsule.isOpened {
                            Text("opened \(Design.formatDateShort(capsule.openedAt ?? capsule.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .tracking(Design.trackingTight)
                        } else if isReady {
                            ReadyPulseText()
                        } else {
                            RowCountdown(targetDate: capsule.unlocksAt, now: now)
                        }
                    }

                    Spacer()

                    if capsule.isSealed {
                        Image(systemName: isReady ? "lock.open" : "lock")
                            .font(.caption2.weight(.light))
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 8)

                // Progress bar for sealed (non-ready) capsules
                if capsule.isSealed && !isReady {
                    RowProgressBar(
                        createdAt: capsule.createdAt,
                        unlocksAt: capsule.unlocksAt,
                        now: now
                    )
                }
            }
            .contentShape(.rect)
        }
    }
}

// MARK: - Ready pulse text

private struct ReadyPulseText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Text("ready")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Design.bg)
            .tracking(Design.trackingNormal)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary)
            .clipShape(.rect(cornerRadius: Design.radiusSmall))
            // Live up to the component's name: a subtle breathing scale + dim
            // so ready capsules visibly call attention in the list.
            .scaleEffect(breathing ? 1.04 : 1.0)
            .opacity(breathing ? 0.85 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

// MARK: - Progress bar

private struct RowProgressBar: View {
    let createdAt: Date
    let unlocksAt: Date
    let now: Date

    private var progress: Double {
        let total = unlocksAt.timeIntervalSince(createdAt)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(createdAt)
        return min(max(elapsed / total, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1.5)

                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: geo.size.width * progress, height: 1.5)
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: 1.5)
        .padding(.leading, 52) // align with text (36pt icon + 16pt spacing)
    }
}

// MARK: - Countdown

private struct RowCountdown: View {
    let targetDate: Date
    let now: Date

    private var parts: (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let interval = max(0, targetDate.timeIntervalSince(now))
        let total = Int(interval)
        return (total / 86400, (total % 86400) / 3600, (total % 3600) / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 2) {
            if parts.days > 0 {
                countdownPart(parts.days, unit: "d")
                countdownPart(parts.hours, unit: "h")
                countdownPart(parts.minutes, unit: "m")
                countdownPart(parts.seconds, unit: "s")
            } else {
                countdownPart(parts.hours, unit: "h")
                countdownPart(parts.minutes, unit: "m")
                countdownPart(parts.seconds, unit: "s")
            }
        }
    }

    private func countdownPart(_ value: Int, unit: String) -> some View {
        HStack(spacing: 0) {
            Text("\(value)")
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(unit)
            Text(" ")
                .font(.system(size: 2))
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }
}
