import SwiftUI

/// The affordance between two adjacent, unlinked exercise cards that joins them
/// into a superset. Counterpart of the unlink control on the connecting line
/// (`SupersetGroupContainer`): same chain-link symbol family, same group-colour
/// language, and the same 44pt minimum hit region — here the whole row is
/// tappable while the pill itself stays visually compact.
struct SupersetLinkButton: View {
    let onLink: () -> Void

    private let minimumTapHeight: CGFloat = 44

    var body: some View {
        Button(action: onLink) {
            HStack(spacing: 8) {
                dashedLine
                label
                dashedLine
            }
            .frame(maxWidth: .infinity, minHeight: minimumTapHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("superset.link_exercises".localized)
    }

    /// Labelled, so the control explains itself instead of asking the user to
    /// decode a bare icon.
    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 11, weight: .bold))
            Text("superset.link_action".localized)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color.white.opacity(0.55))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var dashedLine: some View {
        DashedLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        Text("Exercise 1")
        SupersetLinkButton { }
        Text("Exercise 2")
        SupersetLinkButton { }
        Text("Exercise 3")
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignSystem.Colors.background)
}
