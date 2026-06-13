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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Click to open · Press and hold, then drag to move")
    }
}