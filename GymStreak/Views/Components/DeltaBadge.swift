import SwiftUI

// MARK: - Delta Badge

struct DeltaBadge: View {
    let value: Double
    let unit: String
    var isWeight: Bool = false

    private var intValue: Int? {
        isWeight ? nil : Int(value)
    }

    private var isPositive: Bool {
        value > 0
    }

    private var isNegative: Bool {
        value < 0
    }

    private var color: Color {
        if isPositive {
            return DesignSystem.Colors.success
        } else if isNegative {
            return DesignSystem.Colors.warning
        } else {
            return .secondary
        }
    }

    private var icon: String {
        if isPositive {
            return "arrow.up.right"
        } else if isNegative {
            return "arrow.down.right"
        } else {
            return "equal"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)

            if let intVal = intValue {
                Text(intVal > 0 ? "+\(intVal)" : "\(intVal)")
                    .font(.caption2.weight(.medium))
            } else {
                Text(value > 0 ? String(format: "+%.1f", value) : String(format: "%.1f", value))
                    .font(.caption2.weight(.medium))
            }

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
            }
        }
        .foregroundStyle(color)
    }
}

// Convenience initializer for Int values
extension DeltaBadge {
    init(value: Int, unit: String) {
        self.value = Double(value)
        self.unit = unit
        self.isWeight = false
    }
}
