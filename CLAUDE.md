# i want ur pod

Project-specific guidance for Claude Code. Auto-loaded for sessions started in this directory.

## Verification

After making UI or code changes, always launch and visually verify the running app (open the app/emulator or take a screenshot), not just run build/test.

## CSS / Frontend Conventions

For mobile scroll-lock, use `position: fixed` on the body rather than `overflow: hidden`, which does not block touch scrolling.

## Deployment

When deploying to a device or working with Xcode UI, provide numbered 1-2-3 steps and confirm each menu label matches the user's actual UI before proceeding.

## Remote / SSH Operations

Before starting extraction/copy to remote SSH directories, confirm the exact target directory path with the user first.

## Debugging

When a fix doesn't render, suspect stale build cache (e.g. corrupted `.next`) and check for concurrent build/dev processes before assuming the code is wrong.
