import CoreMedia

extension CMTime {
    nonisolated var seconds: Double {
        CMTimeGetSeconds(self)
    }

    nonisolated var displayString: String {
        let totalSeconds = max(0, seconds)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let secs = Int(totalSeconds) % 60
        let fraction = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 100)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, secs, fraction)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, secs, fraction)
        }
    }

    nonisolated static func from(seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

extension CMTimeRange {
    nonisolated var durationSeconds: Double {
        duration.seconds
    }

    nonisolated var startSeconds: Double {
        start.seconds
    }

    nonisolated var endSeconds: Double {
        (start + duration).seconds
    }
}
