import SwiftUI

/// End-of-game card shown over the board (win, loss, or neutral).
struct ResultOverlay<Actions: View>: View {
    enum Mood { case win, loss, neutral }

    let mood: Mood
    let title: String
    var subtitle: String?
    var details: [(String, String)] = []
    var tint: Color = .accentColor
    @ViewBuilder var actions: () -> Actions

    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(appeared ? 0.35 : 0))
                .ignoresSafeArea()
            if mood == .win {
                ConfettiView().ignoresSafeArea()
            }
            // A card taller than the screen (long text, large type) scrolls instead of running off.
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicatorsFlash(onAppear: true)
            }
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: appeared)
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !details.isEmpty {
                // One row when it fits (with tighter boxes on narrow phones); otherwise two per
                // row, so no box runs off the card.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { pills(details.indices, compact: false) }
                    HStack(spacing: 8) { pills(details.indices, compact: true) }
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(Array(stride(from: 0, to: details.count, by: 2)), id: \.self) { row in
                            GridRow {
                                if row + 1 < details.count {
                                    pills(row..<row + 2, compact: false)
                                } else {
                                    // A lone last box sits in the middle.
                                    pills(row..<row + 1, compact: false).gridCellColumns(2)
                                }
                            }
                        }
                    }
                }
            }
            VStack(spacing: 10) { actions() }
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func pills(_ range: Range<Int>, compact: Bool) -> some View {
        ForEach(range, id: \.self) { i in
            StatPill(title: details[i].0, value: details[i].1, tint: tint, compact: compact)
        }
    }

    private var icon: String {
        switch mood {
        case .win: "trophy.fill"
        case .loss: "xmark.octagon.fill"
        case .neutral: "flag.checkered"
        }
    }
}
