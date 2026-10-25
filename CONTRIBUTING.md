# Contributing to Breather

Thanks for helping make Breather better.

## Reporting bugs

Open an [issue](https://github.com/jals413/breather/issues/new/choose) with:

- your macOS version and Mac model,
- what you expected and what happened,
- the output of `Breather.app/Contents/MacOS/Breather --diagnose` if it's about Smart Pause (it shows what each detector sees; nothing is sent anywhere).

## Suggesting features

Open an issue describing the problem you'd like solved before the solution — it helps keep Breather calm and focused.

## Pull requests

1. Fork and create a branch from `main`.
2. Build and test:
   ```bash
   scripts/build.sh --run
   swift test
   ```
3. Keep changes focused, and match the surrounding code: comments explain *why*, names say *what*.
4. UI changes: include a before/after screenshot. `--render-snapshots <dir>` produces consistent ones.
5. Don't add analytics, tracking or network calls beyond the existing update check.

By contributing you agree that your contributions are licensed under the [GPL-3.0](LICENSE).

## Releasing (maintainers)

1. Update `CHANGELOG.md`.
2. Tag and push: `git tag v1.2.3 && git push origin v1.2.3`.
3. GitHub Actions builds the universal zip + DMG, publishes the release with checksums, and updates the Homebrew tap.
