import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Path { path in
                    let points = normalizedPoints(in: geometry.size)
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    let points = normalizedPoints(in: geometry.size)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let data = values.isEmpty ? [0, 0] : (values.count == 1 ? [values[0], values[0]] : values)
        let maximum = max(data.max() ?? 0, 1)
        let step = size.width / CGFloat(max(data.count - 1, 1))

        return data.enumerated().map { index, value in
            let normalized = min(max(value / maximum, 0), 1)
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(normalized) * max(size.height - 3, 1)) - 1.5
            )
        }
    }
}
