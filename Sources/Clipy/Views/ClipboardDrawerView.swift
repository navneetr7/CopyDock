import SwiftUI
import AppKit


private let brandTextSize:         CGFloat = 17
private let headerHintTextSize:    CGFloat = brandTextSize * 0.7
private let categoryIconSpacing:   CGFloat = 10
private let brandToCategoryPad:    CGFloat = 14
private let drawerEdgeInset:       CGFloat = 12
private let drawerCornerRadius:    CGFloat = 18
private let emptyMessageFontSize:  CGFloat = 44
private let cardSpacing:           CGFloat = 4
private let scrollBarReserve:      CGFloat = 6
private let scrollBarHeight:       CGFloat = 2.5
private let scrollBarBottomPadding: CGFloat = 2
private let cardToScrollbarGap:    CGFloat = 5
private let cardAspectRatio:       CGFloat = 1.35
private let cardSizeScale:         CGFloat = 0.95
private let cardHoverPadding:      CGFloat = 5

private let cardHoverScale:        CGFloat = 1.035
private let cardShrinkScale:       CGFloat = 0.975
private let cardHoverAnimation:    Animation = .spring(response: 0.3, dampingFraction: 0.86)


enum DrawerSection: Hashable {
    case recent
    case pinned
    case category(ClipboardCategory)

    var title: String {
        switch self {
        case .recent: "Recent"
        case .pinned: "Pinned"
        case .category(let cat): cat.rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock.arrow.circlepath"
        case .pinned: "pin.fill"
        case .category(let cat): cat.systemImage
        }
    }

    static var displayOrder: [DrawerSection] {
        [.recent, .pinned] + ClipboardCategory.displayOrder.map { .category($0) }
    }
}

private struct CardLayout {
    let width: CGFloat
    let height: CGFloat
    let visibleCount: Int
}


struct ClipboardDrawerView: View {
    @State private var selectedSection: DrawerSection = .recent
    @State private var items: [ClipboardItem] = []
    @State private var isClearing = false
    @State private var clearIncludesPinned = false
    @State private var hoveredCardID: ClipboardItem.ID?
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool

    let onRestore:      (ClipboardItem) -> Bool
    let onDelete:       @MainActor (ClipboardItem) async -> Void
    let onTogglePin:    @MainActor (ClipboardItem) async -> Void
    let onClearAll:     @MainActor (Bool) async -> Void
    let loadItems:      @MainActor () async -> [ClipboardItem]
    let settings:       UserSettings

