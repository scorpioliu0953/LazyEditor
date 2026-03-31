import CoreMedia

extension Array where Element == ClipSegment {
    /// 在指定片段的本地時間點分割成兩個片段
    func splitting(segmentID: UUID, at localTime: Double) -> [ClipSegment] {
        var result: [ClipSegment] = []
        for segment in self {
            if segment.id == segmentID {
                let splitPoint = segment.startTime + localTime
                guard splitPoint > segment.startTime && splitPoint < segment.endTime else {
                    result.append(segment)
                    continue
                }
                let first = ClipSegment(
                    clipID: segment.clipID,
                    startTime: segment.startTime,
                    endTime: splitPoint,
                    volumeDB: segment.volumeDB
                )
                let second = ClipSegment(
                    clipID: segment.clipID,
                    startTime: splitPoint,
                    endTime: segment.endTime,
                    volumeDB: segment.volumeDB
                )
                result.append(first)
                result.append(second)
            } else {
                result.append(segment)
            }
        }
        return result
    }
}

extension ClipSegment {
    /// 排除靜音範圍後，回傳保留的子片段
    /// - Parameter padding: 在靜音邊界前後各保留的緩衝時間（秒）
    func excludingRanges(_ ranges: [CMTimeRange], padding: Double = 0) -> [ClipSegment] {
        // 將靜音範圍限縮到此片段的時間範圍內，並套用 padding 縮減
        let clipped = ranges.compactMap { range -> (Double, Double)? in
            let rangeStart = range.startSeconds
            let rangeEnd = range.endSeconds

            let paddedStart = rangeStart + padding
            let paddedEnd = rangeEnd - padding

            guard paddedStart < paddedEnd else { return nil }

            let clampedStart = max(paddedStart, startTime)
            let clampedEnd = min(paddedEnd, endTime)
            guard clampedStart < clampedEnd else { return nil }
            return (clampedStart, clampedEnd)
        }.sorted { $0.0 < $1.0 }

        guard !clipped.isEmpty else { return [self] }

        var result: [ClipSegment] = []
        var cursor = startTime

        for (silenceStart, silenceEnd) in clipped {
            if cursor < silenceStart {
                result.append(ClipSegment(
                    clipID: clipID,
                    startTime: cursor,
                    endTime: silenceStart,
                    volumeDB: volumeDB
                ))
            }
            cursor = silenceEnd
        }

        if cursor < endTime {
            result.append(ClipSegment(
                clipID: clipID,
                startTime: cursor,
                endTime: endTime,
                volumeDB: volumeDB
            ))
        }

        return result
    }
}
