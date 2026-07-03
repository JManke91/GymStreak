//
//  MiniSparkline.swift
//  GymStreak
//

import SwiftUI

/// Lightweight sparkline used on exercise rows in the Fortschritt tab.
/// Renders a filled area + stroked line, no axis/labels.
struct MiniSparkline: View {
    let data: [Double]
    var width: CGFloat = 56
    var height: CGFloat = 20
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            let minV = data.min() ?? 0
            let maxV = data.max() ?? 1
            let range = maxV - minV == 0 ? 1 : maxV - minV
            let step = size.width / CGFloat(data.count - 1)
            let padV: CGFloat = 2
            let usableH = size.height - padV * 2

            var line = Path()
            var area = Path()
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * step
                let norm = CGFloat((value - minV) / range)
                let y = padV + (1 - norm) * usableH
                if index == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                    area.move(to: CGPoint(x: x, y: size.height))
                    area.addLine(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                    area.addLine(to: CGPoint(x: x, y: y))
                }
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(color), lineWidth: 1.6)
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    MiniSparkline(data: [5, 7, 6, 9, 11, 10, 13, 14])
        .padding()
        .background(DesignSystem.Colors.background)
        .preferredColorScheme(.dark)
}
