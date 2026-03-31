import Foundation

struct SRTParser {
    enum ParseError: Error, LocalizedError {
        case cannotReadFile
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .cannotReadFile: "無法讀取字幕檔案"
            case .invalidFormat:  "字幕格式無效"
            }
        }
    }

    /// 解析 SRT 檔案，回傳依 startTime 排序的字幕條目
    static func parse(url: URL) throws -> [SubtitleEntry] {
        let content = try readFile(at: url)
        return parseContent(content)
    }

    /// 讀取檔案，支援 UTF-8 及 UTF-16
    private static func readFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        // 嘗試 UTF-8
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        // 嘗試 UTF-16
        if let str = String(data: data, encoding: .utf16) {
            return str
        }
        // 嘗試 UTF-16 Little Endian
        if let str = String(data: data, encoding: .utf16LittleEndian) {
            return str
        }
        // 嘗試 UTF-16 Big Endian
        if let str = String(data: data, encoding: .utf16BigEndian) {
            return str
        }

        throw ParseError.cannotReadFile
    }

    /// 解析 SRT 內容字串
    static func parseContent(_ content: String) -> [SubtitleEntry] {
        // 統一換行符號
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // 移除 BOM
        let clean = normalized.hasPrefix("\u{FEFF}")
            ? String(normalized.dropFirst())
            : normalized

        // 按空行分割區塊
        let blocks = clean.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var entries: [SubtitleEntry] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            // 尋找時間碼行（包含 -->）
            var timeLineIndex: Int?
            for (i, line) in lines.enumerated() {
                if line.contains("-->") {
                    timeLineIndex = i
                    break
                }
            }

            guard let tIdx = timeLineIndex,
                  let (start, end) = parseTimeLine(lines[tIdx]) else {
                continue
            }

            // 時間碼行之後的所有行為字幕文字
            let textLines = lines[(tIdx + 1)...]
            let rawText = textLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 移除 HTML tag
            let text = removeHTMLTags(rawText)

            guard !text.isEmpty else { continue }

            entries.append(SubtitleEntry(
                startTime: start,
                endTime: end,
                text: text
            ))
        }

        // 按 startTime 排序
        return entries.sorted { $0.startTime < $1.startTime }
    }

    /// 解析時間碼行 "HH:MM:SS,mmm --> HH:MM:SS,mmm"
    private static func parseTimeLine(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)

        guard let start = parseTimeCode(startStr),
              let end = parseTimeCode(endStr) else {
            return nil
        }

        return (start, end)
    }

    /// 解析單一時間碼 "HH:MM:SS,mmm" 或 "HH:MM:SS.mmm"
    private static func parseTimeCode(_ str: String) -> Double? {
        // 支援逗號或句號分隔毫秒
        let normalized = str.replacingOccurrences(of: ",", with: ".")
        let components = normalized.components(separatedBy: ":")

        guard components.count == 3 else { return nil }

        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let secondsAndMs = Double(components[2]) else {
            return nil
        }

        return hours * 3600 + minutes * 60 + secondsAndMs
    }

    /// 移除 HTML tag（<i>、<b>、<u>、<font> 等）
    private static func removeHTMLTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }
}
