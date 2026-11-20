---
description: Commit pending work, bump the version, push main and tag a release (CI builds and publishes it)
argument-hint: "[patch | minor | major | X.Y.Z]"
---

Release AirBuds: commit what's pending, bump the version, push `main`, tag it,
and follow the Release workflow until the GitHub release is published.

Requested version: `$ARGUMENTS` (empty means you suggest one, see step 2).

## How releases work here

- **Version:** `CFBundleShortVersionString` in `Resources/Info.plist` is the only
  version number to edit. Leave `CFBundleVersion` at `1`, because CI stamps the build
  number from the run.
- **Tags:** pushing an annotated tag `vX.Y.Z` with the message `AirBuds X.Y.Z`
  starts `.github/workflows/release.yml`. That workflow runs the checks, builds a
  universal app, packages the DMG, zip and `SHA256SUMS.txt`, signs `appcast.xml`
  (needs the `SPARKLE_PRIVATE_KEY` secret) and publishes the GitHub release.
- **Branch:** releases are cut from `main`.
- **Commit style:** a short summary of the change. A release commit ends with
  `; version X.Y.Z`, as in `Disconnect button on the main page, Quit in Quick Settings; version 0.2.2`.

## Steps

1. **Look first.** Run `git status`, `git branch --show-current`, `git log --oneline -5`,
   `git tag --sort=-v:refname | head -3`, read the current version from Info.plist,
   and run `git log --oneline <last tag>..HEAD` plus `git diff` to see what's
   shipping. Stop and report if:
   - nothing has changed since the last tag and nothing is uncommitted, or
   - the working tree has files that look unrelated or unfinished.

2. **Pick the version.**
   - `patch`, `minor` or `major`: bump that part of the current version.
   - `X.Y.Z`: use it as given. It must be higher than the last tag.
   - Empty: suggest `minor` if the changes add features and `patch` for fixes,
     and ask the user to confirm before going on.

   The tag `vX.Y.Z` must not already exist locally or on `origin`.

3. **Branch.** If you're not on `main`, ask whether to fast-forward `main` to this
   branch (`git switch main && git merge --ff-only <branch>`) or stop so they can
   open a PR. Never force-push and never rewrite `main`'s history.
   Run `git pull --ff-only` on `main` before continuing.

4. **Preflight.** These must pass before anything is committed:
   - `swift build`
   - `swift run AirBudsKitChecks` (must end with `0 failed`)
   - `scripts/build-app.sh` (release build, as CI does)

   If a build fails with "There is no XCFramework found", `.build/` is stale (for
   example from a moved checkout). Say so and offer `rm -rf .build`; don't delete it
   without asking. If any view under `Sources/AirBuds/Views/` changed since the last tag,
   regenerate the screenshots with
   `AIRBUDS_SNAPSHOT=docs/screenshots swift run AirBuds` and include them.
   If files were added, moved or renamed, check that the source map in
   `docs/ARCHITECTURE.md` and the layout in `README.md` match.

5. **Bump and commit.**
   `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y.Z" Resources/Info.plist`.
   - Uncommitted work: commit it together with the bump, as `<summary>; version X.Y.Z`.
   - Everything already committed: commit only the bump, as `Version X.Y.Z`.

   Stage specific files, not `git add -A`, so stray files don't ship. Show the
   commit (`git show --stat HEAD`) before pushing.

6. **Push and tag.**
   ```bash
   git push origin main
   git tag -a vX.Y.Z -m "AirBuds X.Y.Z"
   git push origin vX.Y.Z
   ```

7. **Follow the release.** Find the run with
   `gh run list --workflow release.yml --limit 1`, then `gh run watch <id> --exit-status`
   (run it in the background if it takes long). When it finishes, check
   `gh release view vX.Y.Z --json assets,url`. It should have
   `AirBuds-X.Y.Z.dmg`, a zip, `SHA256SUMS.txt` and `appcast.xml`. If
   `appcast.xml` is missing, the `SPARKLE_PRIVATE_KEY` secret isn't set and
   installed copies won't be offered the update. Say so clearly.
   If the run fails, show the failing step (`gh run view <id> --log-failed`) and stop.
   Don't delete or move the tag unless the user asks.

8. **Report.** Give the version, the commit, the release URL and the assets, plus any
   warnings (no appcast, screenshots not regenerated, docs out of date).
