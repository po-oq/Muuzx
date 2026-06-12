import SwiftUI

struct AudioListView: View {
    @ObservedObject var viewModel: AudioListViewModel
    let folderName: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ファイル一覧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                viewModel.play(item)
                            } label: {
                                AudioFileRow(
                                    item: item,
                                    isCurrent: item.id == viewModel.currentItemId
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    if item.id == viewModel.currentItemId {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                            .padding(.trailing, 14)
                                            .padding(.bottom, 12)
                                            .accessibilityIdentifier("current-item-speaker")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("audio-row-\(item.fileName)")
                            .contextMenu {
                                Button {
                                    viewModel.playFromBeginning(item)
                                } label: {
                                    Label("先頭から再生", systemImage: "play.fill")
                                }

                                Button {
                                    viewModel.markUnplayed(item)
                                } label: {
                                    Label("未再生に戻す", systemImage: "arrow.counterclockwise")
                                }
                            }

                            if index < viewModel.items.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))

            MiniPlayerView(viewModel: viewModel)
        }
        .navigationTitle(folderName ?? "ファイル一覧")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
            viewModel.startObservingPlaybackIfNeeded()
        }
        .onDisappear { viewModel.stopObservingPlayback() }
    }
}
