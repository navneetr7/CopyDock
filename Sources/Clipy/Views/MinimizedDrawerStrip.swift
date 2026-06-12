import SwiftUI

struct MinimizedDrawerStrip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Clipy")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Click to open · Press and hold, then drag to move")
    }
}