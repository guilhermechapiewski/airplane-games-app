import SwiftUI
import GameLogic

struct WordSearchView: View {
    @State private var model = WordSearchModel()
    @State private var showThemes = false
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let accent = GameID.wordSearch.accent
    /// Readable accent for text on light backgrounds (the yellow game color is too pale).
    static let ink = Color(light: Color(hex: 0xB27200), dark: Color(hex: 0xFFC94A))
    /// Filled button color with enough contrast for white text.
    static let buttonColor = Color(hex: 0xC98200)

    var body: some View {
        VStack(spacing: 14) {
            header
            if let state = model.state {
                WordSearchGrid(model: model, state: state, reduceMotion: reduceMotion)
                    .frame(maxWidth: sizeClass == .regular ? 780 : 620)
                    .opacity(model.isGenerating ? 0.35 : 1)
                    .overlay { if model.isGenerating { ProgressView() } }
                WordListView(model: model, state: state, reduceMotion: reduceMotion)
                    .frame(maxWidth: sizeClass == .regular ? 780 : 620)
                Spacer(minLength: 0)
                controls
            } else {
                Spacer()
                ProgressView("Hiding words…")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { winOverlay }
        .sheet(isPresented: $showThemes) {
            WordSearchThemeSheet(current: model.categoryID) { id in
                showThemes = false
                model.chooseCategory(id)
            }
            .presentationDetents([.medium, .large])
        }
        .gameChrome(.wordSearch, rules: Self.rules,
                    stats: WordSearchModel.difficulties.map { StatsVariant(key: $0.rawValue, title: $0.title, showsTime: true) },
                    newGame: WordSearchModel.difficulties.map { d in
                        NewGameOption(title: d.title, systemImage: Self.symbol(for: d)) { model.newGame(difficulty: d) }
                    } + [NewGameOption(title: "Choose Theme…", systemImage: "square.grid.2x2") { showThemes = true }],
                    onActiveChange: model.setActive,
                    freshStart: { model.newGame() })
    }

    static func symbol(for d: Difficulty) -> String {
        switch d {
        case .easy: "gauge.with.dots.needle.0percent"
        case .medium: "gauge.with.dots.needle.50percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { showThemes = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.difficulty.title) · \(model.categoryID == nil ? "Random" : "Theme")")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 6) {
                        Image(systemName: WordCategory.all.first { $0.title == model.state?.puzzle.title }?.symbol ?? "square.grid.2x2")
                        Text(model.state?.puzzle.title ?? " ")
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Self.ink)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Theme: \(model.state?.puzzle.title ?? ""), \(model.difficulty.title)")
            .accessibilityHint("Choose a theme")
            Spacer(minLength: 4)
            StatPill(title: "Found", value: "\(model.foundCount)/\(model.totalCount)", tint: Self.ink)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                StatPill(title: "Time", value: model.clock.elapsed().clockString)
            }
        }
        .frame(maxWidth: sizeClass == .regular ? 780 : 620)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ToolButton(title: "Hint", systemImage: "lightbulb", tint: Self.ink) { model.useHint() }
                .disabled(model.state?.isComplete != false || model.isGenerating)
            ToolButton(title: "New", systemImage: "arrow.clockwise", tint: Self.ink) { model.newGame() }
        }
    }

    @ViewBuilder private var winOverlay: some View {
        if model.showWin, let state = model.state {
            let time = model.clock.elapsed()
            ResultOverlay(mood: .win, title: "All found!",
                          subtitle: model.isNewBest ? "New best time for \(model.difficulty.title)!"
                                                    : "You found all \(state.puzzle.placements.count) \(state.puzzle.title.lowercased()) words.",
                          details: [("Time", time.clockString), ("Best", (model.bestTime ?? time).clockString),
                                    ("Hints", "\(state.hintsUsed)")],
                          tint: Self.ink) {
                Button("Play Again") { model.newGame() }
                    .buttonStyle(PrimaryButtonStyle(color: Self.buttonColor))
                    .accessibilityIdentifier("playAgain")
                Button("Choose Theme") { showThemes = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        }
    }

    static let rules = HowToPlay(
        summary: "Find every themed word hidden in the grid.",
        sections: [
            .init(title: "Selecting", symbol: "hand.draw", points: [
                "Drag from the first letter of a word to its last letter.",
                "Or tap the first letter, then tap the last letter.",
                "Words read in a straight line. Found words stay highlighted.",
            ]),
            .init(title: "Difficulty", symbol: "dial.medium", points: [
                "Easy: 8×8, words run left-to-right or top-to-bottom.",
                "Medium: 10×10, diagonals too.",
                "Hard: 12×12, any of 8 directions — including backwards.",
            ]),
            .init(title: "Stuck?", symbol: "lightbulb", points: [
                "Tap Hint to flash the first letter of a word you haven't found.",
                "Your best time for each difficulty is saved.",
            ]),
        ]
    )
}

// MARK: - Highlight colors

enum WordSearchPalette {
    static let colors: [Color] = [
        Color(hex: 0xFFB3A7), Color(hex: 0xA8D8FF), Color(hex: 0xB9F0C9), Color(hex: 0xFFE08A),
        Color(hex: 0xD6C1FF), Color(hex: 0xFFC2E0), Color(hex: 0x9EE8E0), Color(hex: 0xFFD0A6),
        Color(hex: 0xC8E59A), Color(hex: 0xB7C7FF),
    ]

    static func color(_ order: Int) -> Color { colors[order % colors.count] }
}

// MARK: - Grid

private struct WordSearchGrid: View {
    let model: WordSearchModel
    let state: WordSearch.State
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStart: GridPoint?
    @State private var dragEnd: GridPoint?
    @GestureState private var dragActive = false

    var body: some View {
        let puzzle = state.puzzle
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inset = side * 0.03
            let cell = (side - inset * 2) / CGFloat(puzzle.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 12, y: 4)

                // Found words (behind the letters).
                ForEach(state.found, id: \.self) { index in
                    let p = puzzle.placements[index]
                    SelectionCapsule(from: p.start, to: p.end, cell: cell, inset: inset,
                                     color: WordSearchPalette.color(model.foundOrder(index) ?? 0)
                                        .opacity(colorScheme == .dark ? 0.55 : 0.85))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                }

                // Live selection.
                if let start = dragStart ?? model.pendingStart {
                    SelectionCapsule(from: start, to: dragEnd ?? start, cell: cell, inset: inset,
                                     color: Color.secondary.opacity(0.28), outline: GameID.wordSearch.accent)
                }

                // Hint flash.
                if let hint = model.hint {
                    let start = puzzle.placements[hint.index].start
                    HintPulse(token: hint.token, reduceMotion: reduceMotion)
                        .frame(width: cell * 0.92, height: cell * 0.92)
                        .position(x: inset + (CGFloat(start.col) + 0.5) * cell, y: inset + (CGFloat(start.row) + 0.5) * cell)
                        .allowsHitTesting(false)
                }

                letters(puzzle: puzzle, cell: cell, inset: inset)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(drag(cell: cell, inset: inset, size: puzzle.size))
            .onGestureCancelled(dragActive) { dragStart = nil; dragEnd = nil }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: state.found)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter grid")
        .accessibilityIdentifier("wordSearchGrid")
    }

    private func letters(puzzle: WordSearch.Puzzle, cell: CGFloat, inset: CGFloat) -> some View {
        let foundCells = Set(state.found.flatMap { puzzle.placements[$0].cells })
        return VStack(spacing: 0) {
            ForEach(0..<puzzle.size, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<puzzle.size, id: \.self) { c in
                        let p = GridPoint(row: r, col: c)
                        let letter = puzzle.letter(at: p).uppercased()
                        Text(letter)
                            .font(.system(size: cell * 0.5, weight: foundCells.contains(p) ? .heavy : .semibold, design: .rounded))
                            .foregroundStyle(foundCells.contains(p) ? Color.primary : Color.primary.opacity(0.82))
                            .minimumScaleFactor(0.5)
                            .frame(width: cell, height: cell)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(letter)
                            .accessibilityValue("Row \(r + 1), column \(c + 1)\(foundCells.contains(p) ? ", in a found word" : "")\(model.pendingStart == p ? ", selected start" : "")")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.tapCell(p) }
                            .accessibilityIdentifier("cell.\(r).\(c)")
                    }
                }
            }
        }
        .padding(inset)
    }

    private func gridPoint(_ location: CGPoint, cell: CGFloat, inset: CGFloat) -> (row: Double, col: Double) {
        (Double((location.y - inset) / cell) - 0.5, Double((location.x - inset) / cell) - 0.5)
    }

    private func drag(cell: CGFloat, inset: CGFloat, size: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .tracking($dragActive)
            .onChanged { value in
                let s = gridPoint(value.startLocation, cell: cell, inset: inset)
                let start = GridPoint(row: Int(s.row.rounded()), col: Int(s.col.rounded()))
                guard start.isInside(rows: size, cols: size) else { return }
                let moved = hypot(value.translation.width, value.translation.height) > cell * 0.35
                guard moved else { return }
                if dragStart == nil {
                    dragStart = start
                    model.pendingStart = nil
                    Haptics.select()
                }
                let end = WordSearch.snappedEnd(from: start, toward: gridPoint(value.location, cell: cell, inset: inset), size: size)
                if end != dragEnd {
                    if dragEnd != nil { Haptics.select() }
                    dragEnd = end
                }
            }
            .onEnded { value in
                if let start = dragStart {
                    model.select(from: start, to: dragEnd ?? start)
                } else {
                    // A tap: two-tap selection.
                    let s = gridPoint(value.startLocation, cell: cell, inset: inset)
                    let p = GridPoint(row: Int(s.row.rounded()), col: Int(s.col.rounded()))
                    if p.isInside(rows: size, cols: size) { model.tapCell(p) }
                }
                dragStart = nil
                dragEnd = nil
            }
    }
}

