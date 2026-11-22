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
                    HStack(spacing: 10) {
                        ForEach(details.indices, id: \.self) { i in
                            StatPill(title: details[i].0, value: details[i].1, tint: tint)
                        }
                    }
                }
                VStack(spacing: 10) { actions() }
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            .padding(24)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var icon: String {
        switch mood {
        case .win: "trophy.fill"
        case .loss: "xmark.octagon.fill"
        case .neutral: "flag.checkered"
        }
    }
}
