//
//  SmartStackTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SmartStackTileView: View {
    let tile: SmartStackTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan

    @State private var selection = 0
    @State private var lastScrollAt: TimeInterval = 0
    @State private var accumulatedScrollOffset: CGFloat = 0
    @State private var showsPagingIndicator = false
    @State private var indicatorHideWorkItem: DispatchWorkItem?
    /// Mirrors `tile.widgets.map(\.identifier)` so the macOS 13 single-value
    /// `onChange(of:perform:)` form can recover the previous list on each
    /// fire (the new two-arg form that hands you old/new is macOS 14+).
    @State private var previousWidgetIdentifiers: [String] = []

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        SmartStackScrollHostingView(content: contentView) { deltaX, deltaY in
            handleScroll(deltaX: deltaX, deltaY: deltaY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: tile.widgets.map(\.identifier)) { _, newIdentifiers in
            let oldIdentifiers = previousWidgetIdentifiers
            previousWidgetIdentifiers = newIdentifiers
            if let newWidgetIdentifier = newIdentifiers.first(where: { !oldIdentifiers.contains($0) }),
               let newSelection = newIdentifiers.firstIndex(of: newWidgetIdentifier) {
                selection = newSelection
                showPagingIndicator()
            } else {
                selection = min(selection, max(0, newIdentifiers.count - 1))
            }

            if newIdentifiers.count <= 1 {
                hidePagingIndicator()
            }
        }
        .onAppear {
            previousWidgetIdentifiers = tile.widgets.map(\.identifier)
        }
        .onDisappear(perform: hidePagingIndicator)
    }

    @ViewBuilder
    private var contentView: some View {
        if tile.widgets.isEmpty {
            emptyState
        } else {
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    // Render only the currently-selected widget. Stacking
                    // every widget eagerly (even inside `LazyVStack`,
                    // which is only lazy inside a ScrollView) meant every
                    // widget's body re-evaluated on every service publish
                    // — Calendar's minute timer, MediaPlayback's now-
                    // playing tick, etc. — even though only one was
                    // visible. With `.id(widget.identifier)` SwiftUI
                    // swaps the view on selection change and the
                    // transition gives the same vertical-slide feel.
                    ZStack {
                        if let selectedWidget = selectedWidget {
                            WidgetTileView(
                                tile: selectedWidget,
                                cornerRadius: cornerRadius,
                                renderedSpan: renderedSpan,
                                isWithinStack: true
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(selectedWidget.identifier)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: selection)
                }
                .clipped()
                .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                .dockyGlassBorder(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .trailing) {
                    if tile.widgets.count > 1 {
                        VStack(spacing: 5) {
                            ForEach(tile.widgets.indices, id: \.self) { index in
                                Capsule(style: .continuous)
                                    .fill(index == selection ? Color.primary.opacity(0.9) : Color.primary.opacity(0.22))
                                    .frame(width: 3, height: index == selection ? 18 : 8)
                                    .animation(.easeInOut(duration: 0.18), value: selection)
                            }
                        }
                        .frame(width: 6)
                        .opacity(showsPagingIndicator ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: showsPagingIndicator)
                        .offset(x: 8)
                    }
                }
                .background {
                    Color
                        .primary.opacity(0.2)
                        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                        .padding(showsPagingIndicator ? -4 : 0)
                        .padding(.trailing, showsPagingIndicator ? -8 : 0)
                        .opacity(showsPagingIndicator ? 1 : 0)
                        .animation(.easeInOut(duration: 0.20), value: showsPagingIndicator)
                }
            }
        }
    }

    /// The widget currently in view. Falls back to the first widget if
    /// `selection` is out of range (can happen briefly while the widgets
    /// list is mutating).
    private var selectedWidget: WidgetTile? {
        if tile.widgets.indices.contains(selection) {
            return tile.widgets[selection]
        }
        return tile.widgets.first
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(0.12))
            .overlay {
                VStack(spacing: 4) {
                    Label("Smart Stack", systemImage: "square.stack.3d.up")
                        .font(.caption.weight(.semibold))
                    Text("No widgets available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
    }

    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard tile.widgets.count > 1 else {
            return false
        }

        let dominantDelta = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        guard dominantDelta != 0 else {
            return false
        }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastScrollAt > 0.2 else {
            return true
        }

        let threshold: CGFloat = 4
        accumulatedScrollOffset += dominantDelta

        if accumulatedScrollOffset <= -threshold {
            selection = min(selection + 1, tile.widgets.count - 1)
            lastScrollAt = now
            accumulatedScrollOffset = 0
            showPagingIndicator()
            return true
        }

        if accumulatedScrollOffset >= threshold {
            selection = max(selection - 1, 0)
            lastScrollAt = now
            accumulatedScrollOffset = 0
            showPagingIndicator()
            return true
        }

        return true
    }

    private func showPagingIndicator() {
        indicatorHideWorkItem?.cancel()
        showsPagingIndicator = true

        let workItem = DispatchWorkItem {
            showsPagingIndicator = false
            indicatorHideWorkItem = nil
        }

        indicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func hidePagingIndicator() {
        indicatorHideWorkItem?.cancel()
        indicatorHideWorkItem = nil
        accumulatedScrollOffset = 0
        showsPagingIndicator = false
    }
}

private struct SmartStackScrollHostingView<Content: View>: NSViewRepresentable {
    let content: Content
    let onScroll: (CGFloat, CGFloat) -> Bool

    func makeNSView(context: Context) -> ScrollHostingView<Content> {
        let view = ScrollHostingView(rootView: content)
        view.scrollHandler = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.scrollHandler = onScroll
    }
}

/// Generic `NSHostingView<Content>` subclass — the genericity lets
/// `NSHostingView`'s update path diff structurally against the previous
/// `rootView` instead of re-hosting the whole subtree on every parent
/// recompute (an `AnyView`-erased subclass triggers full rebuilds and
/// makes the smart stack unresponsive when many parents publish).
///
/// The explicit empty `deinit` is the workaround for a Swift 6.x
/// `EarlyPerfInliner` crash on the *synthesized* deinit of generic
/// NSHostingView subclasses at `-O`: writing the deinit ourselves
/// routes the optimizer through a different inlining path that
/// doesn't recurse in `isCallerAndCalleeLayoutConstraintsCompatible`.
/// Don't remove it without re-running an Archive build.
private final class ScrollHostingView<Content: View>: NSHostingView<Content> {
    var scrollHandler: ((CGFloat, CGFloat) -> Bool)?

    deinit { }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if scrollHandler?(event.scrollingDeltaX, event.scrollingDeltaY) == true {
            return
        }

        super.scrollWheel(with: event)
    }
}
