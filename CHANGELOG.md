# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org).

## [Unreleased]

### Added

- Right-clicking a sub-issue opens the same menu as a card on the board (status, priority, assign to me, copy link,
  open on GitHub). Sub-issues that aren't on the board offer what applies to them: mark as done or reopen, and the
  links.
- Sub-issue rows show their priority, in the same order as list rows.

### Changed

- Clicking the account at the top of the sidebar opens a menu with Sync Now, Appearance, Settings and Sign Out.
  The separate "…" button next to the sync status is gone.
- The sync status sits lower, lines up with the sidebar's icons, and shows a capsule on hover.

### Fixed

- Typing straight after pressing C (or ⌘N, or ⌘K) no longer loses the first letters: keys pressed before the
  title field has focus are held and handed to it. If anything takes focus away while the new-issue dialog
  appears, the title gets it back.
- The board now shows a loading state while a project is fetched for the first time, as the list already did.
  Both say so when you are offline or the project can't be loaded, instead of loading forever.

## [0.1.0] - 2026-10-01

First public version.

### Added

- Board for GitHub Projects with drag and drop between and within columns, including spring animations,
  auto-scroll near the edges and cancelling with Escape.
- List grouped by status, and "My Issues" across all projects.
- Issue view with Markdown, sub-issues, comments and editable status, priority, assignees and labels.
- Creating issues and sub-issues.
- Adding, renaming, recolouring and removing status columns, and reordering them by dragging their headers.
- Reordering the list's sections by dragging their headers (kept as a local preference).
- Command palette and single-key shortcuts for the common actions.
- Back and forward navigation with ⌘[ and ⌘], mouse side buttons and trackpad swipes.
- Local database with instant edits, an offline queue, and background sync with GitHub.
- Conflict handling: field-level changes, automatic merging of description edits, and a choice when edits overlap.
- Light and dark appearance, or following the system, and a choice of Dock icons.
- Sign-in with the GitHub CLI, a personal access token, or the OAuth device flow.

[Unreleased]: https://github.com/lukaskaibel/git-issues-mac-app/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lukaskaibel/git-issues-mac-app/releases/tag/v0.1.0
