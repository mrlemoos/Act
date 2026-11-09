# Act

A macOS screenwriting app built in Swift, SwiftUI and AppKit. Fountain files remain plain text. Courier writing, scene navigation, PDF export and a separate shot-planning workspace share one document window.

## Run

Requires macOS 15 or later and a Swift 6 toolchain.

```sh
swift test
scripts/build-app.sh
open .build/Act.app
```

The script creates a locally ad-hoc signed development app. It is not a notarised distribution release. Open `Examples/FirstLight.fountain` for a short sample.

## Write

Open a `.fountain` file with Command-O. Save with Command-S. Act preserves UTF-8 source and its byte order marker. The formatted view dims Fountain markers outside the current element. Source mode shows the original text. The outline includes `#` sections and `=` synopsis bodies beneath their scene or section. Each entry navigates to its own source line. Section headings use pink for `#`, blue for `##` and orange for `###` and deeper levels, in both editor and outline. The scene outline is hidden by default. Show it with Command-Option-1 to move through the screenplay. Source and PDF export are in the toolbar menu; the editor has no persistent counters or status bar.

Command-F opens Find. Command-Shift-M toggles source mode, Command-Option-1 toggles the outline and Command-Shift-E exports a PDF. Screenplays use native document autosave and undo. If the backing file has changed externally, Act refuses to overwrite it. Use Save As to keep your version separately, or Revert to Saved to reload.

Typed straight apostrophes automatically become right curly apostrophes. Loaded files and multi-character pastes retain their text. Undo and redo use the normal document history.

Return inserts two line breaks between screenplay blocks. Character cues, dialogue and parentheticals use one. Press Return twice to leave a dialogue block. Existing LF, CRLF or CR line endings are preserved, and each Return remains one undo step.

## Writing settings

Open the right settings sidebar with Act > Settings, Command-comma or the toolbar menu. Live examples show each style change alongside the screenplay. Close the sidebar with its upper-right control. Choose an installed font and point size, one or two blank lines before scene headings, bold or regular scene headings, and automatic dialogue CONT'D. Preferences apply across windows and PDF export and survive app restarts. Defaults are Courier 12 pt, two blank lines, bold headings and continuations on. The editor uses a readable zoom relative to print size.

Automatic CONT'D appears when the same speaker resumes after action within a scene. PDF page breaks also add MORE and repeated continued cues. Turning the option off leaves explicit cues already written in the source untouched. These are display/export changes; Fountain source and whitespace stay unchanged.

## Plan shots

Select Shot list. Add shots yourself or open Local AI to configure generation. Shot lists save separately as `.shots.json`; framing and action stay visible, while Details reveals camera movement and rationale. Right-click a shot to delete it. Open, Save Copy and Local AI are in the shot-list menu. Command-S saves the active workspace. Save Copy preserves another version.

Scene text changes flag existing shots for review. Deleted or renamed unnumbered scenes leave their shots visible in a separate section. Explicit Fountain scene numbers give more stable links when headings change. Inserting or deleting repeated unnumbered headings can change their references; review the warnings before using old plans.

Act keeps local shot-list recovery data under `~/Library/Application Support/Act/ShotRecovery`. Recovery records preserve saved paths and migrate when the screenplay is first saved or renamed. A native restored untitled screenplay can recover a unique matching unsaved shot list. Ambiguous matches remain untouched. Close Without Saving discards the recovery copy. Native crash/relaunch recovery still needs manual validation.

## Local AI

Install the local runtime if necessary:

```sh
brew install llama.cpp
```

Act discovers the Homebrew runtime, preferring `llama-completion` for clean structured output. You can select a runtime executable yourself. Local AI offers an explicit download of the official Qwen2.5 7B Instruct Q4_K_M model, about 4.68 GB across two verified shards. Downloaded files use pinned sizes and SHA-256 hashes. Alternatively, select a compatible existing GGUF instruct model. A split model requires all sibling shards in the same folder; select the first shard.

Generation passes only the selected scene to a local subprocess, using Metal and the runtime's offline flag. There is no cloud fallback. Cancel stops the subprocess; failed generation preserves existing shots. Successful regeneration replaces shots for the selected scene after explicit confirmation. Generated suggestions need editorial review.

Models are stored under `~/Library/Application Support/Act/Models`. Runtime and model paths are stored in local preferences. Inference has a 12,000-byte scene limit and a 180-second deadline. The production downloader and actual offline inference have been verified with the recommended 7B model. Suggestions can still invent details and need review. The verified model already exists in `.scratch/recommended-model`; choose its first shard in Local AI to reuse it without another download.

To run the opt-in real-model adapter check:

```sh
ACT_TEST_MODEL=/absolute/path/to/model.gguf swift test --filter GenerationTests
```

## Project records

The [specification](docs/specs/screenwriting/spec.md) links eight approved tickets. [Inference research](docs/specs/screenwriting/local-inference-research.md) records runtime/model sources and actual verification. [Validation](docs/specs/screenwriting/validation.md) distinguishes automated checks from native UI and model evidence.

## Tests

Run `swift test` for core and hidden native-view regressions. The two real-model checks are opt-in. [Coverage and commands](Tests/README.md) distinguish automated evidence from remaining desktop checks.
