import SwiftUI

struct InfoTipButton: View {
    let text: String
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(
                    Circle()
                        .fill(.quaternary.opacity(0.45))
                )
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
                .padding(12)
        }
    }
}
