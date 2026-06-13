# Step 3 Claude Code Handoff

## Current State

- Repository: `/Users/wata/Documents/repo/github.com/po-oq/Muuzx`
- Branch: `codex/step3-playback-state-ui-design`
- Next task: **Task 3**
- Do not redo Task 0, Task 1, or Task 2.
- Task 3 and later have not been started.

Primary documents:

- Design: `docs/superpowers/specs/2026-06-06-step3-playback-state-ui-design.md`
- Implementation plan: `docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md`
- UI target: `docs/ui-mock.html`

Continue from:

```text
docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md
Task 3: AudioListViewModel に再生状態遷移と長押し操作を追加する（TDD）
```

## Completed Work

### Task 0: Audio metadata loading

Completed and reviewed.

- Added `AudioMetadataLoading`
- Added `AudioMetadataService`
- Loads duration asynchronously with `AVURLAsset`
- Invalid or unavailable duration throws `AudioMetadataError.durationUnavailable`

Commits:

```text
cefd1b7 feat: add audio metadata loading
```

### Task 1: Playback session controls

Completed and reviewed.

- Added playback from a requested position
- Added current position and duration accessors
- Added `stop()`
- Added completed-item notification before advancing
- Preserves requested position while duration is not loaded

Commits:

```text
8986e91 feat: extend playback session controls
60e94e4 fix: preserve playback position before duration loads
```

### Task 2: ViewModel metadata loading

Completed and reviewed.

- `AudioListViewModel` displays the file list immediately
- Durations are loaded and applied asynchronously
- Previous metadata task is cancelled when the list reloads
- Stale results cannot update the new list
- Cancellation regression test uses deterministic synchronization

Commits:

```text
3c64c1f feat: load audio durations asynchronously
0cdfa05 test: cover audio metadata cancellation
0443365 test: make metadata cancellation test deterministic
```

## Review Status

Tasks 0, 1, and 2 were implemented with Subagent-Driven Development.

Each completed task passed:

1. TDD RED/GREEN verification
2. Specification compliance review
3. Code quality review

Task 2 required two quality-review fix loops before final approval.

Latest verified results:

```text
AudioListViewModelTests: 4 passed
All unit tests: 51 passed
Task 2 tests repeated 50 times: passed
git diff --check: passed
project.pbxproj lint: passed
```

No full UI test run has been performed for Step 3 yet. UI work begins in later tasks.

## Important Implementation Notes

- The implementation uses the actual Task 0 API:

```swift
func duration(for url: URL) async throws -> Double
```

The implementation-plan snippets may show `durationSec(for:)`; follow the compiling API unless deliberately renaming it across all callers and tests.

- `AudioListViewModel` is `@MainActor`.
- `metadataTask` cancellation behavior is covered by deterministic regression tests.
- `metadataTaskDidFinishProcessing` is an internal test hook. It defaults to `nil` and is used only to deterministically observe cancelled task completion.
- Do not implement JSON persistence in Step 3. That belongs to Step 4.
- Do not implement background playback or Now Playing UI in Step 3. That belongs to Step 5.
- Do not redesign the folder screen in Step 3. That belongs to Step 7.
- Preserve the existing accessibility identifiers because Task 6 extends the UI smoke test.

## Recommended Claude Code Prompt

```text
Use Subagent-Driven Development and continue Step 3 from Task 3.

Read:
- docs/superpowers/STEP3-CLAUDE-CODE-HANDOFF.md
- docs/superpowers/specs/2026-06-06-step3-playback-state-ui-design.md
- docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md

Tasks 0-2 are complete, reviewed, and committed. Start at Task 3.
Follow TDD and perform specification review followed by code-quality review after every task.
Do not implement features assigned to Step 4 or later.
```

## Verification Commands

Use the explicit simulator destination:

```bash
xcodebuild test -scheme AudioFolderPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData \
  -only-testing:AudioFolderPlayerTests
```

Full test command:

```bash
xcodebuild test -scheme AudioFolderPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

After adding Swift files:

```bash
xcodegen generate
```

## Expected Git State

Before continuing:

```bash
git switch codex/step3-playback-state-ui-design
git status --short --branch
git log --oneline -10
```

Expected: clean worktree on `codex/step3-playback-state-ui-design`, with `0443365` in history.
