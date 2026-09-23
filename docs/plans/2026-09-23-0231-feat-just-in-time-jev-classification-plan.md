---
title: Just-in-time Jev classification in Zevra - Plan
type: feat
date: 2026-09-23
topic: just-in-time-jev-classification
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-brainstorm
execution: code
---

# Just-in-time Jev classification in Zevra - Plan

## Goal Capsule

- **Objective:** A person browsing in Arc can see a timely, correctable suggestion about which eligible pages merit follow-up, without starting a classification run.
- **Means:** Add Jev classification to the standalone native Zevra app.
- **Product authority:** The user chose just-in-time classification over manual or daily classification. The trigger and labels below are proposed defaults for this native feature; the existing collector and original v0 specification remain separate.
- **Open blockers:** None. The proposed defaults can be revised before implementation.

---

## Product Contract

### Summary

Zevra will classify a public Arc page once it has accumulated 10 seconds of active attention and enough page evidence is available. It will show a provisional follow-up suggestion beside the saved page. Leaving or closing the page will update attention time, without automatically causing another Jev call.

### Problem Frame

The downloadable macOS app records URLs, titles, and active time but makes no classification. The separate Bun collector already classifies enriched pages during five-minute sweeps, and its history does not enter the native app. Waiting for a daily run or for a tab to close would delay a result that could be available while the page is still open; many Arc tabs remain open long after the reading session.

### Key Decisions

- **Trigger after attention accrues.** The native app initiates classification at the threshold in R3, independent of tab closure. Governs R3, R4. (session-settled: user-directed — chosen over manual and daily classification: the user wants a timely result while browsing.) The 10-second trigger is a proposed default.
- **Use Jev for a bounded page judgment.** The first version suggests a follow-up action from eligible page evidence; it does not claim to know the user's goals or whether the page was fully read. Governs R5, R6.
- **Keep the result advisory.** No model output hides, deletes, or exports a saved page. Governs R6, R9.
- **Keep native setup standalone.** Classification belongs to native observations and does not require the extension or Bun collector. Governs R1, R11.

### Requirements

**Control and eligibility**

- R1. Jev classification has a separate, explicit opt-in from capture and remains off on a new installation or when no classification mode is selected.
- R2. Zevra applies its saved domain and sensitive-URL exclusions before fetching page evidence or sending anything to Jev; an excluded page gets no classification attempt.
- R3. An eligible normalized page qualifies after 10 cumulative seconds of active Arc attention across visits; background, idle, and closed-tab time never advances this threshold.
- R4. On first qualification, Zevra starts classification in the background as soon as a public page excerpt is available; the request never blocks capture or the app's saved-materials view.

**Judgment and presentation**

- R5. Jev receives only the eligible page's title, domain, and a bounded public excerpt, and returns a suggested follow-up: **Read deeper**, **Keep as reference**, or **No obvious follow-up**. These labels describe potential use, not proof of personal relevance or reading completion.
- R6. Zevra shows the suggestion as provisional, identifies Jev as its source, and displays **Needs review** when Jev's Choice confidence is below 0.6; it does not invent a model explanation.
- R7. If a public excerpt cannot be obtained, Zevra leaves the page unclassified with a visible evidence status rather than asking Jev to guess from the title alone.
- R8. A page receives one Jev classification for unchanged title and excerpt, even if the user switches tabs, revisits the page, or closes it; a material change to that evidence may trigger one new classification.
- R9. The user can correct a suggestion, and that correction remains authoritative across later visits and model retries until the user changes it.

**Failure and data boundaries**

- R10. Missing credentials, offline status, or a provider error leaves the observation intact and shows classification as pending or unavailable; retries are bounded and never create duplicate visible suggestions.
- R11. Turning classification off stops new provider requests while preserving saved observations and human corrections; it does not start a historical backfill when turned on again.
- R12. The first version does not import the Bun collector's database or silently run both classification paths against the same native observation.
- R13. Zevra offers in-app setup and removal of a TypeSafe API key; the key stays in protected local storage and never appears in the repository, diagnostic logs, or synced observations.

### Key Flows

- F1. **Trigger:** An allowed Arc page reaches 10 cumulative active seconds. **Steps:** Zevra obtains eligible public evidence, submits one background Jev judgment, and shows its source and review state. **Outcome:** The suggestion is ready while the page may still be open. Covers R2-R8.
- F2. **Trigger:** The user switches away from or closes the page. **Steps:** Zevra checkpoints active time and keeps any existing classification. **Outcome:** A tab transition does not itself send another request. Covers R3, R8.
- F3. **Trigger:** The user corrects a suggestion. **Steps:** Zevra displays and retains the human choice. **Outcome:** Later model results cannot overwrite it. Covers R9.

### Acceptance Examples

- AE1. **Covers R3, R4, R8.** Given a public page receives 6 active seconds, is backgrounded, then receives 5 more active seconds, classification starts once after the second interval. Repeated focus changes do not send further requests for unchanged content.
- AE2. **Covers R2, R7.** Given an excluded URL or an eligible page whose public content cannot be extracted, no page excerpt is sent to Jev; the eligible page shows why it has no suggestion.
- AE3. **Covers R1, R10, R11.** Given classification is off or credentials are missing, visits continue to save and no provider request is made; enabling classification does not send older history without a separate user action.
- AE4. **Covers R6, R9.** Given a low-confidence response followed by a human correction, Zevra shows the correction after reopening the app and keeps the model suggestion distinguishable from the human decision.

### Success Criteria

- On a healthy connection and a reachable public test page, the suggestion appears during a continuing reading session after the active-attention threshold, without waiting for unfocus or close.
- In a small review of eligible pages the user knows, the suggestions lead to useful follow-up often enough to justify keeping classification enabled; disagreements and uncertain cases are visible rather than hidden. The review establishes a measured quality baseline before automatic actions are considered.

### Scope Boundaries

- Manual and daily digests, notifications, automatic archiving, and automatic deletion are outside this feature.
- Personal goals, interest profiles, correction-based learning, and claims of personalized relevance remain separate product questions.
- Cross-device iCloud distribution and synchronization are outside this feature; the public 0.1.1 preview is local-only.
- The original v0 specification remains unchanged.

### Dependencies / Assumptions

- The 10-second threshold is a proposed product default drawn from the existing collector's enrichment gate, not a measured optimum for native classification.
- The 0.6 review threshold starts from the collector's current rule; it is not a measured accuracy guarantee for the native labels.
- The three follow-up labels are proposed native wording. They do not carry the original collector's `utrwal` meaning of “already read and ready for Raindrop.”
- The app can fetch a public excerpt without browser cookies for some eligible pages. Login-only pages, paywalls, and client-rendered content may remain unclassified.
- An existing TypeSafe API key on this machine is not proof that the native app may use it. The app must provide its own explicit credential setup without exposing the key in logs or the repository.

### Sources / Research

- `macos/App/AppModel.swift`, `macos/Sources/AttentionCore/Observation.swift`, and `docs/macos-prototype.md`: native capture, data, and app boundary.
- `src/enrich.ts`, `src/jev.ts`, `src/store.ts`, and `README.md`: collector enrichment, existing Jev categories and fallback, and documented quality limits.
- `docs/specs/attention-log-v0.md`: original collector goal and 10-second enrichment gate; this proposal does not edit that specification.
- TypeSafe's [Introduction](https://docs.typesafe.ai/introduction) and [Primitives](https://docs.typesafe.ai/primitives): bounded typed judgments and the absence of generated prose explanations.
