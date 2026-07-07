//
//  RedesignControls.swift
//  GymStreak
//
//  Shared interactive controls of the Routinen & Übungen redesign:
//  search bar, filter pill and dashed create button.
//

import SwiftUI

/// Rounded dark search bar with clear button.
struct RedesignSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("action.cancel".localized)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Horizontal-scroll filter pill. Active pills fill with `color` (default tint).
struct FilterPillButton: View {
    let label: String
    let isActive: Bool
    var color: Color = DesignSystem.Colors.tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? color : Color.white.opacity(0.05))
                .overlay(
                    Capsule().stroke(isActive ? Color.clear : Color.white.opacity(0.07), lineWidth: 1)
                )
                .clipShape(Capsule())
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isActive)
    }
}

/// Dashed rounded button used for "create new" tiles.
struct DashedCreateButton: View {
    let title: String
    var tinted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13.5, weight: tinted ? .bold : .semibold))
            }
            .foregroundStyle(tinted ? DesignSystem.Colors.tint : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(tinted ? DesignSystem.Colors.tint.opacity(0.5) : Color.white.opacity(0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Left-aligned wrapping layout for pill rows (muscle-group selection).
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var text = ""
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    RedesignSearchBar(text: $text, placeholder: "Übungen suchen")
                    HStack {
                        FilterPillButton(label: "Alle", isActive: true) {}
                        FilterPillButton(label: "Brust", isActive: false) {}
                    }
                    DashedCreateButton(title: "Neue Routine") {}
                    DashedCreateButton(title: "Neue Übung erstellen", tinted: true) {}
                }
                .padding()
            }
        }
    }
    return PreviewWrapper()
}
