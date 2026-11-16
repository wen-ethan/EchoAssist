//
//  SplitLayout.swift
//  EchoAssist
//
//  Decides when a list screen shows its detail beside it rather than pushed
//  over it. Shared so every list screen switches layouts at the same point.
//

import SwiftUI

extension View {
    /// Keeps `usesSplitLayout` true while this view has room for a list and
    /// its detail side by side: a regular-width size class *and* more width
    /// than height. A tall screen, even a wide one, stays a single column like
    /// a phone.
    ///
    /// Measured from the view's own frame rather than the device orientation,
    /// so it tracks window resizes and the iPhone Duo folding and unfolding.
    ///
    /// Pass `requiresRegularWidth: false` for a layout that works at any
    /// width and only cares about the shape — e.g. one that moves controls
    /// beside content when height runs short on an iPhone in landscape.
    func onSplitLayoutChange(
        _ usesSplitLayout: Binding<Bool>,
        requiresRegularWidth: Bool = true
    ) -> some View {
        modifier(SplitLayoutReader(
            usesSplitLayout: usesSplitLayout, requiresRegularWidth: requiresRegularWidth))
    }
}

private struct SplitLayoutReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var usesSplitLayout: Bool
    let requiresRegularWidth: Bool
    @State private var isLandscape = false

    private var fits: Bool {
        isLandscape && (!requiresRegularWidth || horizontalSizeClass == .regular)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width > proxy.size.height
            } action: { isWider in
                isLandscape = isWider
            }
            .onChange(of: fits, initial: true) { _, fits in
                usesSplitLayout = fits
            }
    }
}
