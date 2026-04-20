import SwiftUI

/// A thin vertical strip on the right edge of the document viewer.
/// Shows a translucent viewport indicator that the user can drag to
/// scroll the document — the "zoomed-out" navigation handle.
struct ScrollMiniMapView: View {
    @Binding var scrollFraction: CGFloat   // 0…1, current top position
    @Binding var visibleFraction: CGFloat  // 0…1, fraction of doc visible
    let onDrag: (CGFloat) -> Void          // delivers new scrollFraction

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let indicatorH = max(24, visibleFraction * h)
            let maxTravel = max(0, h - indicatorH)
            let indicatorY = scrollFraction * maxTravel

            ZStack(alignment: .top) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemBackground).opacity(0.85))

                // Tick lines at 10 % intervals
                VStack(spacing: 0) {
                    ForEach(1..<10, id: \.self) { i in
                        Spacer()
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 0.5)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)

                // Viewport indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(isDragging ? 0.45 : 0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.accentColor.opacity(isDragging ? 0.8 : 0.5),
                                          lineWidth: 1)
                    )
                    .frame(height: indicatorH)
                    .offset(y: indicatorY)
                    .allowsHitTesting(false)
            }
            // Unified drag / tap gesture on the whole strip
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let rawFrac = (value.location.y - indicatorH / 2) / max(maxTravel, 1)
                        onDrag(max(0, min(1, rawFrac)))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(width: 18)
        .padding(.vertical, 10)
    }
}
