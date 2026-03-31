import SwiftUI

struct TextCardOverlayView: View {
    @Bindable var vm: ProjectViewModel

    var body: some View {
        GeometryReader { geo in
            let currentTime = vm.playback.currentTime
            let activeCards = vm.textCardTrack.activeEntries(at: currentTime)

            ForEach(activeCards) { card in
                TextCardItemView(
                    card: card,
                    viewportSize: geo.size,
                    isSelected: vm.selectedTextCardID == card.id,
                    onSelect: { vm.selectedTextCardID = card.id },
                    onMove: { newX, newY in
                        vm.updateTextCardPosition(id: card.id, x: newX, y: newY)
                    },
                    onScale: { newScale in
                        vm.updateTextCardScale(id: card.id, scale: newScale)
                    },
                    onEdit: { newText in
                        vm.updateTextCardText(id: card.id, text: newText)
                    }
                )
            }
        }
    }
}

// MARK: - 單一字卡項目

private struct TextCardItemView: View {
    let card: TextCardEntry
    let viewportSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (CGFloat, CGFloat) -> Void
    let onScale: (CGFloat) -> Void
    let onEdit: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var dragOffset: CGSize = .zero
    @State private var baseScale: CGFloat = 1.0

    private var cardX: CGFloat { card.positionX * viewportSize.width }
    private var cardY: CGFloat { card.positionY * viewportSize.height }

    var body: some View {
        let style = card.style

        ZStack {
            // 描邊層
            if style.strokeWidth > 0 {
                let sw = style.strokeWidth * card.scale
                let offsets: [(CGFloat, CGFloat)] = [
                    (sw, 0), (-sw, 0), (0, sw), (0, -sw),
                    (sw * 0.7, sw * 0.7), (-sw * 0.7, sw * 0.7),
                    (sw * 0.7, -sw * 0.7), (-sw * 0.7, -sw * 0.7)
                ]
                ForEach(0..<offsets.count, id: \.self) { i in
                    Text(card.text)
                        .font(.custom(style.fontName, size: viewportSize.height * style.fontSizeRatio * card.scale))
                        .fontWeight(style.fontWeight)
                        .foregroundStyle(style.strokeColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .frame(maxWidth: viewportSize.width * card.widthRatio)
                        .offset(x: offsets[i].0, y: offsets[i].1)
                }
            }

            // 主文字
            Text(card.text)
                .font(.custom(style.fontName, size: viewportSize.height * style.fontSizeRatio * card.scale))
                .fontWeight(style.fontWeight)
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .frame(maxWidth: viewportSize.width * card.widthRatio)
        }
        .padding(style.padding * card.scale)
        .background(
            style.backgroundColor != .clear
                ? RoundedRectangle(cornerRadius: style.cornerRadius * card.scale)
                    .fill(style.backgroundColor)
                : nil
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: style.cornerRadius * card.scale)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-2)
                : nil
        )
        .shadow(color: style.shadowColor, radius: style.shadowRadius * card.scale)
        .position(
            x: cardX + dragOffset.width,
            y: cardY + dragOffset.height
        )
        .onTapGesture {
            onSelect()
        }
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    editText = card.text
                    isEditing = true
                }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    onSelect()
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let newX = (cardX + value.translation.width) / viewportSize.width
                    let newY = (cardY + value.translation.height) / viewportSize.height
                    let clampedX = max(0.05, min(0.95, newX))
                    let clampedY = max(0.05, min(0.95, newY))
                    onMove(clampedX, clampedY)
                    dragOffset = .zero
                }
        )
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    onSelect()
                    let newScale = baseScale * value.magnification
                    onScale(max(0.3, min(3.0, newScale)))
                }
                .onEnded { value in
                    baseScale = card.scale
                }
        )
        .onAppear {
            baseScale = card.scale
        }
        .popover(isPresented: $isEditing) {
            VStack(spacing: 8) {
                Text("編輯字卡")
                    .font(.headline)
                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .frame(width: 220, height: 80)
                    .border(Color(white: 0.3))
                HStack {
                    Spacer()
                    Button("確定") {
                        onEdit(editText)
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}
