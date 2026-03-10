# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app (choose a target device/platform)
flutter run

# Run on a specific platform
flutter run -d macos
flutter run -d chrome

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze (lint)
flutter analyze

# Format code
dart format lib/ test/

# Get/update dependencies
flutter pub get
flutter pub upgrade
```

## Architecture

This is an early-stage Flutter app. Currently all code lives in `lib/main.dart`:

- `IcebreakerApp` — root `MaterialApp`, dark theme, no debug banner
- `HomeScreen` — full-screen black scaffold with a centered "GO LIVE" tap target (pink heart icon + bold text)

The app targets 6 platforms: Android, iOS, macOS, Linux, Web, Windows. Platform-specific config lives in the respective top-level directories (`android/`, `ios/`, `macos/`, etc.).

## Conventions

- Commit messages follow **Conventional Commits**: `feat:`, `fix:`, `chore:`, `refactor:`, `style:`, `test:`, `docs:`
- Dart SDK: `^3.11.1`, linting via `flutter_lints`
- GitHub repo: `icebreakersupport-lab/icebreaker` (private)

## Git Workflow

After every meaningful unit of work — a new screen, a bug fix, a refactor, a dependency addition — commit and push immediately:

```bash
git add <specific files>
git commit -m "feat: description of what was done"
git push
```

Never leave significant work uncommitted. Each commit should represent a coherent, working change so the GitHub history always reflects the true state of the project.
