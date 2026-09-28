# Navigation and readable controls

Status: prepared for Zevra 0.3.1 (5), following the 0.3.0 release. Publication and installation are recorded separately in `docs/verification.md`.

## Content destinations

| Previous name | New name         | What belongs here                                                           |
| ------------- | ---------------- | --------------------------------------------------------------------------- |
| Library       | Saved materials  | Imported notes/bookmarks and browsing pages the user has rated.             |
| Visits        | Browsing history | Automatically recorded Arc visits, active time and optional AI suggestions. |

A rated browsing page is saved in the same library, even if its rating is later cleared. The Saved materials label covers both imported entries and these saved pages. Each destination explains its source in one sentence. Import is available directly in Saved materials, with separate choices for a folder/export and notes filtered by an Obsidian Base. Both retain the existing review-before-save flow.

## Settings navigation

The native sidebar groups content separately from four settings destinations:

- **General:** launch at login and storage information.
- **Capture & privacy:** capture switch, Accessibility permission and site exclusions.
- **AI suggestions:** TypeSafe credentials, browsing suggestions, personal evaluation and an explanation of optional OpenAI import analysis.
- **Interests & goals:** current goals, selected interests and rated examples. Suggested topics are in an expandable section.

Capture status remains visible in the sidebar, with text and an icon. Capture, classification and personal evaluation retain their independent switches and existing prerequisites. No provider, collection-scope or persistence behavior changes are part of this revision.

## Color and readability

- Green stays in the logo. Interactive labels use neutral colors; the native sidebar supplies selection and keyboard behavior.
- Statuses use words and symbols rather than a green/orange distinction. Selected navigation has a filled background and heavier text, plus the native selected accessibility state.
- Secondary text is opaque and appearance-aware: white level 0.34 in light appearance and 0.76 in dark appearance. Calculated contrast is 7.26:1 against white and 8.26:1 against `#282828`, respectively. These are reference color pairs, not a claim that every rendered control has been audited.
- Search prompts and sidebar section headings use the same readable secondary color. Settings explanations use callout-sized text. Inactive controls keep native disabled styling.
- A sample of the old screenshot's green text was approximately 2.2:1 against white. This screenshot measurement is indicative, not a replacement for inspecting resolved native colors.

The design target follows the [W3C contrast criterion](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) and [use-of-color criterion](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html): ordinary text should have at least 4.5:1 contrast, and color should not be the only way to convey meaning.

## Window material

The main window uses a native behind-window blur with the semantic `underWindowBackground` material and a 35% window-background overlay. Text and controls remain opaque. The effect follows window activation and system appearance. Reduce Transparency or increased contrast requests an opaque surface; native sidebar and titlebar materials retain their system behavior.

This uses [AppKit's window material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground), rather than changing whole-window opacity. macOS 15 and newer also clear SwiftUI's window container background; macOS 14 uses the AppKit window configuration. The deployment target remains macOS 14.

The 0.3.1 synthetic preview was inspected in light and dark appearances at 860 points wide. High-contrast NSAppearance was also inspected; this does not verify a live system Reduce Transparency toggle. Runtime behavior on macOS 14 and Intel remains unverified.

## Verification

Manual checks on an isolated, synthetic-data preview on 2026-09-28:

- Sidebar destinations and cross-links opened their intended content.
- Up/Down keys changed the selected sidebar destination and its content.
- Light and dark appearances were inspected, including a window reduced to 860 points wide.
- Imported-material search showed the no-results state; Clear filters restored all four synthetic materials.
- Import opened the review sheet directly from Saved materials. Cancel returned to the unchanged four-material list.
- The final larger settings descriptions and darker sidebar headings were inspected in light appearance.

The preview uses `ZEVRA_IMPORT_PREVIEW` and `com.jamatyka.Zevra.NavigationPreview`, with capture disabled and in-memory synthetic data. Its appearance menu is compiled out of normal builds. No live provider request or user-data import was part of these UI checks.

On 2026-09-29, the full native gate passed again on the final source: 43 tests, strict formatting and the normal Xcode build. The preview also opened successfully. Light and dark high-contrast NSAppearance variants were inspected on the imported-material screen at 860 points wide. This checks app appearance, not every system accessibility preference. Final-build verification is recorded in `docs/verification.md`.

Not yet verified: a full VoiceOver workflow and specific color-vision-deficiency simulations. This revision is not a full accessibility-conformance claim.
