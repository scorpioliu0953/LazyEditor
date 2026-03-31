import Foundation

@Observable
final class TimelineState {
    var segments: [ClipSegment] = []
    var selectedSegmentIDs: Set<UUID> = []
    var playheadPosition: Double = 0
    var zoomScale: CGFloat = Constants.defaultPixelsPerSecond

    /// 上次點擊選取的片段索引（用於 Shift 範圍選取）
    var lastSelectedIndex: Int?

    // MARK: - 復原系統
    private var undoStack: [[ClipSegment]] = []
    private let maxUndoLevels = 50

    /// 時間軸上所有片段的總時長
    var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// 保存當前狀態到復原堆疊
    func pushUndo() {
        undoStack.append(segments)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
    }

    /// 復原上一步操作
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        segments = previous
        selectedSegmentIDs.removeAll()
        lastSelectedIndex = nil
    }

    // MARK: - 選取

    func isSelected(_ id: UUID) -> Bool {
        selectedSegmentIDs.contains(id)
    }

    /// 一般選取（取代目前選取）
    func selectOnly(_ id: UUID) {
        selectedSegmentIDs = [id]
        lastSelectedIndex = segments.firstIndex(where: { $0.id == id })
    }

    /// Command 點擊：切換單一片段的選取狀態
    func toggleSelection(_ id: UUID) {
        if selectedSegmentIDs.contains(id) {
            selectedSegmentIDs.remove(id)
        } else {
            selectedSegmentIDs.insert(id)
        }
        lastSelectedIndex = segments.firstIndex(where: { $0.id == id })
    }

    /// Shift 點擊：從上次選取到目前點擊的片段，全部選取
    func extendSelection(to id: UUID) {
        guard let targetIndex = segments.firstIndex(where: { $0.id == id }) else { return }
        let anchorIndex = lastSelectedIndex ?? 0

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        for i in range {
            selectedSegmentIDs.insert(segments[i].id)
        }
        // 不更新 lastSelectedIndex，保持 anchor 不變
    }

    /// 清除選取
    func clearSelection() {
        selectedSegmentIDs.removeAll()
        lastSelectedIndex = nil
    }
}
