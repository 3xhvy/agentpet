import SwiftUI

/// The pet itself: the current animation frame, sized for the floating window.
struct PetView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        Text(pet.currentFrame)
            .font(.system(size: 56))
            .frame(width: 120, height: 120)
            .contentShape(Rectangle())
    }
}
