import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        HStack(spacing: 16) {
            Text(viewModel.currentItem?.fileName ?? "再生していません")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: viewModel.skipBackward) {
                Image(systemName: "gobackward.10")
            }
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: viewModel.skipForward) {
                Image(systemName: "goforward.30")
            }
        }
        .padding()
        .background(.thinMaterial)
        .disabled(viewModel.currentItem == nil)
    }
}
