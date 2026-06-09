import SwiftUI
import AgentPetCore

/// Body motion for a given mood at time `t`, shared by all pet renderers.
struct PetMotion {
    var offsetY: CGFloat
    var rotation: Double
    var scaleX: CGFloat
    var scaleY: CGFloat

    /// Identity: the app no longer adds body motion (no bob/sway/rotation/scale).
    /// The pet stays perfectly still and only animates through its sprite frames.
    static func resolve(_ mood: PetMood, _ t: Double) -> PetMotion {
        PetMotion(offsetY: 0, rotation: 0, scaleX: 1, scaleY: 1)
    }
}

/// Mood overlays shared by all pet renderers: sparkles while celebrating and a
/// "?" bubble while waiting.
struct MoodAccessories: View {
    let mood: PetMood
    let t: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            if mood == .celebrate {
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) / 4 * .pi * 2
                    let twinkle = 0.35 + 0.65 * abs(sin(t * 4 + Double(i)))
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .opacity(twinkle)
                        .offset(x: cos(angle) * size * 0.34, y: -abs(sin(angle)) * size * 0.34 - size * 0.06)
                }
            }
        }
    }
}
