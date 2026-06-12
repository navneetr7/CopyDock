import AppKit
import SwiftUI


let clipyClearAllRed = Color(red: 0.86, green: 0.18, blue: 0.16)

struct ClipyVisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        if let layer = view.layer {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
    }
}

struct ClipyFrostedBackdrop: View {
    var cornerRadius: CGFloat = 0

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ClipyVisualEffectBlur(
                material: .hudWindow,
                blendingMode: .withinWindow,
                cornerRadius: cornerRadius
            )
            shape.fill(Color.black.opacity(0.14))
        }
        .clipShape(shape)
    }
}

struct ClipyFrostedDialogSurface: View {
    var cornerRadius: CGFloat = 16

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ClipyVisualEffectBlur(
                material: .popover,
                blendingMode: .withinWindow,
                cornerRadius: cornerRadius
            )
            shape.fill(Color.black.opacity(0.06))
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
        }
        .overlay {
            shape.inset(by: 0.75)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

struct ClipyClearAllPillLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(clipyClearAllRed))
    }
}

struct ClipyFrostedConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    var backdropCornerRadius: CGFloat = 0
    var maxWidth: CGFloat = 300
    var checkboxLabel: String? = nil
    var checkboxBinding: Binding<Bool>? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            ClipyFrostedBackdrop(cornerRadius: backdropCornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: backdropCornerRadius, style: .continuous))
                .onTapGesture { onCancel() }

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let label = checkboxLabel, let binding = checkboxBinding {
                    Toggle(isOn: binding) {
                        Text(label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.quaternary))
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        ClipyClearAllPillLabel(title: confirmTitle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: maxWidth)
            .background {
                ClipyFrostedDialogSurface(cornerRadius: 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}


enum ClipyGlass {
    static let categoryAnimation: Animation = {
        if #available(macOS 26.0, *) {
            return .bouncy(duration: 0.42)
        }
        return .spring(response: 0.38, dampingFraction: 0.82)
    }()

    static let gridAnimation: Animation = {
        if #available(macOS 26.0, *) {
            return .bouncy(duration: 0.45)
        }
        return .spring(response: 0.4, dampingFraction: 0.86)
    }()
}

extension View {
    @ViewBuilder
    func clipyCardBackground(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func clipyGridTransition<ID: Hashable>(id: ID) -> some View {
        if #available(macOS 26.0, *) {
            self
                .id(id)
                .transition(.blurReplace.combined(with: .scale(0.97)))
                .glassEffectTransition(.materialize)
        } else {
            self
                .id(id)
                .transition(.opacity.combined(with: .scale(0.98)))
        }
    }
}


struct DrawerPositionGlassPicker: View {
    @Binding var selection: UserSettings.DrawerPosition

    private let pillSpacing: CGFloat = 8
    private let pillHeight: CGFloat = 36
    private let rowInset: CGFloat = 6
    private let strokeInset: CGFloat = 0.75

    var body: some View {
        HStack(spacing: pillSpacing) {
            ForEach(UserSettings.DrawerPosition.allCases, id: \.self) { position in
                pillButton(for: position)
            }
        }
        .padding(rowInset)
        .frame(maxWidth: .infinity)
    }

    private func pillButton(for position: UserSettings.DrawerPosition) -> some View {
        let isSelected = selection == position

        return Button {
            withAnimation(ClipyGlass.categoryAnimation) {
                selection = position
            }
        } label: {
            Text(position.displayName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: pillHeight)
                .background {
                    if isSelected {
                        selectedPillBackground
                    }
                }
                .overlay {
                    Capsule()
                        .inset(by: strokeInset)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 1 : 0.5
                        )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(1)
    }

    private var selectedPillBackground: some View {
        ZStack {
            ClipyVisualEffectBlur(
                material: .popover,
                blendingMode: .withinWindow,
                cornerRadius: pillHeight / 2
            )
            Capsule()
                .fill(Color.accentColor.opacity(0.52))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.18),
                            Color.accentColor.opacity(0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .clipShape(Capsule())
        .shadow(color: Color.accentColor.opacity(0.35), radius: 5, y: 2)
    }
}


struct CategoryGlassPicker: View {
    @Binding var selectedCategory: ClipboardCategory?
    let counts: [ClipboardCategory: Int]

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if #available(macOS 26.0, *) {
                glassCategoryRow
            } else {
                legacyCategoryRow
            }
        }
    }

    @available(macOS 26.0, *)
    private var glassCategoryRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ClipboardCategory.displayOrder, id: \.self) { category in
                    categoryButton(for: category, usesGlass: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var legacyCategoryRow: some View {
        HStack(spacing: 8) {
            ForEach(ClipboardCategory.displayOrder, id: \.self) { category in
                categoryButton(for: category, usesGlass: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func categoryButton(for category: ClipboardCategory, usesGlass: Bool) -> some View {
        let isSelected = selectedCategory == category

        Button {
            withAnimation(ClipyGlass.categoryAnimation) {
                selectedCategory = isSelected ? nil : category
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                Text(category.rawValue)
                    .font(.caption.weight(.semibold))
                Text("\(counts[category, default: 0])")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .background {
            if usesGlass {
                if #available(macOS 26.0, *) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.clear)
                            .glassEffect(
                                .regular.tint(Color.accentColor.opacity(0.22)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .glassEffectID("categorySelection", in: selectionNamespace)
                    }
                }
            } else if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            }
        }
        .overlay {
            if !usesGlass {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}