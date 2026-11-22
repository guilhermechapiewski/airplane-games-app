import AVFoundation

/// Short sound effects synthesized at runtime — the app ships no audio assets.
enum SoundEffect: CaseIterable {
    case tap, move, merge, place, clear, invalid, win, lose, flip, pop, eat, select

    /// Notes played in sequence: (frequency Hz, duration s, waveform, gain).
    fileprivate var notes: [Note] {
        switch self {
        case .tap: [Note(1200, 0.03, .sine, 0.25)]
        case .select: [Note(880, 0.04, .sine, 0.22)]
        case .move: [Note(420, 0.05, .triangle, 0.3)]
        case .merge: [Note(523, 0.05, .triangle, 0.3), Note(784, 0.07, .triangle, 0.3)]
        case .place: [Note(300, 0.06, .triangle, 0.38)]
        case .pop: [Note(660, 0.04, .sine, 0.3), Note(990, 0.05, .sine, 0.25)]
        case .flip: [Note(700, 0.025, .triangle, 0.2), Note(900, 0.025, .triangle, 0.2)]
        case .eat: [Note(600, 0.04, .square, 0.12), Note(900, 0.05, .square, 0.12)]
        case .clear: [Note(523, 0.06, .triangle, 0.3), Note(659, 0.06, .triangle, 0.3),
                      Note(784, 0.06, .triangle, 0.3), Note(1047, 0.12, .triangle, 0.3)]
        case .invalid: [Note(180, 0.09, .square, 0.12), Note(150, 0.12, .square, 0.12)]
        case .win: [Note(523, 0.1, .triangle, 0.32), Note(659, 0.1, .triangle, 0.32),
                    Note(784, 0.1, .triangle, 0.32), Note(1047, 0.28, .triangle, 0.32)]
        case .lose: [Note(392, 0.14, .triangle, 0.3), Note(330, 0.14, .triangle, 0.3),
                     Note(262, 0.32, .triangle, 0.3)]
        }
    }
}

fileprivate enum Waveform { case sine, triangle, square }

fileprivate struct Note {
    let frequency: Double
    let duration: Double
    let waveform: Waveform
    let gain: Float
    init(_ f: Double, _ d: Double, _ w: Waveform, _ g: Float) {
        frequency = f; duration = d; waveform = w; gain = g
    }
}

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var isConfigured = false

    private init() {}

    func play(_ effect: SoundEffect) {
        guard AppSettings.shared.soundEnabled else { return }
        configureIfNeeded()
        guard isConfigured, let buffer = buffers[effect] else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        // `.interrupts` replaces whatever this node was playing without a synchronous `stop()`,
        // which blocks the main thread on the audio render thread.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Sets up the audio engine ahead of the first sound so the first tap doesn't pay for it.
    func warmUp() {
        guard AppSettings.shared.soundEnabled else { return }
        configureIfNeeded()
        if isConfigured, !engine.isRunning { try? engine.start() }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        // `.ambient` mixes with other audio and respects the silent switch.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        // A ~5 ms hardware buffer instead of the default ~20 ms keeps clicks in sync with touches.
        try? session.setPreferredIOBufferDuration(0.005)
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.8
        for effect in SoundEffect.allCases {
            buffers[effect] = Self.render(effect.notes, format: format)
        }
        do {
            try engine.start()
            isConfigured = true
        } catch {
            isConfigured = false
        }
    }

    private static func render(_ notes: [Note], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.duration * rate) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        var offset = 0
        for note in notes {
            let count = Int(note.duration * rate)
            let attack = max(1, Int(0.004 * rate))
            for i in 0..<count {
                let t = Double(i) / rate
                let phase = (t * note.frequency).truncatingRemainder(dividingBy: 1)
                let raw: Double
                switch note.waveform {
                case .sine: raw = sin(2 * .pi * phase)
                case .triangle: raw = 4 * abs(phase - 0.5) - 1
                case .square: raw = phase < 0.5 ? 1 : -1
                }
                // Quick attack, exponential-ish decay to avoid clicks.
                let env = i < attack ? Double(i) / Double(attack) : pow(1 - Double(i - attack) / Double(count - attack), 2)
                data[offset + i] = Float(raw * env) * note.gain
            }
            offset += count
        }
        return buffer
    }
}

/// Convenience used by view models: play a sound and a matching haptic together.
@MainActor
enum Feedback {
    static func play(_ effect: SoundEffect) {
        SoundEngine.shared.play(effect)
        switch effect {
        case .tap, .select, .flip: Haptics.select()
        case .move, .eat: Haptics.tap()
        case .merge, .pop, .place: Haptics.impact()
        case .clear: Haptics.thud()
        case .invalid: Haptics.warning()
        case .win: Haptics.success()
        case .lose: Haptics.error()
        }
    }
}
