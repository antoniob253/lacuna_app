import SwiftUI
import UIKit

struct TextContentEditor: View {
    @Binding var textContent: String
    /// When true, the underlying UITextView grabs first responder shortly after
    /// mount — used by surfaces like `QuickCaptureView` that want to drop the
    /// user straight into typing with no intermediate tap.
    var autoFocus: Bool = false
    @State private var isFocused = false
    @State private var boldActive = false
    @State private var italicActive = false
    @State private var textView: UITextView?
    @State private var formatTrigger = false
    @State private var doneTapTrigger = false

    // MARK: - Writing prompts
    /// Index into `WritingPrompts.all` for the currently shown prompt.
    /// `-1` is the "not yet picked" sentinel — replaced on first onAppear.
    @State private var promptIndex = -1
    /// Persisted across sessions so the next launch never opens with the
    /// same prompt that was just shown last time.
    @AppStorage("lastWritingPromptIndex") private var lastPromptIndex = -1
    @State private var promptBreathing = false
    @State private var swapTrigger = false

    /// The prompt + swap-affordance only appear when the editor is empty AND
    /// unfocused — i.e., the same condition as a traditional placeholder. Once
    /// the user taps in to write, both disappear.
    private var showsPrompt: Bool {
        textContent.isEmpty && !isFocused
    }

    var body: some View {
        VStack(spacing: 14) {
            // — editor card —
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if showsPrompt {
                        Text(WritingPrompts.prompt(at: promptIndex))
                            .font(.body)
                            .fontDesign(.serif)
                            .tracking(Design.trackingNormal)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                            // .id() forces SwiftUI to treat each prompt as a
                            // distinct view, so the cross-fade transition fires
                            // when the swap button bumps `promptIndex`.
                            .id(promptIndex)
                            .transition(.opacity)
                    }

                    RichTextEditor(
                        text: $textContent,
                        isFocused: $isFocused,
                        boldActive: $boldActive,
                        italicActive: $italicActive,
                        textViewRef: $textView,
                        autoFocus: autoFocus
                    )
                    .frame(minHeight: 180)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Divider().overlay(Design.divider)

                HStack(spacing: 8) {
                    Button { formatTrigger.toggle(); toggleTrait(.traitBold) } label: {
                        Text("B")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(boldActive ? Design.bg : .secondary)
                            .frame(width: 32, height: 28)
                            .background(boldActive ? Color.primary : .clear)
                            .clipShape(.rect(cornerRadius: Design.radiusSmall))
                    }
                    .buttonStyle(.plain)

                    Button { formatTrigger.toggle(); toggleTrait(.traitItalic) } label: {
                        Text("I")
                            .font(Font(UIFont(descriptor: UIFont.systemFont(ofSize: 15, weight: .regular).fontDescriptor.withDesign(.serif)!.withSymbolicTraits(.traitItalic)!, size: 15)))
                            .foregroundStyle(italicActive ? Design.bg : .secondary)
                            .frame(width: 32, height: 28)
                            .background(italicActive ? Color.primary : .clear)
                            .clipShape(.rect(cornerRadius: Design.radiusSmall))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isFocused {
                        Button { doneTapTrigger.toggle(); textView?.resignFirstResponder() } label: {
                            Text("done")
                                .font(.subheadline.weight(.medium))
                                .tracking(Design.trackingNormal)
                                .foregroundStyle(Design.bg)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.primary)
                                .clipShape(.rect(cornerRadius: Design.radiusSmall))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .sensoryFeedback(.selection, trigger: formatTrigger)
                .sensoryFeedback(.impact(weight: .light), trigger: doneTapTrigger)
            }
            .background(Design.surface)
            .clipShape(.rect(cornerRadius: Design.radiusMedium))
            .overlay {
                RoundedRectangle(cornerRadius: Design.radiusMedium)
                    .strokeBorder(Design.border, lineWidth: 1)
            }

            // — ✦ another — breathing swap affordance, below the card.
            // Visible only when the prompt itself is visible. A single tap
            // cross-fades to a fresh prompt, never repeating the current one.
            if showsPrompt {
                Button {
                    swapTrigger.toggle()
                    let newIndex = WritingPrompts.nextIndex(excluding: promptIndex)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        promptIndex = newIndex
                    }
                    lastPromptIndex = newIndex
                } label: {
                    Text("✦ another")
                        .font(.caption)
                        .tracking(Design.trackingWide)
                        .foregroundStyle(.primary.opacity(promptBreathing ? 0.30 : 0.55))
                        // Pin to a single line at natural width — animating
                        // opacity on a tracked Text makes SwiftUI re-measure the
                        // glyph run each frame, which shifts the centered
                        // position left↔right. fixedSize locks the width.
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: swapTrigger)
                .accessibilityLabel("another prompt")
                .accessibilityHint("shows a different writing prompt")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsPrompt)
        .onAppear {
            // First mount: pick a prompt that isn't the one the user last saw.
            if promptIndex < 0 {
                let firstIdx = WritingPrompts.nextIndex(excluding: lastPromptIndex)
                promptIndex = firstIdx
                lastPromptIndex = firstIdx
            }
            // Start the slow breathing pulse on the swap affordance.
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                promptBreathing = true
            }
        }
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }

        let baseFont = Design.editorBaseFont
        let range = tv.selectedRange

        if range.length > 0 {
            // Selection exists — toggle trait on selected text
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                guard let font = value as? UIFont else { return }
                let currentTraits = font.fontDescriptor.symbolicTraits
                var newTraits = currentTraits
                if currentTraits.contains(trait) {
                    newTraits.remove(trait)
                } else {
                    newTraits.insert(trait)
                }
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits) ?? baseFont.fontDescriptor
                let newFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
                mutable.addAttribute(.font, value: newFont, range: subRange)
            }
            tv.attributedText = mutable
            tv.selectedRange = range

