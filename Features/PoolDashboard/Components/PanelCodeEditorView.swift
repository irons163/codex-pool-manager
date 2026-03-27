import SwiftUI

struct PanelCodeEditorView: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    let font: Font

    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .frame(minHeight: minimumHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelMutedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                    )
            )
    }
}
