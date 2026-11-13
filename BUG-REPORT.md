# J.A.R.V.I.S. (PrivateAgent) v1.1.0 — Bug Report

**Repo:** https://github.com/AbuZar-Ansarii/Jarvis (branch `main`, v1.1.0+2)
**Audited:** 2026-11-12, from a fresh clone at `~/workspace/jarvis-repo/`
**Scope:** code review only — no code was changed.
**User setup this report is anchored to:** Tecno SPARK 20, Android 13, 8 GB RAM; v1.1.0 APK
sideloaded from GitHub Releases; accessibility service "PrivateAgent Screen Control"
(Android 13 restricted-settings block applies); AI provider OpenRouter, model
`nvidia/nemotron-3-ultra-550b-a55b:free`, free-tier key (50 req/day, 20/min).

## Confirmed user facts (from the user, not inferred)

1. The user **already pasted the edited Roman Urdu SOUL.md into the app** (Section 3,
   "Language — Roman Urdu") — and the AI **still replies in English**. "SOUL.md not
   applied by the user" is therefore ruled out.
2. **Screen summarize does not work** (overlay "Summarize Screen" / "summarize this
   screen" command produces no usable summary).
3. The AI itself **does connect** (provider + key work; replies arrive, in English).

---

## Summary — most likely culprits for this user's setup

**Roman Urdu (symptom 1): BUG-1 is the prime suspect, BUG-2 the second.**
The app *does* send SOUL.md to the model (the plumbing is wired — see "Verified
correct"), but `HermesEvolutionService.init()` **deletes the user's edited SOUL.md on
every cold start** and replaces it with the built-in default, because its "guard"
condition matches the default template's own sentence *"Never refer to Tony Stark."*
The user's edited file contains that exact sentence, so the edit can never survive a
restart. A second wipe path (`evolveContext()`, auto-triggered whenever a memory fact
is saved) regenerates SOUL.md from a hardcoded template with no language section.
On top of that, USER.md — sent in the *same* system prompt — says
"Primary Language: English", contradicting SOUL.md even if it survived.

**Screen summarize (symptom 2): BUG-5 is the prime suspect, BUG-6 the second.**
`summarizeForegroundScreen()` never checks whether the accessibility service is on;
when it is off, the native side throws `SERVICE_OFF`, which is swallowed into a
generic "Unable to analyze…" message with no hint that the service is off. This
user's service was blocked/off (Android 13 restricted settings for sideloaded apps).
Even with the service on, only the **first 40 text nodes** (browser chrome first) are
sent to the AI, so the article body is usually discarded.

**Provider config (latent, same user): BUG-8.** Re-tapping the OpenRouter pill silently
resets the custom model name to the paid `openai/gpt-4o-mini` (402 on a free key).

---

## BUG-1 — CRITICAL — `init()` wipes any edited SOUL.md on every app start

- **File:** `lib/services/hermes_evolution_service.dart:107-110`
- **Code:**
  ```dart
  if (_soulMd.contains('Tony Stark') || !_soulMd.contains('Abuzar') ||
      _soulMd.contains('or "Abuzar" when addressing by name')) {
    _soulMd = defaultSoulMd;
    await prefs.setString(_soulKey, _soulMd);
  }
  ```
  Called from `init()`, which runs on every cold start (`lib/main.dart` calls
  `HermesEvolutionService.instance.init()`).
- **What is wrong:** the guard is self-defeating. The built-in `defaultSoulMd`
  itself contains the sentence *"Never refer to Tony Stark."*
  (`defaultSoulMd`, lines 42-59), so `_soulMd.contains('Tony Stark')` is true for
  the default text **and for any user-edited SOUL.md that keeps that sentence** —
  including the Roman Urdu version the user pasted (its line 5 reads
  "…Never refer to Tony Stark."). Any edit is therefore replaced with
  `defaultSoulMd` and persisted, on every restart. The edit survives only until
  the app process is killed.
- **User-visible symptom:** user pastes the Roman Urdu SOUL.md into the app, it
  appears saved, but after the next app restart the AI answers in English again
  (and the editor shows the default text). Exactly the reported symptom 1.
- **Suggested fix:** remove the `'Tony Stark'` substring test (or match the
  *offending* pattern precisely, e.g. a line claiming Tony Stark *is* the
  creator, not a line saying *never refer to* him). The intent — "Abuzar must be
  the recorded creator" — is already covered by the `!contains('Abuzar')` check.

## BUG-2 — CRITICAL — `evolveContext()` regenerates SOUL.md from a hardcoded template, discarding all user edits

- **File:** `lib/services/hermes_evolution_service.dart:231-256`
  (`final evolvedSoul = '''...'''`, assigned at line 252)
- **What is wrong:** the "evolved" SOUL.md is a fixed template with no language
  section, no creator line, and no trace of the user's edits. It is triggered
  **automatically** on every memory-fact save/delete
  (`lib/services/conversational_memory_service.dart:182,193` —
  `addFact()`/`deleteFact()` call `evolveContext().catchError((_) {})`), plus
  manually from the settings screen (`lib/screens/settings/jarvis_settings_screen.dart:2664`)
  and the voice command "self evolve" (`lib/services/jarvis_service.dart:934`).
  Worse, the evolved template contains no "Abuzar", so the *next* `init()` run
  resets it again via the `!contains('Abuzar')` branch of BUG-1. Two wipe paths
  chained together.
- **User-visible symptom:** the Roman Urdu SOUL.md disappears even without an app
  restart, as soon as the app saves a memory fact (which happens during normal
  conversation).
- **Suggested fix:** evolve by *patching* the existing `_soulMd` (or preserve a
  user-editable section verbatim) instead of overwriting it; at minimum carry
  over any `## 3. Language` section and the creator line into the evolved text,
  and do not auto-evolve on every fact save.

## BUG-3 — MAJOR — USER.md contradicts SOUL.md on language in the same system prompt

- **File:** `lib/services/hermes_evolution_service.dart:64` (default USER.md:
  `**Primary Language**: English (UK/US).`) and `:192` (evolved USER.md:
  `**Primary Language**: English.`)
- **What is wrong:** `buildHermesSystemContext()` (`:269-281`) concatenates SOUL.md,
  USER.md and AGENT.md into one system prompt. SOUL.md says "reply in Roman Urdu";
  USER.md in the same prompt says "Primary Language: English". The model receives
  contradictory instructions and typically defaults to English.
- **User-visible symptom:** even if the SOUL.md edit survived, replies stay English
  (or flip unpredictably between English and Roman Urdu).
- **Suggested fix:** make USER.md's language line follow the SOUL.md language section
  (single source of truth), or drop the hardcoded "Primary Language: English" from
  both USER.md templates.

## BUG-4 — MAJOR — tool/summary prompts bypass SOUL.md and hardcode English

- **File:** `lib/services/ai_service.dart:1224-1253` (`summarizeScreenContent`,
  line 1231: *"Write clean, natural English for voice synthesis…"*),
  `ai_service.dart:1181-1220` (`completeMultimodal` / Jarvis Eye, line 1193:
  *"Provide clean spoken English ready for voice synthesis"*), and
  `ai_service.dart:1136-1180` (`answerWithToolResult`).
- **What is wrong:** these methods build their **own** system prompts with no Hermes
  context (`buildHermesSystemContext()` is never called), so SOUL.md — including
  the Roman Urdu rule — is never sent for these calls. `summarizeScreenContent`
  and `completeMultimodal` additionally *explicitly demand English*;
  `answerWithToolResult` does not demand English in words, but still never sees
  the language rule.
- **User-visible symptom:** screen summaries and tool-based answers (weather/news/
  etc.) always come back in English even if chat mode were fixed to Roman Urdu.
- **Suggested fix:** include the Hermes context (or at least the language rule) in
  these prompts, and replace the hardcoded "English" with the user's configured
  language.

## BUG-5 — CRITICAL (for this user) — screen summarize fails silently when the accessibility service is off

- **Files:**
  - `lib/services/screen_automation_service.dart:56-66` — `dumpScreen()` has **no
    try/catch**; a `PlatformException` propagates.
  - `android/app/src/main/kotlin/com/privateagent/private_agent/MainActivity.kt:824-833`
    — `"dumpScreen"` returns `result.error("SERVICE_OFF", "PrivateAgent
    accessibility service is not enabled", null)` when the service is not bound.
  - `lib/services/jarvis_tools_service.dart:534-562` — `summarizeForegroundScreen()`
    wraps everything in one catch-all returning the generic
    *"Unable to analyze the foreground screen article at this moment, sir."*
- **What is wrong:** there is no pre-check (`isServiceEnabled()` exists but is never
  called on this path) and no distinction between "service off", "empty screen"
  and "AI failed". The user gets the same vague spoken failure for all three and
  is never told to enable "PrivateAgent Screen Control". This user's service was
  blocked by Android 13 restricted settings (sideloaded app), i.e. exactly the
  state that produces this failure.
- **User-visible symptom:** "Summarize Screen" says it is analyzing, then reports
  it cannot analyze the screen — no actionable guidance. Exactly the reported
  symptom 2.
- **Suggested fix:** call `isServiceEnabled()` first in `summarizeForegroundScreen()`;
  if off, return a specific message ("Accessibility service is off — enable
  PrivateAgent Screen Control in Settings → Accessibility") and offer to open
  accessibility settings; keep the three failure modes distinct.

## BUG-6 — MAJOR — summarize sends only the first 40 text nodes (browser chrome, not the article)

- **File:** `lib/services/jarvis_tools_service.dart:537-548`
  ```dart
  final texts = nodes.map((n) => n.text.isNotEmpty ? n.text : n.contentDescription)
      .map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList();
  ...
  final joinedText = texts.take(40).join('\n');
  ```
- **What is wrong:** nodes arrive in accessibility-tree order, so on a Chrome/article
  page the first ~40 are browser chrome (tabs, URL bar, toolbar, menus). The article
  body comes later and is discarded. There is no filtering of the foreground app's
  own chrome, no ranking by text length, and no scrolling to collect more content.
  The LLM therefore summarises the browser UI (or gets almost nothing usable).
- **User-visible symptom:** summaries are about the wrong content, empty, or the
  "could not detect any readable text" fallback — even with the service on.
- **Suggested fix:** drop nodes belonging to browser chrome (short UI labels), rank
  remaining nodes by text length, take the longest blocks (e.g. top ~40 by length,
  capped by characters not node count), and/or scroll-and-collect before summarizing.

## BUG-7 — MINOR — summarize path has further empty-screen traps

- **Files:** `android/.../AgentAccessibilityService.kt` (`dumpScreen()`, `traverse()`),
  `lib/services/jarvis_tools_service.dart:540-543`
- **What is wrong:** (a) if `rootInActiveWindow` is null (screen locked, transient
  window change) `dumpScreen()` returns an empty list → "could not detect any
  readable text"; (b) when the user triggers summarize from inside the Jarvis app
  itself, its own package nodes are deliberately skipped, so the dump is empty;
  (c) `traverse()` only keeps nodes that are `isVisibleToUser && onScreen &&
  (interactive || hasLabel)` — WebView article paragraphs are usually covered, but
  text in zero-size/off-screen nodes is dropped.
- **User-visible symptom:** intermittent "no readable text" failures depending on
  which app/screen is in front.
- **Suggested fix:** retry the dump once after a short delay when empty; if still
  empty, say *which* screen was seen (package name) so the failure is diagnosable.

## BUG-8 — CRITICAL (for this user) — tapping a provider pill resets the custom model name

- **Files:**
  - `lib/services/settings_service.dart:82-89` — `setProvider()` unconditionally
    overwrites `ai_base_url` **and** `ai_model` with the preset whenever it is called.
  - `lib/screens/settings/settings_screen.dart:349-359` — provider pills call
    `_settings.setProvider(entry.key)` on **every** tap, including re-tapping the
    already-selected provider. (`_onSettingsChanged`, lines 96-101, then syncs the
    text fields to the reset values.)
  - Same pattern in onboarding: `lib/screens/onboarding/onboarding_screen.dart:353-354`.
- **What is wrong:** the user types the custom model `nvidia/nemotron-3-ultra-550b-a55b:free`
  into the Model field, but any later tap on the OpenRouter pill (easy to do while
  confirming the selection) silently reverts the model to the preset
  `openai/gpt-4o-mini` — and the screen shows the reverted value as if that was
  intended. There is no warning and no undo.
- **User-visible symptom:** AI suddenly stops working / returns 402 errors after the
  user "only tapped OpenRouter to check it was selected" — the exact setup this
  user has (OpenRouter + custom free model).
- **Suggested fix:** only apply the preset base URL/model when the provider actually
  *changes*, and never overwrite a non-empty custom model (or ask before resetting).

## BUG-9 — MAJOR — default OpenRouter model is a paid model (402 on a free key)

- **File:** `lib/services/settings_service.dart:64-67` — OpenRouter preset
  `model: 'openai/gpt-4o-mini'` (paid model, not `:free`).
- **What is wrong:** on the user's free-tier OpenRouter key every call with this
  model returns **402 Payment Required**. Combined with BUG-8 (which can silently
  restore this default), the app can break with no in-app explanation. The 402
  body is truncated to 300 chars and surfaced only as `AI request failed: HTTP 402: …`
  (`lib/services/task_executor.dart:250-254`).
- **User-visible symptom:** "AI request failed: HTTP 402…" / no reply, even though
  the key is valid — because the *model* is not free.
- **Suggested fix:** default the OpenRouter preset to a `:free` model, and surface
  401/402/429 distinctly ("wrong key" / "model is not free — pick a :free model" /
  "daily limit reached") instead of a generic failure line.

## BUG-10 — MAJOR — no way to test the provider config in-app; config errors are indistinguishable

- **Files:** `lib/screens/settings/settings_screen.dart` (no test-connection action
  anywhere — grep for "test" finds only unrelated text); `lib/services/ai_service.dart:812-819,1266-1273`
  (`'No API key configured. Open Settings and add one first.'`,
  `'No model name configured.'`).
- **What is wrong:** (a) there is no "Test connection" button, so the user can only
  discover a bad key/model/base-URL by sending a message and reading a failure;
  (b) the string users report — *"no AI provider is configured"* — **does not exist
  anywhere in the code**; the real errors are the ones above plus the generic
  `AI request failed: …` line in Chat mode (`task_executor.dart:250-261`), which
  hides whether the cause is a missing key, a wrong model, a 402, a 429, or a
  network failure.
- **User-visible symptom:** "app doesn't work" with no diagnosable cause; the
  reported "no AI provider is configured" error is a paraphrase, not a literal
  app message — which itself shows the app never tells the user what is actually
  wrong.
- **Suggested fix:** add a "Test connection" button in AI settings that calls the
  provider and reports OK / bad key (401) / model not free (402) / rate-limited
  (429) / unreachable, in plain language.

## BUG-11 — MINOR (latent) — default 2048 max tokens is too low for reasoning models

- **Files:** `lib/services/settings_service.dart` (`maxTokens` default 2048);
  `lib/services/ai_service.dart` (finish_reason `length` handling — the code itself
  notes reasoning models burn the budget on hidden thinking before replying).
- **What is wrong:** the user's model, Nemotron 3 Ultra, is a **reasoning** model: it
  spends completion tokens on hidden reasoning, so with a 2048-token cap it can
  return empty content with `finish_reason == 'length'`. The code handles this with
  a clear error message (good), but the default still invites the failure.
- **User-visible symptom:** intermittent empty replies / "Model used the whole token
  budget before replying… Raise Max tokens in Settings."
- **Suggested fix:** raise the default `maxTokens` (e.g. 4096) or set a higher default
  for known reasoning models.

## BUG-12 — MINOR — Ollama base URL without `/v1` produces 404

- **File:** `lib/services/ai_service.dart` (`_postChatCompletion` / `chatStream`:
  `Uri.parse('$base/chat/completions')` after stripping trailing slashes).
- **What is wrong:** the URL is built by appending `/chat/completions` to whatever
  base URL is stored. The preset is correct (`http://127.0.0.1:11434/v1`), but if
  the user types `http://127.0.0.1:11434` (no `/v1`), requests go to
  `…/chat/completions` and Ollama answers 404. No normalisation or helpful error.
- **User-visible symptom:** local Ollama "doesn't work" with a 404, although Ollama
  is running.
- **Suggested fix:** if the base URL host is localhost/127.0.0.1 and the path does not
  end in `/v1`, append `/v1` (or warn in settings).

## BUG-13 — MINOR (security, not functional) — API keys stored in plaintext

- **File:** `lib/services/settings_service.dart` — `setApiKey()` writes to
  `SharedPreferences` (`ai_api_key`), readable by any app/process with access to
  the app's prefs.
- **Suggested fix:** store API keys in `flutter_secure_storage` (Android Keystore)
  instead of SharedPreferences.

---

## Verified correct — checked, no bug found (do not "fix" these)

- **SOUL.md *is* sent to the model when it survives.** `buildHermesSystemContext()`
  (`hermes_evolution_service.dart:269-281`) is included in `buildChatSystemPrompt()`
  and `buildSystemPrompt()` (`ai_service.dart`), used by `chat()`, `chatStream()`,
  `complete()` and `interpretJarvisCommand()`. The failure is the wipe (BUG-1/2),
  not the plumbing.
- **SOUL.md editing/saving works.** The settings editor saves via `updateSoul()` →
  `_persist()` (SharedPreferences + `hermes/soul.md` on disk). The user's paste *was*
  saved — it is deleted afterwards by BUG-1/2.
- **Accessibility service registration is correct.** Manifest declares
  `AgentAccessibilityService` with `BIND_ACCESSIBILITY_SERVICE` and the
  `@xml/accessibility_service_config` metadata; the config sets
  `canRetrieveWindowContent="true"`, `canPerformGestures="true"`,
  `canTakeScreenshot="true"` and `flagRetrieveInteractiveWindows|flagReportViewIds|
  flagIncludeNotImportantViews`. No config bug.
- **Summarize flow is wired end-to-end.** Overlay button → `_sendCommand({'command':
  'summarize_screen'})` (`overlay_app.dart:360,429`) → `main.dart` case
  `'summarize_screen'` → `processCommand('summarize this screen article')` →
  `jarvis_service.dart` 3e-1 branch (matches `'summarize this screen'`) →
  `summarizeForegroundScreen()` → summary shared back via `shareData`
  (`type: 'screen_summary'`) → overlay card expands (`overlay_app.dart:93-100`).
  The breaks are BUG-5/6/7, not the routing.
- **Provider request plumbing is correct.** OpenAI-compatible `POST {base}/chat/completions`
  with `Bearer` auth, OpenRouter `HTTP-Referer`/`X-Title` headers, `stream: true/false`
  handling, SSE `data:` parsing, non-200 bodies surfaced with status code, 45 s/60 s
  timeouts, and a streaming→non-streaming fallback in `chatStream()`. Trailing-slash
  stripping on the base URL is present.
- **Gemini preset is valid.** Base URL `https://generativelanguage.googleapis.com/v1beta/openai`
  is Google's OpenAI-compatible endpoint; model `gemini-2.0-flash` is valid there.
- **Wake word is implemented** (not a stub): continuous `SpeechRecognizer` with
  restart-on-error (`MainActivity.kt`), `containsWakeWord` hypothesis preference,
  `extractWakeCommand()` with phonetic variants (`jarvis/javis/jervis/travis/…`),
  950 ms silence debounce and wake-only handling (`jarvis_service.dart:321+, 575-670`).
  It depends on Google Speech Services being present and online, and on microphone
  permission — on a Tecno without Google Speech Services, or offline, it will fail
  with "MICROPHONE UNAVAILABLE" rather than silently ignoring "Hey Jarvis".
- **TTS offline fallback exists.** `VoiceService.speak()` tries Edge-TTS (online) then
  falls back to local `flutter_tts` (`voice_service.dart:288-305`). Edge-TTS being
  online-only is therefore not a total voice failure.
- **Chat-mode error display works.** `TaskExecutor.sendChatMessage()` streams tokens
  into the transcript, falls back to a non-streaming call on empty reply, and logs
  `ChatMessage.error('AI request failed: …')` on `AiException`
  (`task_executor.dart:207-261`).

## Android 13 note (environmental, not a code bug)

On Android 13, sideloaded apps get **restricted settings**: the Accessibility
("PrivateAgent Screen Control"), overlay and notification-listener toggles are greyed
out until the user opens the app's App info → ⋮ menu → **"Allow restricted settings"**.
The app does not detect or explain this state anywhere (permissions screen does not
mention it). Worth adding a guided hint, but it is an OS behaviour, not an app bug.
