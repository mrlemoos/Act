# Automated downloadable macOS releases

Status: active
Domain: Screenwriting, desktop distribution
Owner: Repository maintainers
Related ADRs: None. This change uses the existing app packaging boundary.
Tickets: None

## Problem

Act currently requires a local build. There is no GitHub Actions workflow publishing downloadable app bundles. Repeating local packaging for each change prevents a reliable download from being available after a push.

The existing build script creates an ad-hoc signed app and bundled standalone CLI. This is not Developer ID signing or notarisation. The agreed first release path uses that existing capability without waiting for Apple distribution credentials.

## Intended behaviour

Every push to `main` triggers a macOS build and validation run for that exact commit. A successful run packages `Act.app` as a ZIP and publishes a GitHub Release with a unique tag and downloadable asset. A failed build, check or packaging step does not publish a successful release.

Users download the ZIP, extract the app and copy it to Applications. The release notes identify the source commit, supported macOS version and architecture, installation steps, and the absence of Developer ID signing and notarisation. Gatekeeper may block opening the download and require explicit user approval. No workflow or installation instructions disable Gatekeeper or remove quarantine automatically.

The app and its bundled CLI retain ad-hoc signatures. Users do not need Swift, Bun or Node to run them. Optional local inference runtimes and models remain separate setup, as documented today.

## Acceptance checks

- [ ] A push to `main` triggers a release run for its exact commit; other branches do not publish releases.
- [ ] Existing automated checks pass before publication, including Swift tests and the bundled CLI contract check.
- [ ] A release configuration build produces a ZIP containing one complete `Act.app`, including the executable, CLI helper, icon, localisations and SwiftPM resource bundle.
- [ ] The extracted app and CLI have valid ad-hoc signatures after final metadata changes and packaging.
- [ ] The release tag, asset and notes identify the built commit and actual supported platform. The release targets that commit rather than a later branch head.
- [ ] Two nearby pushes cannot overwrite each other's tags or assets. New pushes do not cancel an already running release.
- [ ] Retrying a run does not silently replace an existing published download. Interrupted publication has a defined recovery path.
- [ ] A failed check, build or archive validation leaves no newly published release advertised as successful. Publication failures are visible in Actions.
- [ ] A fresh download on a supported Mac extracts successfully, opens after any required macOS approval and opens a sample Fountain file. The bundled CLI can report its schema without Bun or Node installed.
- [ ] Release notes clearly state that the app is not Developer ID signed or notarised, and describe optional inference setup separately.
- [ ] The archive contains no personal documents, credentials, private keys, local settings, model downloads or development workspace files.
- [ ] The workflow requires no Apple credentials or manually configured repository secrets. Publication uses the automatically supplied GitHub Actions token with only the permissions required by the relevant job.

## Decisions and contracts

- Trigger: every push to `main`. Validation and publication refer to the triggering commit, not whichever commit is current when a job starts.
- Download format: ZIP containing the app bundle. A DMG or installer package is outside this change.
- Packaging boundary: reuse [scripts/build-app.sh](../../scripts/build-app.sh) with release configuration and preserve its app/CLI resource layout. Any final metadata edits precede final ad-hoc signing.
- Minimum operating system: follow the app's authoritative bundle metadata and Swift package platform requirement, currently macOS 15. Architecture must match the actual build and be stated explicitly.
- Identity: tags use `build-<Actions run ID>-<12-character commit SHA>`; assets use `Act-<tag>-macOS-arm64.zip`. The full commit is recorded in release notes and artifact metadata. The staged app's bundle build number is the Actions run ID; the source marketing version stays unchanged.
- Runner: `macos-15`, with an explicit arm64 check. Downloads support Apple Silicon only. Publication runs separately with write permission; the build job has read permission.
- Queue: concurrency is scoped to the Actions run ID, so separate pushes never displace each other's pending jobs. Publication does not update the latest-release pointer because completion order need not match commit order.
- Retry: an existing published release is preserved. An unpublished draft with the same commit can have interrupted asset uploads replaced before publication. Network failures fail the run rather than being treated as a missing release. No draft or tag is automatically deleted.
- Publication is the final step after validation. Prefer preparing assets on an unpublished draft so partial uploads do not appear as a successful release. Recovery must distinguish an incomplete draft from an existing published release.
- Preserve the existing public bundle identifier, document associations, localisations and standalone CLI contract.
- Changes remain within release automation, packaging support and public installation documentation. No screenplay or planning behaviour changes.
- Public configuration and documentation contain no credentials, personal account details, certificate identities, team identifiers or private filesystem paths. Logs and downloads follow the same boundary.

