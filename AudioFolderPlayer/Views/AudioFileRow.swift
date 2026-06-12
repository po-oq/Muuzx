import SwiftUI

struct AudioFileRow: View {
    let item: AudioItem
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName)
                    .font(.body)
                    .fontWeight(item.status == .unplayed ? .bold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(PlaybackDisplayFormatter.subtitle(
                    status: item.status,
                    position: item.positionSec,
                    duration: item.durationSec
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: PlaybackDisplayFormatter.progress(
                    position: item.positionSec,
                    duration: item.durationSec
                ))
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(height: 3)
            }

            Spacer(minLength: 8)

            Text(badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isCurrent ? .blue : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule())
                .accessibilityIdentifier("audio-status-\(item.fileName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var badgeText: String {
        if isCurrent { return "再生中" }

        switch item.status {
        case .unplayed:
            return "未再生"
        case .inProgress:
            guard item.durationSec.isFinite, item.durationSec > 0 else { return "途中" }
            let percent = Int(PlaybackDisplayFormatter.progress(
                position: item.positionSec,
                duration: item.durationSec
            ) * 100)
            return "\(percent)%"
        case .played:
            return "100%"
        }
    }
}
