import SwiftUI
import AppKit

struct MinimizedDrawerStrip: View {
    var body: some View {
        Group {
            if let img = Bundle.main.image(forResource: "clipy_pill") {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Click to open · Press and hold, then drag to move")
    }
}