//
//  SupersetGroupContainer.swift
//  GymStreak
//
//  Renders one superset of the routine detail as a single row of the outer
//  LazyVStack, so its connecting line can cross the gaps between the member
//  cards instead of being clipped inside each card. The line also carries the
//  unlink control that breaks the group apart at a seam.
//

import SwiftUI

/// What one member card publishes to its enclosing `SupersetGroupContainer`:
/// the connector dot in its header, and — for every member but the last — the
/// seam below it, where the unlink control sits.
///
/// Collected ONLY inside the container's own subtree — that subtree is small
/// and always fully materialised. Resolving anchors across the outer lazy
/// container does not work: offscreen rows are never built, their entries
/// silently fall back to the default, and the line snaps or drops mid-scroll.
struct SupersetMemberAnchors {
    var dot: Anchor<CGPoint>?
    var seam: Anchor<CGPoint>?
}

struct SupersetMemberAnchorKey: PreferenceKey {
    static var defaultValue: [UUID: SupersetMemberAnchors] { [:] }

    static func reduce(value: inout [UUID: SupersetMemberAnchors], nextValue: () -> [UUID: SupersetMemberAnchors]) {
        value.merge(nextValue()) { current, next in
            SupersetMemberAnchors(dot: next.dot ?? current.dot, seam: next.seam ?? current.seam)
        }
    }
}

extension View {
    /// Publishes this view's centre as the card's connector dot position.
    /// Inert (`isActive == false`) for cards that are not superset members.
    func supersetConnectorAnchor(id: UUID, isActive: Bool) -> some View {
        anchorPreference(key: SupersetMemberAnchorKey.self, value: .center) { anchor in
            isActive ? [id: SupersetMemberAnchors(dot: anchor)] : [:]
        }
    }

    /// Publishes this view's centre as the seam below member `id`.
    func supersetSeamAnchor(below id: UUID) -> some View {
        anchorPreference(key: SupersetMemberAnchorKey.self, value: .center) { anchor in
            [id: SupersetMemberAnchors(seam: anchor)]
        }
    }
}

/// The empty layout space between two member cards. It reserves room for the
/// unlink control, which the container draws on top of the line — the control
/// itself cannot live here, because the line is an overlay and would be
/// stroked straight across it.
struct SupersetSeamSpacer: View {
    let memberAboveId: UUID

    static let height: CGFloat = 28

    var body: some View {
        Color.clear
            .frame(height: Self.height)
            .supersetSeamAnchor(below: memberAboveId)
    }
}

/// Wraps the member cards of one superset. The connector is a sibling of the
/// cards (an overlay of this container), never a child of one of them, which is
/// what lets a single unbroken line span the whole group. Endpoints come from
/// the cards' own anchors, so they ride the expand/collapse animation.
struct SupersetGroupContainer<Content: View>: View {
    /// One member in display order — the line runs from the first to the last,
    /// and each adjacent pair gets an unlink control between them. The name is
    /// what the control's VoiceOver label names, since its meaning is purely
    /// positional on screen.
    struct Member: Identifiable {
        let id: UUID
        let name: String
    }

    let members: [Member]
    let color: Color
    /// Breaks the group at the seam below the passed member.
    let onUnlink: (UUID) -> Void
    let content: Content

    init(
        members: [Member],
        color: Color,
        onUnlink: @escaping (UUID) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.members = members
        self.color = color
        self.onUnlink = onUnlink
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .overlayPreferenceValue(SupersetMemberAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let first = members.first.flatMap({ anchors[$0.id]?.dot }),
                   let last = members.last.flatMap({ anchors[$0.id]?.dot }) {
                    let start = proxy[first]

                    SupersetConnectorLine(start: start, end: proxy[last], color: color)
                        // Purely decorative — taps belong to the cards
                        // underneath and to the unlink controls above it, and
                        // each card's badge already announces its position.
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    ForEach(seams) { seam in
                        if let seamAnchor = anchors[seam.id]?.seam {
                            SupersetUnlinkButton(color: color) {
                                onUnlink(seam.id)
                            }
                            .accessibilityLabel(
                                String(format: "superset.unlink_between".localized, seam.aboveName, seam.belowName)
                            )
                            // The line's x, the seam's y: the control rides the
                            // connector down the lane between the two cards.
                            .position(x: start.x, y: proxy[seamAnchor].y)
                        }
                    }
                }
            }
        }
    }

    /// One entry per adjacent pair, identified by the member above it — the
    /// same id `SupersetSeamSpacer` publishes its anchor under.
    private struct Seam: Identifiable {
        let id: UUID
        let aboveName: String
        let belowName: String
    }

    private var seams: [Seam] {
        zip(members, members.dropFirst()).map { above, below in
            Seam(id: above.id, aboveName: above.name, belowName: below.name)
        }
    }
}

/// One unbroken stroke between the two anchor dots.
private struct SupersetConnectorLine: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    private let lineWidth: CGFloat = 3
    private let dotSize: CGFloat = 8

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .position(start)

            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .position(end)
        }
    }
}

/// Breaks the superset at one seam. Drawn compact so it reads as a node on the
/// connector, but its tap shape is a full 44pt circle — the glyph is sized
/// independently of the hit region. The opaque fill is what makes the line
/// appear to pass behind it.
///
/// `scissors` rather than a struck-through chain: iOS 26.1 ships no
/// `link.slash`, `link.badge.minus` or `link.badge.xmark` (verified against the
/// runtime's symbol catalogue after the first attempt rendered an empty node).
/// `link.badge.plus` on the link side is the only half of the pair Apple has.
private struct SupersetUnlinkButton: View {
    let color: Color
    let action: () -> Void

    private let diameter: CGFloat = 26

    var body: some View {
        Button(action: action) {
            Image(systemName: "scissors")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(DesignSystem.Colors.background))
                .overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1.5))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