## Test seam

Approved test seam: an actual GitHub Actions run through GitHub Release download and extraction, with existing Swift tests providing app regression coverage. This is the highest useful seam because local packaging alone cannot prove event triggers, token permissions, publication or downloadable asset integrity.

Prior art is [scripts/build-app.sh](../../scripts/build-app.sh), [scripts/build-cli.sh](../../scripts/build-cli.sh), the existing Swift test suites and the [README build instructions](../../README.md#run). Implementation is [release.yml](../../.github/workflows/release.yml), [release.ts](../../scripts/release.ts) and its [publication regression tests](../../scripts/release.test.ts). Regression tests mock the GitHub CLI boundary; they do not replace the approved live seam.

A supported Mac provides the final first-download check, including Gatekeeper behaviour. CI signature verification does not prove a quarantined download opens on another machine. No new app testing interface is required.

## Validation

Existing local checks:

```sh
swift test --no-parallel
zsh scripts/build-app.sh release
bun CLI/contract.ts --check
codesign --verify --deep --strict .build/Act.app
codesign --verify --strict .build/Act.app/Contents/Helpers/act
node .galicia/check.ts
git diff --check
bun test scripts/release.test.ts CLI/src
```

In Actions, `bun scripts/release.ts package` validates commit identity, assigns build metadata, signs, archives, extracts and verifies signatures, resources and arm64 executables. The extracted CLI reports its schema with a PATH containing no Bun or Node. `bun scripts/release.ts publish` validates artifact identity and SHA-256 before accessing GitHub. Both commands require the Actions-provided commit and run identity environment variables; publication additionally uses the repository identity and automatic token.

Local validation on 2026-11-25: 12 Bun tests passed, including publication retry, upload failure, network failure, conflicting release and checksum rejection. Swift tests passed with three opt-in integration checks skipped. TypeScript checking, CLI contract checking and workflow YAML parsing passed. A release configuration app was built and packaged locally using a synthetic run ID; extraction, ad-hoc signatures, arm64 architecture, resources, localisations and standalone CLI schema checks passed. The local archive is an ignored build output, not a published release. Live Actions publication and a fresh quarantined-download check remain pending; the spec is not complete.

Completion requires links to a successful Actions run and published release, the matching commit and tag, inspection of the downloaded ZIP, and a recorded fresh-download app/CLI smoke check. Failed-run publication and rerun behaviour need evidence as well. Local checks, publication and manual first-open evidence are separate claims. This specification records intended behaviour, not completed release evidence.

## Exclusions

- Developer ID signing, Apple notarisation, stapling and Apple credential provisioning.
- App Store distribution, Windows and Linux builds.
- In-app automatic updates, update feeds and automatic installation.
- Bundling inference runtimes, model weights or user projects.
- Changes to app functionality or unrelated working-tree edits.
- Creating credentials, publishing a release or committing code as part of writing this specification.

## Unresolved decisions

- Live verification: after the implementation reaches `main`, record a successful Actions run, published release and downloaded asset inspection. Until then, hosted runner compatibility and publication permissions remain unverified.
- First-download verification: validation owner must supply a supported Mac and record the observed Gatekeeper and app/CLI behaviour before marking complete.
