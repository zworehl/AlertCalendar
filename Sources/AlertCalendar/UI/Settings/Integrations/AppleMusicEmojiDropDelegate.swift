import SwiftUI

struct AppleMusicEmojiDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var emojis: [String]
    @Binding var draggingIndex: Int?

    func validateDrop(info: DropInfo) -> Bool {
        draggingIndex != nil
    }

    func dropEntered(info: DropInfo) {
        guard let sourceIndex = draggingIndex,
              sourceIndex != targetIndex,
              emojis.indices.contains(sourceIndex),
              emojis.indices.contains(targetIndex) else { return }

        withAnimation(.easeInOut(duration: 0.14)) {
            emojis.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
            draggingIndex = targetIndex
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }
}
