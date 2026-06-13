import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text(viewModel.currentItem?.fileName ?? "再生していません")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("mini-player-title")

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(height: 3)
                .accessibilityIdentifier("mini-player-progress")

            HStack {
                Text(PlaybackDisplayFormatter.time(viewModel.currentPlaybackPositionSec))
                    .accessibilityIdentifier("mini-player-current-time")
                Spacer()
                Text(PlaybackDisplayFormatter.time(viewModel.currentItem?.durationSec ?? 0))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 44) {
                Button(action: viewModel.skipBackward) {
                    Image(systemName: "gobackward.10")
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("skip-backward-button")

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("play-pause-button")
                .accessibilityValue(viewModel.isPlaying ? "再生中" : "一時停止中")

                Button(action: viewModel.skipForward) {
                    Image(systemName: "goforward.30")
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("skip-forward-button")
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 112)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .disabled(viewModel.currentItem == nil)
    }

    private var progress: Double {
        guard let item = viewModel.currentItem else { return 0 }
        return PlaybackDisplayFormatter.progress(
            position: item.positionSec,
            duration: item.durationSec
        )
    }
}
