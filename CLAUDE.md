# Storilex — Claude Code Project Instructions

## 1. Project Overview

Storilex is a cross-platform, offline-first English reading and language-learning application built with Flutter and Dart.

Repository: `hamitgk-beep/vocabloom`

The application includes an English–Turkish dictionary, book reader, grammar analysis, vocabulary learning, phrase recognition, multilingual interface, and offline text-to-speech.

Read `README.md`, `pubspec.yaml`, and relevant source files before making architectural assumptions. The repository is the source of truth.

## 2. Development Principles

Follow these principles for all development tasks:

- Understand the existing implementation before editing.
- State important assumptions and clarify genuine ambiguities.
- Prefer the simplest solution that meets the requirements.
- Make small, targeted changes.
- Do not refactor unrelated code.
- Preserve existing functionality and compatibility.
- Define verifiable success criteria.
- Never claim a test passed unless it was actually executed successfully.

## 3. Installed Skills

Use available skills when relevant:

**Superpowers**
- Use its planning, debugging, testing, and implementation workflows for appropriate tasks.
- Avoid unnecessary planning overhead for trivial changes.

**UI UX Pro Max**
- Use for UI design, visual consistency, accessibility, responsive layouts, and design-system improvements.
- Apply Flutter-compatible guidance.
- Do not introduce React, Tailwind, shadcn/ui, or web-only dependencies into Flutter code.

**Karpathy Guidelines**
- Prefer simplicity, minimal changes, explicit assumptions, and verifiable outcomes.
- Resolve overlapping skill instructions according to the task, without duplicating workflows.

If a skill is unavailable in a session, report that limitation rather than claiming it was used.

## 4. Dictionary and Data Protection

- Treat `assets/dict.db`, `assets/tr_en.db`, and other existing data assets as valuable project data.
- Do not delete, reset, regenerate, overwrite, or migrate production dictionary databases without explicit approval.
- Preserve existing dictionary entries, translations, examples, idioms, phrase matching, and grammatical information.
- Before changing matching or lookup logic, inspect relevant code and tests.
- Prefer reproducible data transformations and validation.
- Report expected changes in record counts and data structures.
- Never invent dictionary data or silently replace linguistic content.

## 5. Offline-First Architecture

- Preserve core offline functionality.
- Do not introduce mandatory network dependencies into existing offline features.
- Keep optional online services optional.
- Preserve local reading progress, vocabulary state, and user settings.
- Avoid unnecessary downloads, storage duplication, and memory consumption.

## 6. Flutter UI and Localization

- Follow the existing Flutter architecture and visual language.
- Preserve existing themes, typography, spacing, and component conventions unless redesign is explicitly requested.
- Support relevant desktop and mobile layouts.
- Maintain Turkish and English localization.
- Follow the existing `L('Türkçe', 'English')` convention.
- Check accessibility, contrast, text overflow, and touch-target usability.
- Do not change unrelated screens during a focused UI task.

## 7. Testing and Verification

For relevant changes:

1. Identify existing tests and expected behavior.
2. Add regression tests when practical.
3. Run focused tests.
4. Run `flutter analyze` and relevant `flutter test` commands when supported.
5. Check whether changes affect localization, offline behavior, or other platforms.
6. Report tests that could not run and explain why.

For book importing, grammar recognition, and dictionary behavior, inspect their dedicated tests.

Do not regenerate large datasets merely to run unrelated tests.

## 8. Git and Release Safety

- Prefer feature branches and pull requests.
- Never force-push, reset shared history, or delete branches without explicit approval.
- Do not commit secrets, API keys, credentials, or private user data.
- Do not merge pull requests or trigger production releases without explicit approval.
- Preserve the existing CI workflows and release-note conventions.
- Respect the project's GPL-3.0 source-code licensing and third-party data licenses.

## 9. Communication

- Communicate with the project owner in Turkish.
- Explain technical concepts clearly without assuming advanced programming knowledge.
- Before substantial changes, provide a concise plan and identify risks.
- After changes, summarize modified files, verification results, and unresolved issues.
- Ask for approval before destructive, irreversible, or production-affecting operations.

## 10. Definition of Done

A task is complete only when:

- The requested behavior is implemented.
- Relevant existing functionality remains intact.
- Available verification has been performed.
- Data integrity and offline requirements are respected.
- Remaining risks and unverified behavior are clearly disclosed.
