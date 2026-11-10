# Project board validation

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: [Approved slices](tickets/01-slice.md)

## Automated evidence

`swift test` passed 85 tests, comprising 43 ActCore tests and 42 native ActApp tests. New checks cover project save/reopen, source bytes including UTF-8 BOM and CRLF, removal/undo, version and identity validation, group movement, scene changes/missing scenes, bounded anchored navigation, routing, external-save conflicts, save-copy recovery and write failure.

`scripts/build-app.sh` produced the locally signed `.build/Act.app`. `node .galicia/check.ts` and `git diff --check` passed. No release or publication occurred.

## Native evidence

Actual app launched using CUA. File > New Project opened the board while ordinary New retained the screenplay editor. A note was created and its title/body edited through native accessibility controls. File > Save opened the project save panel and saved a local test project. The save panel treats a full path typed into its name field as a literal filename; use its folder controls for destination navigation.

Native view renders were produced at 1280 and 820 points in light/dark appearances under `.scratch/project-board/`. Their offscreen toolbar capture has a black strip; the real app screenshot showed the full toolbar correctly.

## Outstanding evidence

Card drag attempts did not establish movement. Later attempts returned CUA `ScreenCaptureKit.SCStreamErrorDomain Code=-3812` and `noWindowsAvailable`. Gesture priority was adjusted, but successful native drag and pinch evidence is still required. Do not interpret tested coordinate transformations as physical trackpad proof.

Group dragging, relinking dialogs, asset opening/sharing, close/reopen and crash/relaunch recovery still need complete desktop workflow checks. Native persistence APIs and conflict tests cover state preservation, not these OS interaction paths. Parent specification and relevant tickets remain active.

## Reference contracts

Version-1 JSON uses `.actboard`, absolute local file paths and UUID identities. No sources are moved or copied. Removed draft cards leave dependent provenance unresolved until undo or explicit original-draft relinking. Cross-draft sharing references the original asset and opens the original owning draft; it does not merge character libraries or transplant shot anchors.

## Main-window tab follow-up

Board now appears in the existing workspace picker beside Screenplay, Shot list and Characters. Selecting Board creates an unsaved project only when needed. New Project and opening `.actboard` attach to the active writing workspace, creating a writing window only when none exists. Project documents no longer create a separate board window.

Save, Save As, Revert and window Undo route to project state on the Board tab. Closing the host protects project edits and keeps existing screenplay/sidecar safeguards. Replacing an edited board requires explicit save/discard/cancel.

Two additional native tests verify attachment without a project window, independent undo routing, detachment and board-tab saving while the host screenplay remains unsaved. All 85 regression tests passed; local app bundle rebuilt. CUA verified the actual main window with Board selected in its four-tab workspace picker. Preview renders now use the full workspace at `.scratch/project-board-tab/`.

Earlier physical gesture/recovery limitations remain unchanged.
