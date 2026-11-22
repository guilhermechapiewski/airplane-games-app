import SwiftUI

/// Rules content shown in a game's "How to play" sheet.
struct HowToPlay {
    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let points: [String]
    }

    let summary: String
    let sections: [Section]
}

struct HowToPlaySheet: View {
    let game: GameID
    let rules: HowToPlay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        GameBadge(game: game, size: 56)
                        Text(rules.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rules.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.headline)
                                .foregroundStyle(game.accent)
                            ForEach(section.points, id: \.self) { point in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle().fill(game.accent.opacity(0.6)).frame(width: 6, height: 6)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                    Text(point).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The rounded gradient icon representing a game.
struct GameBadge: View {
    let game: GameID
    var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: game.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: game.symbol)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .accessibilityHidden(true)
    }
}
