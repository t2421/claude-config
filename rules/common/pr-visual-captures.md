# PR Visual Change Captures

## Principle

When a change affects rendered appearance — a web page, a mobile/desktop screen,
a CLI's visually significant output — attach a screenshot (or short capture for
motion/animation) to the pull request. A reviewer should be able to see the
result without pulling the branch and running it locally.

## When to attach

- New UI, or a changed layout, color, spacing, or typography
- A changed responsive breakpoint or component state (hover/focus/error/empty/loading)
- A visual bug fix — attach before/after so the fix is verifiable at a glance
- Any change explicitly requested for its appearance (copy changes on a rendered
  screen, a new button, a redesigned page, etc.)

## When to skip

- Pure logic/backend changes with no rendered-output change
- Refactors that do not alter appearance
- Changes limited to non-visual config, docs, or tests

## How

- Attach images as **PR attachments/comments**, never as committed files in the
  repo — screenshots do not belong in git history. Use the `gh-pr-attach-image`
  skill (or the equivalent `user-attachments` upload flow) to post them without
  adding files to the tree.
- Capture the actual rendered result (the running app/site), not a design mockup.
- Capture the states/breakpoints that actually changed. For web work, mirror the
  breakpoints in [web/testing.md](../web/testing.md#1-visual-regression) (320,
  768, 1024, 1440) when the change is responsive; otherwise one representative
  capture is enough.
- If both light and dark themes exist and the change touches either, capture both.

## Where this fits

This extends the "Draft comprehensive PR summary" step in
[common/git-workflow.md](./git-workflow.md#pull-request-workflow) (an upstream
file — this rule lives here instead of edited into it) — a PR summary for a
visual change is not complete without a capture.
