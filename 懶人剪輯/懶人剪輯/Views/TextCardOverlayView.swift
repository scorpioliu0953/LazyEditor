import SwiftUI

struct TextCardOverlayView: View {
    @Bindable var vm: ProjectViewModel
    @State private var previousActiveCardIDs: Set<UUID> = []

    var body: some View {
        GeometryReader { geo in
            let currentTime = vm.playback.currentTime
            let activeCards = vm.textCardTrack.activeEntries(at: currentTime)

            ForEach(activeCards) { card in
                let fadeOpacity = card.fadeInOut
                    ? Self.computeFadeOpacity(card: card, currentTime: currentTime)
                    : 1.0

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
                    },
                    onResize: { newWidthRatio, newHeightRatio in
                        vm.updateTextCardSize(id: card.id, widthRatio: newWidthRatio, heightRatio: newHeightRatio)
                    },
                    onEditingStateChanged: { editing in
                        vm.isEditingTextCard = editing
                    }
                )
                .opacity(fadeOpacity)
            }
            .onChange(of: Set(activeCards.map(\.id))) { _, newIDs in
                // 偵測新出現的字卡，播放音效
                let newCards = newIDs.subtracting(previousActiveCardIDs)
                for id in newCards {
                    if let card = activeCards.first(where: { $0.id == id }),
                       card.soundEffect != .none {
                        SoundEffectGenerator.shared.play(card.soundEffect)
                    }
                }
                previousActiveCardIDs = newIDs
            }
        }
        .coordinateSpace(name: "textCardViewport")
    }

    /// 計算淡入淡出 opacity（前 0.3s 淡入、後 0.3s 淡出）
    static func computeFadeOpacity(card: TextCardEntry, currentTime: Double) -> Double {
        let fadeDuration = 0.3
        let elapsed = currentTime - card.startTime
        let remaining = card.endTime - currentTime

        var opacity = 1.0
        if elapsed < fadeDuration {
            opacity = min(opacity, elapsed / fadeDuration)
        }
        if remaining < fadeDuration {
            opacity = min(opacity, remaining / fadeDuration)
        }
        return max(0, min(1, opacity))
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
    let onResize: (CGFloat, CGFloat) -> Void
    let onEditingStateChanged: (Bool) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var dragOffset: CGSize = .zero
    @State private var baseScale: CGFloat = 1.0
    @State private var cardSize: CGSize = .zero

    private var cardX: CGFloat { card.positionX * viewportSize.width }
    private var cardY: CGFloat { card.positionY * viewportSize.height }

    private var cardWidth: CGFloat { viewportSize.width * card.widthRatio }
    private var cardHeight: CGFloat? {
        card.heightRatio > 0 ? viewportSize.height * card.heightRatio : nil
    }

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
                        .lineLimit(nil)
                        .frame(width: cardWidth, height: cardHeight)
                        .offset(x: offsets[i].0, y: offsets[i].1)
                }
            }

            // 主文字
            Text(card.text)
                .font(.custom(style.fontName, size: viewportSize.height * style.fontSizeRatio * card.scale))
                .fontWeight(style.fontWeight)
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .frame(width: cardWidth, height: cardHeight)
        }
        .drawingGroup()
        .padding(style.padding * card.scale)
        .background(
            style.backgroundColor != .clear
                ? RoundedRectangle(cornerRadius: card.effectiveCornerRadius * card.scale)
                    .fill(style.backgroundColor)
                : nil
        )
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in cardSize = newSize }
            }
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: card.effectiveCornerRadius * card.scale)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-2)
                : nil
        )
        .overlay(
            isSelected
                ? ResizeHandlesView(
                    cardSize: cardSize,
                    viewportSize: viewportSize,
                    currentWidthRatio: card.widthRatio,
                    currentHeightRatio: card.heightRatio,
                    onResize: onResize
                )
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
        .onChange(of: isEditing) { _, editing in
            onEditingStateChanged(editing)
        }
    }
}

// MARK: - 四角拖拉控制點

private struct ResizeHandlesView: View {
    let cardSize: CGSize
    let viewportSize: CGSize
    let currentWidthRatio: CGFloat
    let currentHeightRatio: CGFloat
    let onResize: (CGFloat, CGFloat) -> Void

    private let handleSize: CGFloat = 10

    var body: some View {
        ZStack {
            // 左上
            ResizeCornerHandle(
                handleSize: handleSize, xSign: -1, ySign: -1,
                cardSize: cardSize, viewportSize: viewportSize,
                currentWidthRatio: currentWidthRatio, currentHeightRatio: currentHeightRatio,
                onResize: onResize
            )
            .position(x: 0, y: 0)
            // 右上
            ResizeCornerHandle(
                handleSize: handleSize, xSign: 1, ySign: -1,
                cardSize: cardSize, viewportSize: viewportSize,
                currentWidthRatio: currentWidthRatio, currentHeightRatio: currentHeightRatio,
                onResize: onResize
            )
            .position(x: cardSize.width, y: 0)
            // 左下
            ResizeCornerHandle(
                handleSize: handleSize, xSign: -1, ySign: 1,
                cardSize: cardSize, viewportSize: viewportSize,
                currentWidthRatio: currentWidthRatio, currentHeightRatio: currentHeightRatio,
                onResize: onResize
            )
            .position(x: 0, y: cardSize.height)
            // 右下
            ResizeCornerHandle(
                handleSize: handleSize, xSign: 1, ySign: 1,
                cardSize: cardSize, viewportSize: viewportSize,
                currentWidthRatio: currentWidthRatio, currentHeightRatio: currentHeightRatio,
                onResize: onResize
            )
            .position(x: cardSize.width, y: cardSize.height)
        }
    }
}

private struct ResizeCornerHandle: View {
    let handleSize: CGFloat
    let xSign: CGFloat
    let ySign: CGFloat
    let cardSize: CGSize
    let viewportSize: CGSize
    let currentWidthRatio: CGFloat
    let currentHeightRatio: CGFloat
    let onResize: (CGFloat, CGFloat) -> Void

    @State private var baseWidthRatio: CGFloat?
    @State private var baseHeightRatio: CGFloat?
    @State private var dragStartLocation: CGPoint?

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.white, lineWidth: 1)
            )
            .contentShape(Rectangle().size(width: handleSize + 16, height: handleSize + 16))
            .gesture(
                DragGesture(coordinateSpace: .named("textCardViewport"))
                    .onChanged { value in
                        if dragStartLocation == nil {
                            dragStartLocation = value.startLocation
                            baseWidthRatio = currentWidthRatio
                            baseHeightRatio = currentHeightRatio > 0
                                ? currentHeightRatio
                                : cardSize.height / viewportSize.height
                        }
                        let dx = value.location.x - dragStartLocation!.x
                        let dy = value.location.y - dragStartLocation!.y
                        let dw = dx * xSign / viewportSize.width
                        let dh = dy * ySign / viewportSize.height
                        let newW = max(0.1, min(0.95, baseWidthRatio! + dw))
                        let newH = max(0.05, min(0.9, baseHeightRatio! + dh))
                        onResize(newW, newH)
                    }
                    .onEnded { _ in
                        dragStartLocation = nil
                        baseWidthRatio = nil
                        baseHeightRatio = nil
                    }
            )
    }
}
