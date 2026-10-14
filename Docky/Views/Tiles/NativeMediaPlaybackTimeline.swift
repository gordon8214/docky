import AppKit
import Combine

/// The clock updates existing controls, preserving keyboard focus on playback buttons.
final class NativeMediaPlaybackTimeline: NSView {
    private let state: MediaPlaybackState
    private let lyrics: LyricsContent?
    private let timeLabel = nativeLabel("")
    private let progress = NSProgressIndicator()
    let scroll = NSScrollView()
    private let document = NativeScrollDocumentView()
    private let stack = NSStackView()
    private var lines: [NSTextField] = []
    private var selectedLine: Int?
    private var needsInitialScroll = true
    private var timer: AnyCancellable?
    init(state: MediaPlaybackState, lyrics: LyricsContent? = nil) {
        self.state = state
        self.lyrics = lyrics
        super.init(frame: .zero)
        if let lyrics {
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.documentView = document
            document.addSubview(stack)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            let texts = lyrics.lines.isEmpty ? [lyrics.plain] : lyrics.lines.map(\.text)
            lines = texts.map { nativeLabel($0, size: 14) }
            for line in lines {
                line.maximumNumberOfLines = 0
                line.lineBreakMode = .byWordWrapping
                stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            addSubview(scroll)
            heightAnchor.constraint(equalToConstant: 160).isActive = true
        } else {
            progress.isIndeterminate = false
            progress.minValue = 0
            progress.maxValue = max(1, state.duration)
            progress.setAccessibilityLabel(String(localized: "Playback Progress"))
            addSubview(timeLabel)
            addSubview(progress)
            heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        updateClock()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer = nil
        needsInitialScroll = true
        needsLayout = true
        if window != nil {
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.updateClock() }
        }
    }
    override func layout() {
        super.layout()
        if lyrics != nil {
            scroll.frame = bounds
            let width = max(0, scroll.contentSize.width - 8)
            for line in lines { line.preferredMaxLayoutWidth = width }
            stack.frame = CGRect(x: 4, y: 0, width: width, height: stack.fittingSize.height)
            stack.layoutSubtreeIfNeeded()
            stack.frame.size.height = stack.fittingSize.height
            document.frame.size = CGSize(
                width: scroll.contentSize.width, height: max(bounds.height, stack.frame.height))
            scrollCurrentLineIfNeeded()
        } else {
            timeLabel.frame = CGRect(x: 0, y: 14, width: bounds.width, height: 20)
            progress.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 12)
        }
    }
    private func updateClock() {
        let currentTime = state.estimatedCurrentTime
        timeLabel.stringValue =
            NativeWidgetView.playbackTime(currentTime) + " / "
            + NativeWidgetView.playbackTime(state.duration)
        progress.doubleValue = currentTime
        guard let lyrics, !lyrics.lines.isEmpty else { return }
        let index = lyrics.lines.lastIndex(where: { $0.time <= currentTime })
        if index != selectedLine {
            selectedLine = index
            needsInitialScroll = true
            for (offset, label) in lines.enumerated() {
                label.textColor = offset == index ? .labelColor : .secondaryLabelColor
            }
        }
        if needsInitialScroll { needsLayout = true }
    }
    private func scrollCurrentLineIfNeeded() {
        guard needsInitialScroll, let index = selectedLine, lines.indices.contains(index),
            scroll.contentSize.width > 0, scroll.contentSize.height > 0, lines[index].bounds.height > 0 else { return }
        lines[index].scrollToVisible(lines[index].bounds)
        needsInitialScroll = false
    }
}