            // Sync to binding
            textContent = Design.nsAttributedStringToMarkdown(tv.attributedText)
        } else {
            // No selection — toggle typing attributes for next input
            var attrs = tv.typingAttributes
            let currentFont = attrs[.font] as? UIFont ?? baseFont
            let currentTraits = currentFont.fontDescriptor.symbolicTraits
            var newTraits = currentTraits
            if currentTraits.contains(trait) {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(newTraits) ?? baseFont.fontDescriptor
            attrs[.font] = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            tv.typingAttributes = attrs
        }

        // Update button states
        updateTraitStates(from: tv)
    }

    private func updateTraitStates(from tv: UITextView) {
        let font = tv.typingAttributes[.font] as? UIFont ?? Design.editorBaseFont
        let traits = font.fontDescriptor.symbolicTraits
        boldActive = traits.contains(.traitBold)
        italicActive = traits.contains(.traitItalic)
    }
}

// MARK: - UITextView wrapper

private struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var boldActive: Bool
    @Binding var italicActive: Bool
    @Binding var textViewRef: UITextView?
    /// If true, the text view requests first responder shortly after mount so
    /// the keyboard rises immediately — used by `QuickCaptureView`.
    var autoFocus: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Builds the keyboard accessory bar: full-width cream surface, a 1pt top
    /// hairline, and a right-aligned angular black "done" button — matching the
    /// app's zero-radius design language. Sits flush above the keyboard.
    private static func makeAccessoryView(target: Any, action: Selector) -> UIView {
        // Width is a placeholder — `.flexibleWidth` lets the system stretch the
        // bar to the keyboard's width once attached, so the literal value here
        // doesn't matter.
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        bar.autoresizingMask = [.flexibleWidth]
        bar.backgroundColor = UIColor(named: "CremeBackground")

        // Top hairline — separates the bar from the content above it.
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        bar.addSubview(divider)

        // "done" — filled, zero corner radius (angular, on-brand).
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor(named: "CremeForeground")
        config.baseForegroundColor = UIColor(named: "CremeBackground")
        config.background.cornerRadius = 0
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18)
        var titleContainer = AttributeContainer()
        titleContainer.font = .systemFont(ofSize: 15, weight: .medium)
        config.attributedTitle = AttributedString("done", attributes: titleContainer)

        let done = UIButton(configuration: config)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addTarget(target, action: action, for: .touchUpInside)
        bar.addSubview(done)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: bar.topAnchor),
            divider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            done.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.delegate = context.coordinator
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.typingAttributes = Design.editorBaseAttributes
        textView.keyboardDismissMode = .interactive

        // Always-visible "done" bar above the keyboard. Custom view (not a
        // UIToolbar) so it matches the app exactly: a full-width cream bar with
        // a top hairline and an angular black "done" rectangle. A UIToolbar's
        // `.prominent` bar button renders as a floating rounded capsule on
        // iOS 26, which clashes with the app's zero-radius aesthetic.
        textView.inputAccessoryView = Self.makeAccessoryView(
            target: context.coordinator,
            action: #selector(Coordinator.dismissKeyboard)
        )

        // Load initial text as rich text from markdown
        if !text.isEmpty {
            textView.attributedText = Design.markdownToNSAttributedString(text)
        }

        DispatchQueue.main.async {
            textViewRef = textView
        }

        context.coordinator.textView = textView

        // Auto-focus: wait for the sheet presentation animation to settle, then
        // request first responder so the keyboard rises cleanly instead of
        // racing the sheet transition.
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard !context.coordinator.isUpdatingFromUIKit else { return }
        // No external text sync needed — all edits happen through UITextView directly
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var isUpdatingFromUIKit = false
        weak var textView: UITextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            isUpdatingFromUIKit = true
            parent.text = Design.nsAttributedStringToMarkdown(textView.attributedText)
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromUIKit = false
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Update bold/italic button states based on current cursor position
            let font = textView.typingAttributes[.font] as? UIFont ?? Design.editorBaseFont
            let traits = font.fontDescriptor.symbolicTraits
            DispatchQueue.main.async { [weak self] in
                self?.parent.boldActive = traits.contains(.traitBold)
                self?.parent.italicActive = traits.contains(.traitItalic)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.isFocused = false
            }
        }

        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }
    }
}
