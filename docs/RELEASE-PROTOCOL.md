# Epic LUT release protocol

When David requests an Epic LUT update or release, complete this sequence. Finish the fix before publishing. His current request controls scope and authorization; do not ask again for an action already authorized. This document is a workflow, not separate permission to deploy or publish.

## 1. Fix and verify

- Read WORKSPACE.md and AGENTS.md; use the canonical OneDrive Epic-LUT repository. Verify Git root, branch and status. Preserve unrelated edits.
- Implement the requested fix and review the changes since the last public tag. Run meaningful focused regressions, formatting checks and required package checks.
- Keep evidence separate: source tests, built package, installed bytes, loader activation and observed live behavior. Describe a live result only when it was observed or confirmed by David.
- Use the authorized managed development workflow for game deployment. Publication does not authorize changing native DLLs, saved settings, game patches or another component. Preserve rollback packages.

## 2. Prepare one public snapshot

- Update VERSION, README, CHANGELOG, `docs/RELEASE-<version>.md`, Nexus BBCode/changelog and the Discord announcement. Explain major new features and how to use them, not only the latest fix. Check feature scope, defaults and consent controls against current source; distinguish tested capabilities from live confirmation still pending. Preserve credits, discovery attribution and vendor/LICENSE.
- Commit and push all relevant public Epic-LUT changes. Exclude game assets and binaries, saved presets/settings, screenshots, logs, private cache/evidence, unrelated work and private research. Check staged paths and the diff before committing.
- Build **BSL**, **modular LLL R30+ (`main.lua`)**, and **bundled API-2 MDL (`mod.lua`)** from the same committed source snapshot. Shared changes require parity across all three. Use standard idle-preview packages; continuous-animation candidates remain separate unless explicitly requested.
- Use versioned filenames under dist or an explicitly named release directory. Never overwrite earlier published artifacts. Include the current release note in the package documentation.
- Verify ZIP contents, entrypoints, dependencies, native DLL identity and package checks. Generate SHA-256 checksums for the exact upload files. Record the source commit and final file hashes.

## 3. GitHub

- Create and push the version tag at the exact release source commit.
- Publish one GitHub release with the release notes, all three verified ZIPs and their checksums. Keep older releases available.
- Verify the public release title, tag, source commit and all asset names. Check the actual download URLs and downloaded bytes against the recorded checksums; a completed form alone is not proof of availability.

## 4. Nexus

- Update the existing [Epic LUT page](https://www.nexusmods.com/helldivers2/mods/17039): current description, major features, version, changelog and installation instructions. Keep historical per-file/per-version revision blocks out of the main description; history belongs in the changelog and retained older downloads.
- Upload the exact same files used for GitHub:
  - **BSL: Main File.**
  - **LLL: Optional File.**
  - **MDL: Optional File, never Main File.**
- Keep the three entrypoints clearly labeled and explain that users enable one copy. Retain older downloads for rollback rather than deleting history.
- Verify public rendering, version/file IDs, categories, download availability and file identity where available. Record the Nexus scan state separately: pending, completed or failed. Upload success does not prove the scan finished or the public download is available.

## 5. Discord

- Update the title and opening post of the [existing Epic LUT thread](https://discord.com/channels/1260111500522295377/1557790003206037527/1557790003206037527).
- Use the current announcement, concise changes, correct download links and loader choices. Retain credits and the Shared Lobby LUT testing notice. Keep within the surface's message limit.
- Verify the rendered title/body and links. Edit the existing post; do not create duplicate announcements or message unrelated channels unless requested.

## 6. Record and report

Store a scoped publication receipt with the source commit, tag/release URL, asset names and SHA-256 hashes, Nexus file IDs/categories/scan state, Discord thread/message links, checks performed, and any pending item. Keep private runtime evidence outside public packages and source.

Report the version and published links, concise validation, and any unresolved publication or scan limitation. Distinguish candidate, uploaded, publicly downloadable and live-proven states. A blocked surface does not prevent finishing authorized work on the other surfaces; never claim a failed or pending publication succeeded.
