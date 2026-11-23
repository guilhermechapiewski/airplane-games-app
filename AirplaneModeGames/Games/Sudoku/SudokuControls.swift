import SwiftUI
import GameLogic

/// Undo / Erase / Notes / Hint.
struct SudokuToolbar: View {
    let model: SudokuModel

    var body: some View {
        HStack(spacing: 0) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .frame(maxWidth: .infinity)
            ToolButton(title: "Erase", systemImage: "eraser") { model.erase() }
                .disabled(!model.canErase)
                .frame(maxWidth: .infinity)
            ToolButton(title: "Notes", systemImage: model.notesMode ? "pencil.circle.fill" : "pencil",
                       isActive: model.notesMode, badge: model.notesMode ? "On" : nil,
                       tint: SudokuPalette.player) { model.toggleNotesMode() }
                .disabled(!model.canInteract)
                .accessibilityValue(model.notesMode ? "On" : "Off")
                .accessibilityIdentifier("sudoku.notes")
                .frame(maxWidth: .infinity)
            ToolButton(title: "Hint", systemImage: "lightbulb",
                       badge: (model.game?.hintsUsed ?? 0) > 0 ? "\(model.game?.hintsUsed ?? 0)" : nil,
                       tint: Color(hex: 0xF0A500)) { model.hint() }
                .disabled(!model.canInteract)
                .accessibilityHint("Explains the next step, then can fill it in.")
                .frame(maxWidth: .infinity)
        }
    }
}

/// Digits 1–9 with how many of each are still missing.
struct SudokuNumberPad: View {
    let model: SudokuModel
    /// 9 = single row; 3 = a 3×3 block (used beside the board).
    let columns: Int
    let keyHeight: CGFloat

    var body: some View {
        let spacing: CGFloat = columns == 9 ? 6 : 10
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0..<(9 / columns), id: \.self) { r in
                GridRow {
                    ForEach(1...columns, id: \.self) { c in
                        key(r * columns + c)
                    }
                }
            }
        }
    }

    private func key(_ digit: Int) -> some View {
        let remaining = model.remaining(digit)
        let done = remaining == 0
        let notes = model.notesMode
        return Button {
            model.input(digit)
        } label: {
            VStack(spacing: keyHeight > 64 ? 4 : 1) {
                Text("\(digit)")
                    .font(.system(size: keyHeight * (notes ? 0.42 : 0.5), weight: notes ? .medium : .semibold,
                                  design: .rounded))
                    .foregroundStyle(notes ? SudokuPalette.note : SudokuPalette.player)
                    .frame(height: keyHeight * 0.56)
                Group {
                    if done {
                        Image(systemName: "checkmark")
                    } else {
                        Text("\(remaining)")
                    }
                }
                .font(.system(size: max(10, keyHeight * 0.19), weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: min(14, keyHeight * 0.24), style: .continuous))
            .overlay {
                if notes {
                    RoundedRectangle(cornerRadius: min(14, keyHeight * 0.24), style: .continuous)
                        .strokeBorder(SudokuPalette.player.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
            }
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            .opacity(done ? 0.35 : 1)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(done || !model.canInteract)
        .accessibilityLabel(notes ? "Note \(digit)" : "\(digit)")
        .accessibilityValue(done ? "All placed" : "\(remaining) left")
        .accessibilityIdentifier("sudoku.pad.\(digit)")
    }
}
