import SwiftUI

/// Minimal parser for the schematic body's path data.
///
/// The muscle-map geometry uses only absolute `M`, `L`, `C` and `Z` commands, so a
/// full SVG parser would be dead weight. Parsing is expensive enough that results are
/// only ever built once, into the `static let` storage in `MuscleMapGeometry` —
/// never inside a view `body`.
enum MuscleMapPathParser {

    static func path(from data: String) -> Path {
        var path = Path()
        var command: Character = " "
        var arguments: [CGFloat] = []
        var numberBuffer = ""

        func flushNumber() {
            guard !numberBuffer.isEmpty else { return }
            if let value = Double(numberBuffer) {
                arguments.append(CGFloat(value))
            }
            numberBuffer = ""
        }

        func emit() {
            flushNumber()
            switch command {
            case "M":
                var index = 0
                while index + 1 < arguments.count {
                    let point = CGPoint(x: arguments[index], y: arguments[index + 1])
                    // Repeated coordinate pairs after a moveto are implicit linetos.
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                    index += 2
                }
            case "L":
                var index = 0
                while index + 1 < arguments.count {
                    path.addLine(to: CGPoint(x: arguments[index], y: arguments[index + 1]))
                    index += 2
                }
            case "C":
                var index = 0
                while index + 5 < arguments.count {
                    path.addCurve(
                        to: CGPoint(x: arguments[index + 4], y: arguments[index + 5]),
                        control1: CGPoint(x: arguments[index], y: arguments[index + 1]),
                        control2: CGPoint(x: arguments[index + 2], y: arguments[index + 3])
                    )
                    index += 6
                }
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            arguments.removeAll(keepingCapacity: true)
        }

        for character in data {
            switch character {
            case "M", "L", "C", "Z":
                emit()
                command = character
            case ",", " ", "\n", "\t":
                flushNumber()
            case "-":
                // A minus starts a new number unless it is an exponent sign.
                if !numberBuffer.isEmpty, !numberBuffer.hasSuffix("e"), !numberBuffer.hasSuffix("E") {
                    flushNumber()
                }
                numberBuffer.append(character)
            default:
                numberBuffer.append(character)
            }
        }
        emit()

        return path
    }
}

/// Renders one pre-parsed design-space path scaled into the view's frame.
///
/// The path itself is parsed once and handed in; this only applies the viewport
/// transform, which is what any `Shape` does during layout.
struct MuscleMapPathShape: Shape {
    let designPath: Path

    func path(in rect: CGRect) -> Path {
        let viewport = MuscleMapGeometry.viewport
        let scale = rect.width / viewport.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(
                translationX: rect.minX - viewport.minX * scale,
                y: rect.minY - viewport.minY * scale
            ))
        return designPath.applying(transform)
    }
}
