import SwiftUI

struct PlayheadView: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // 三角形頂部
            Triangle()
                .fill(Constants.playheadColor)
                .frame(width: 10, height: 6)

            // 垂直線
            Rectangle()
                .fill(Constants.playheadColor)
                .frame(width: Constants.playheadWidth, height: height - 6)
        }
    }
}

private struct Triangle: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
