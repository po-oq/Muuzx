import SwiftUI

struct AudioListView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(viewModel.items) { item in
                Button {
                    viewModel.play(item)
                } label: {
                    HStack {
                        Text(item.fileName)
                            .fontWeight(item.status == .unplayed ? .bold : .regular)
                        Spacer()
                        if item.id == viewModel.currentItemId {
                            Image(systemName: "speaker.wave.2.fill")
                                .accessibilityIdentifier("current-item-speaker")
                        }
                    }
                }
                .accessibilityIdentifier("audio-row-\(item.fileName)")
            }
            MiniPlayerView(viewModel: viewModel)
        }
        .onAppear { viewModel.load() }
    }
}
