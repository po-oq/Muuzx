import Foundation

enum PlaybackDisplayFormatter {
    static func time(_ seconds: Double) -> String {
        let total: Int
        if seconds.isFinite,
           seconds > 0,
           let converted = Int(exactly: seconds.rounded(.down)) {
            total = converted
        } else {
            total = 0
        }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func progress(position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    static func subtitle(
        status: PlaybackStatus,
        position: Double,
        duration: Double
    ) -> String {
        let hasKnownDuration = duration.isFinite && duration > 0

        switch status {
        case .unplayed:
            return hasKnownDuration ? "未再生・\(time(duration))" : "未再生"
        case .inProgress:
            return hasKnownDuration
                ? "途中・\(time(position)) / \(time(duration))"
                : "途中・\(time(position))"
        case .played:
            return hasKnownDuration ? "完了・\(time(duration))" : "完了"
        }
    }
}