/// A rounded highlight spanning from one cell center to another.
private struct SelectionCapsule: View {
    let from: GridPoint
    let to: GridPoint
    let cell: CGFloat
    let inset: CGFloat
    let color: Color
    var outline: Color?

    var body: some View {
        let a = CGPoint(x: inset + (CGFloat(from.col) + 0.5) * cell, y: inset + (CGFloat(from.row) + 0.5) * cell)
        let b = CGPoint(x: inset + (CGFloat(to.col) + 0.5) * cell, y: inset + (CGFloat(to.row) + 0.5) * cell)
        let length = hypot(b.x - a.x, b.y - a.y)
        let thickness = cell * 0.8
        Capsule()
            .fill(color)
            .overlay { if let outline { Capsule().strokeBorder(outline, lineWidth: 2) } }
            .frame(width: length + thickness, height: thickness)
            .rotationEffect(.radians(atan2(b.y - a.y, b.x - a.x)))
            .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HintPulse: View {
    let token: Int
    let reduceMotion: Bool

    var body: some View {
        Circle()
            .strokeBorder(WordSearchView.ink, lineWidth: 3)
            .background(Circle().fill(GameID.wordSearch.accent.opacity(0.3)))
            .keyframeAnimator(initialValue: CGFloat(1), trigger: token) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                let peak = CGFloat(reduceMotion ? 1 : 1.25)
                KeyframeTrack {
                    SpringKeyframe(peak, duration: 0.25)
                    SpringKeyframe(CGFloat(1), duration: 0.3)
                    SpringKeyframe(peak, duration: 0.25)
                    SpringKeyframe(CGFloat(1), duration: 0.3)
                    SpringKeyframe(peak, duration: 0.25)
                    SpringKeyframe(CGFloat(1), duration: 0.3)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Word list

private struct WordListView: View {
    let model: WordSearchModel
    let state: WordSearch.State
    let reduceMotion: Bool

    var body: some View {
        let placements = state.puzzle.placements
        let order = placements.indices.sorted { placements[$0].word < placements[$1].word }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(order, id: \.self) { index in
                let found = model.foundOrder(index)
                Text(placements[index].word.uppercased())
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .strikethrough(found != nil, color: .primary.opacity(0.6))
                    .foregroundStyle(found != nil ? Color.primary.opacity(0.55) : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(found.map { WordSearchPalette.color($0).opacity(0.55) } ?? Theme.surface,
                                in: Capsule())
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: found != nil) { view, s in
                        view.scaleEffect(s)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(CGFloat(reduceMotion || found == nil ? 1 : 1.15), duration: 0.12)
                            SpringKeyframe(CGFloat(1), duration: 0.25)
                        }
                    }
                    .accessibilityLabel(placements[index].word)
                    .accessibilityValue(found != nil ? "found" : "not found")
                    .accessibilityIdentifier("word.\(placements[index].word)")
            }
        }
        .animation(.easeOut(duration: 0.25), value: state.found)
    }
}

// MARK: - Theme picker

private struct WordSearchThemeSheet: View {
    let current: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    cell(id: nil, title: "Random", symbol: "shuffle")
                    ForEach(WordCategory.all) { c in cell(id: c.id, title: c.title, symbol: c.symbol) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func cell(id: String?, title: String, symbol: String) -> some View {
        let selected = id == current
        return Button { onPick(id) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: 26)
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.footnote.weight(.bold)) }
            }
            .foregroundStyle(selected ? Color.black.opacity(0.8) : WordSearchView.ink)
            .padding(14)
            .background(selected ? GameID.wordSearch.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
