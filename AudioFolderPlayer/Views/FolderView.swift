import SwiftUI

struct FolderView: View {
    @ObservedObject var folderViewModel: FolderViewModel
    @ObservedObject var audioListViewModel: AudioListViewModel
    @State private var isShowingFolderPicker = false
    @State private var isShowingAudioList = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                summarySection
                actionSection
                Spacer()
            }
            .padding()
            .navigationTitle("フォルダ")
            .sheet(isPresented: $isShowingFolderPicker) {
                FolderPicker(
                    onPick: { url in
                        isShowingFolderPicker = false
                        Task {
                            await folderViewModel.importFolder(url)
                        }
                    },
                    onCancel: {
                        isShowingFolderPicker = false
                    }
                )
            }
            .alert("取り込みできませんでした", isPresented: errorBinding) {
                Button("OK") {
                    folderViewModel.errorMessage = nil
                }
            } message: {
                Text(folderViewModel.errorMessage ?? "")
            }
            .navigationDestination(isPresented: $isShowingAudioList) {
                AudioListView(
                    viewModel: audioListViewModel,
                    folderName: folderViewModel.summary?.folderName
                )
            }
            .onAppear {
                audioListViewModel.load()
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("前回の取り込み元")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(folderViewModel.summary?.folderName ?? "未選択")
                    .font(.title3)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("folder-summary-title")

                if let summary = folderViewModel.summary {
                    Text("\(summary.fileCount)ファイル・\(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))")
                        .foregroundStyle(.secondary)
                    Text("最終取り込み: \(summary.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("音声フォルダを選択してください。")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                isShowingFolderPicker = true
            } label: {
                Label("別フォルダを選択", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(folderViewModel.isImporting)
            .accessibilityIdentifier("choose-folder-button")

            if folderViewModel.hasImportedAudio || !audioListViewModel.items.isEmpty {
                Button {
                    audioListViewModel.load()
                    isShowingAudioList = true
                } label: {
                    Label("一覧を開く", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open-audio-list-button")
            }

            if folderViewModel.isImporting {
                ProgressView(progressText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var progressText: String {
        guard let progress = folderViewModel.progress else {
            return "取り込み中..."
        }
        return "\(progress.completedFiles) / \(progress.totalFiles): \(progress.currentFileName)"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { folderViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    folderViewModel.errorMessage = nil
                }
            }
        )
    }
}