    var body: some View {
        edgeBarLayout
            .padding(.horizontal, drawerEdgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            if isClearing {
                ClipyFrostedConfirmationOverlay(
                    title: "Clear clipboard history?",
                    message: "This permanently deletes all saved clipboard items.",
                    confirmTitle: "Clear History",
                    backdropCornerRadius: drawerCornerRadius,
                    maxWidth: 420,
                    checkboxLabel: "Also clear pinned items",
                    checkboxBinding: $clearIncludesPinned,
                    onConfirm: {
                        let includePinned = clearIncludesPinned
                        isClearing = false
                        clearIncludesPinned = false
                        Task { await onClearAll(includePinned); await refreshItems() }
                    },
                    onCancel: {
                        isClearing = false
                        clearIncludesPinned = false
                    }
                )
                .transition(.opacity.combined(with: .scale(0.97)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: isClearing)
        .onReceive(NotificationCenter.default.publisher(for: .clipyDrawerWillShow)) { _ in
            selectedSection = .recent
            hoveredCardID = nil
            searchQuery = ""
            searchFocused = false
            Task { await refreshItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardItemsDidChange)) { _ in
            Task { await refreshItems() }
        }
        .task { await refreshItems() }
        .onChange(of: selectedSection) { _, _ in hoveredCardID = nil }
        .onChange(of: isClearing) { _, clearing in
            NotificationCenter.default.post(
                name: .clipyBlockAutoMinimize,
                object: nil,
                userInfo: ["blocked": clearing]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .clipyBlockAutoMinimize,
                object: nil,
                userInfo: ["blocked": false]
            )
        }
    }


    private func items(for section: DrawerSection) -> [ClipboardItem] {
        if !searchQuery.isEmpty {
            return items.filter { itemMatchesQuery($0) }
        }
        switch section {
        case .recent:   return Array(items.prefix(10))
        case .pinned:   return items.filter(\.isPinned)
        case .category(let cat): return Array(items.filter { $0.category == cat }.prefix(100))
        }
    }

    private func itemMatchesQuery(_ item: ClipboardItem) -> Bool {
        let q = searchQuery.lowercased()
        if item.preview.lowercased().contains(q) { return true }
        switch item.category {
        case .text, .link:
            return item.contents.contains { $0.stringValue?.lowercased().contains(q) == true }
        case .other, .doc:
            if let fileURL = dragFileURL(from: item.contents),
               fileURL.lastPathComponent.lowercased().contains(q) { return true }
            if let blobPath = item.contents.first(where: { $0.type == "clipy.blob" })?.stringValue {
                let filename = (blobPath as NSString).lastPathComponent
                if filename.lowercased().contains(q) { return true }
            }
            return false
        }
    }

    private func cardLayout(for size: CGSize) -> CardLayout {
        let chrome = scrollBarReserve + cardToScrollbarGap + cardHoverPadding * 2
        let h = max(80, size.height - chrome) * cardSizeScale
        let w = h * cardAspectRatio
        let visibleCount = max(4, Int((size.width + cardSpacing) / (w + cardSpacing)))
        return CardLayout(width: w, height: h, visibleCount: visibleCount)
    }

    private func refreshItems() async { items = await loadItems() }

    private func minimizeDrawer() {
        NotificationCenter.default.post(name: .minimizeClipyDrawer, object: nil)
    }

    private func restoreAndClose(_ item: ClipboardItem) {
        let success = onRestore(item)
        ClipyNotifier.notifyRestore(
            success: success,
            message: success ? ClipyNotifier.successMessage : ClipyNotifier.failureMessage
        )

        if success {
            minimizeDrawer()
        }
    }


    private var edgeBarLayout: some View {
        VStack(spacing: 0) {
            headerBar
            GeometryReader { geo in
                cardPanel(size: geo.size)
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, scrollBarBottomPadding)
        }
    }


    private var headerBar: some View {
        ZStack {
            if !searchFocused && searchQuery.isEmpty {
                Text("Click to copy · Right-click to pin · Drag to drop")
                    .font(.system(size: headerHintTextSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Clipy")
                        .font(.system(size: brandTextSize, weight: .bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: categoryIconSpacing) {
                        ForEach(DrawerSection.displayOrder, id: \.self) { section in
                            categoryIcon(for: section)
                        }
                    }
                    .padding(.leading, brandToCategoryPad)

                    searchPill
                        .padding(.leading, 6)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button { isClearing = true } label: {
                        ClipyClearAllPillLabel(title: "Clear History")
                    }
                    .buttonStyle(.plain)

                    MacTrafficLights(
                        onClose: { NotificationCenter.default.post(name: .closeClipyDrawer, object: nil) },
                        onMinimize: minimizeDrawer,
                        onZoom: { NotificationCenter.default.post(name: .openClipySettings, object: nil) }
                    )
                }
            }
        }
        .padding(.vertical, 8)
        .background {
            Button("") {
                if searchFocused || !searchQuery.isEmpty {
                    searchQuery = ""
                    searchFocused = false
                } else {
                    NotificationCenter.default.post(name: .closeClipyDrawer, object: nil)
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    private var searchPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(searchFocused || !searchQuery.isEmpty ? .primary : .secondary)

            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .focused($searchFocused)
                .frame(maxWidth: .infinity)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background {
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.75)
        }
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
    }


    private func categoryIcon(for section: DrawerSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            withAnimation(ClipyGlass.categoryAnimation) {
                selectedSection = section
            }
        } label: {
            Image(systemName: section.systemImage)
                .font(.system(size: brandTextSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(section.title)
    }


    @ViewBuilder
    private func cardPanel(size: CGSize) -> some View {
        let layout = cardLayout(for: size)
        let sectionItems = items(for: selectedSection)

        VStack(alignment: .leading, spacing: 0) {
            if sectionItems.isEmpty {
                emptyMessage(
                    !searchQuery.isEmpty        ? "No results for \"\(searchQuery)\"" :
                    selectedSection == .recent  ? "Copy something to get started" :
                    selectedSection == .pinned  ? "Right-click any item to pin it" :
                                                  "No items in this category"
                )
            } else {
                Spacer(minLength: 0)
                itemScrollRow(sectionItems, layout: layout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func flipAngle(for index: Int) -> Double {
        max(4, 14 - Double(index) * 1.1)
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: emptyMessageFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 24)
    }

    private func itemScrollRow(_ rowItems: [ClipboardItem], layout: CardLayout) -> some View {
        SleekHorizontalScrollView(
            showsIndicator: rowItems.count > layout.visibleCount,
            barReserve: scrollBarReserve
        ) {
            HStack(spacing: cardSpacing) {
                ForEach(Array(rowItems.enumerated()), id: \.element.id) { index, item in
                    itemCard(item, layout: layout, index: index)
                }
            }
            .padding(.horizontal, cardHoverPadding)
            .padding(.vertical, cardHoverPadding)
            .padding(.bottom, cardToScrollbarGap)
        }
        .frame(height: layout.height + scrollBarReserve + cardToScrollbarGap + cardHoverPadding * 2)
    }

    private func itemCard(_ item: ClipboardItem, layout: CardLayout, index: Int) -> some View {
        let isHovered = hoveredCardID == item.id
        let peerHovered = hoveredCardID != nil && !isHovered

        return RecentItemCard(
            item: item,
            cardWidth: layout.width,
            cardHeight: layout.height,
            flipAngle: flipAngle(for: index),
            isHovered: isHovered,
            onTap: { restoreAndClose(item) },
            onTogglePin: { Task { await onTogglePin(item); await refreshItems() } },
            onRemove: {
                if hoveredCardID == item.id { hoveredCardID = nil }
                Task {
                    await onDelete(item)
                    await refreshItems()
                }
            }
        )
        .frame(width: layout.width, height: layout.height)
        .scaleEffect(isHovered ? cardHoverScale : peerHovered ? cardShrinkScale : 1)
        .brightness(isHovered ? 0.04 : peerHovered ? -0.015 : 0)
        .zIndex(isHovered ? 1 : 0)
        .animation(cardHoverAnimation, value: hoveredCardID)
        .onHover { hovering in
            if hovering {
                hoveredCardID = item.id
            } else if hoveredCardID == item.id {
                hoveredCardID = nil
            }
        }
    }
}


private struct ScrollContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SleekHorizontalScrollTrack: View {
    let progress: CGFloat
    let thumbRatio: CGFloat
    let isVisible: Bool

    var body: some View {
        if isVisible {
            GeometryReader { geo in
                let inset: CGFloat = 2
                let trackWidth = max(geo.size.width - inset * 2, 0)
                let thumbWidth = max(20, trackWidth * min(max(thumbRatio, 0.08), 1))
                let travel = max(trackWidth - thumbWidth, 0)
                let clampedProgress = min(max(progress, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: scrollBarHeight)
                    Capsule()
                        .fill(Color.primary.opacity(0.34))
                        .frame(width: thumbWidth, height: scrollBarHeight)
                        .offset(x: inset + travel * clampedProgress)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, scrollBarBottomPadding)
            }
        }
    }
}

private struct SleekHorizontalScrollView<Content: View>: View {
    let showsIndicator: Bool
    let barReserve: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private var thumbRatio: CGFloat {
        guard contentWidth > 0 else { return 1 }
        return viewportWidth / contentWidth
    }

    private var scrollProgress: CGFloat {
        let maxOffset = max(contentWidth - viewportWidth, 1)
        return scrollOffset / maxOffset
    }

    var body: some View {
        GeometryReader { outer in
            ZStack(alignment: .bottomLeading) {
                ScrollView(.horizontal) {
                    content()
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: ScrollContentWidthKey.self, value: geo.size.width)
                                    .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("clipyHScroll")).minX)
                            }
                        )
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "clipyHScroll")
                .frame(height: max(0, outer.size.height - barReserve))

                SleekHorizontalScrollTrack(
                    progress: scrollProgress,
                    thumbRatio: thumbRatio,
                    isVisible: showsIndicator && contentWidth > viewportWidth + 1
                )
                .frame(width: outer.size.width, height: barReserve)
            }
            .onAppear { viewportWidth = outer.size.width }
            .onChange(of: outer.size.width) { _, newWidth in
                viewportWidth = newWidth
            }
            .onPreferenceChange(ScrollContentWidthKey.self) { contentWidth = $0 }
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = max(0, -$0) }
        }
    }
}
