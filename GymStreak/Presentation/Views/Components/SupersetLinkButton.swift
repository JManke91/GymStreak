import SwiftUI

/// A thin button that appears between adjacent exercise rows to link them as a superset.
/// Visual design: dashed line with a chain-link icon centered.
struct SupersetLinkButton: View {
    let onLink: () -> Void

    var body: some View {
        Button(action: onLink) {
            HStack(spacing: 8) {
                dashedLine
                Image(systemName: "link.badge.plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                dashedLine
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("superset.link_exercises".localized)
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
    List {
        Text("Exercise 1")
        SupersetLinkButton { }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        Text("Exercise 2")
        SupersetLinkButton { }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        Text("Exercise 3")
    }
    .listStyle(.insetGrouped)
}
