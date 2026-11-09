# 13. Persistent regression coverage

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Core and native editor regressions run through the standard Swift package test command, including behaviours previously checked only in scratch harnesses.

## What to build

Add an ActAppTests target that imports the executable module with test access and hosts actual AppKit/SwiftUI views in hidden test-owned windows. Exercise text insertion, Return, curly apostrophes, selections, caret placement, undo/redo, source mode, UTF-8 BOM, safe native saves and external conflicts. Use isolated preference suites and temporary files.

Verify font settings, system semibold section headings and level colours, heading weight/spacing, continuation presentation, live settings/examples and right-sidebar reflow. Exercise shot workspace mutation guards and failure preservation. Expand core tests only for uncovered behavioural boundaries. Preserve opt-in actual Metal inference/model checks; default tests must not download models.

Use native text/layout evidence and same-run example render comparisons, without stored snapshot goldens or source-code matching. No system input, visible app windows or attachment to the user's live Act process.

## Acceptance checks

- [x] Native text behaviours and safe-save protections are repeatable under swift test.
- [x] Preference persistence, formatting and sidebar layout use actual views/model state.
- [x] Shot planning guards and runtime errors preserve existing work.
- [x] Core regressions cover additional Unicode, malformed-data, PDF and output boundaries.
- [x] Final added presentation tests and the complete suite pass.
- [x] Coverage and remaining manual checks are documented.

## Validation

```sh
swift test
swift test --filter NativeEditorTests
```

Real-model validation remains explicit:

```sh
ACT_TEST_MODEL="$PWD/.scratch/recommended-model/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf" ACT_TEST_DOWNLOAD_DIRECTORY="$PWD/.scratch/recommended-model" swift test
```

The final full run passed all 105 tests with no failures or skips: 46 XCTest cases, 33 core Swift Testing cases and 26 native app cases. Both actual cached-model checks were enabled. The default command skips only the two opt-in real-model cases. Cancellation now requires a confirmed running fixture process and checks prompt termination.

The hidden SwiftUI host did not expose accessibility nodes. Tests therefore use native caret/layout state and same-run render comparisons of the actual observed example component. They do not claim physical button, menu, keyboard or assistive-technology integration coverage. [Coverage and commands](../../../../Tests/README.md) records these boundaries.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Relevant code or domain context: [Context map](../../../../context.md)
- Validation: [Evidence](../validation.md)

## Out of scope

- OS crash/relaunch restoration, system input methods and file-dialog automation.
- Guaranteed creative fidelity of generated shots.
- New runtime packaging, cloud services or external CI configuration.
