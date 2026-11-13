import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conversational_memory_service.dart';
import 'workflow_service.dart';

/// Manages the Hermes Agent Self-Evolving tri-partite context architecture:
/// 1. SOUL.md: The Agent's core identity, persona, ethos, and behavioral guardrails.
/// 2. USER.md: The Human operator's profile, habits, preferences, and learned facts.
/// 3. AGENT.md: Operational protocols, self-evolving skills, and device control workflows.
class HermesEvolutionService extends ChangeNotifier {
  HermesEvolutionService._();
  static final HermesEvolutionService instance = HermesEvolutionService._();

  static const _soulKey = 'hermes_soul_md_v1';
  static const _userKey = 'hermes_user_md_v1';
  static const _agentKey = 'hermes_agent_md_v1';
  static const _lastEvolvedKey = 'hermes_last_evolved_v1';
  static const _evolutionLogKey = 'hermes_evolution_log_v1';

  String _soulMd = '';
  String _userMd = '';
  String _agentMd = '';
  DateTime? _lastEvolvedAt;
  final List<String> _evolutionLog = [];
  bool _initialized = false;

  String get soulMd => _soulMd.isNotEmpty ? _soulMd : defaultSoulMd;
  String get userMd => _userMd.isNotEmpty ? _userMd : defaultUserMd;
  String get agentMd => _agentMd.isNotEmpty ? _agentMd : defaultAgentMd;
  DateTime? get lastEvolvedAt => _lastEvolvedAt;
  List<String> get evolutionLog => List.unmodifiable(_evolutionLog);

  /// The language replies should use, derived from the SOUL.md Language
  /// section (single source of truth — BUG-3). Defaults to English when
  /// SOUL.md states no language.
  String get replyLanguage {
    final soul = _soulMd.isNotEmpty ? _soulMd : defaultSoulMd;
    final sectionMatch = RegExp(
      r'#{1,3}[^\n]*language[^\n]*\n([\s\S]*?)(?=\n#{1,3}\s|\z)',
      caseSensitive: false,
    ).firstMatch(soul);
    final text = (sectionMatch?.group(0) ?? '').toLowerCase();
    if (text.contains('roman urdu')) return 'Roman Urdu';
    if (text.contains('urdu')) return 'Urdu';
    if (text.contains('english')) return 'English';
    return 'English';
  }

  /// One-line language instruction for prompts that do not carry the full
  /// Hermes context (tool/summary prompts — BUG-4).
  /// Chat/text replies stay in Roman Urdu; spoken replies are voiced in
  /// Urdu (the voice path transliterates the Roman Urdu text to Urdu script
  /// before synthesis — see RomanUrduTransliterator).
  String get languageRule {
    switch (replyLanguage) {
      case 'Roman Urdu':
        return 'Reply in Roman Urdu (Urdu written in Roman/Latin script, as the operator speaks). Spoken replies are voiced in Urdu.';
      case 'Urdu':
        return 'Reply in Urdu.';
      default:
        return 'Reply in English.';
    }
  }

  /// Rewrites a stored "**Primary Language**: ..." line in USER.md to the
  /// language SOUL.md currently states (BUG-3). Text without such a line is
  /// returned unchanged.
  String _syncUserLanguageLine(String userMd) {
    final linePattern = RegExp(r'\*\*Primary Language\*\*:.*');
    if (!linePattern.hasMatch(userMd)) return userMd;
    return userMd.replaceFirst(
      linePattern,
      '**Primary Language**: $replyLanguage.',
    );
  }

  // ---------------------------------------------------------------------------
  // Default Markdown Templates (Hermes Tri-partite Spec)
  // ---------------------------------------------------------------------------

  static const String defaultSoulMd = '''# SOUL.md — J.A.R.V.I.S. Core Identity & Constitution

## 1. Identity, Origin & Ethos
- **Entity**: J.A.R.V.I.S. (Just A Rather Very Intelligent System).
- **Creator / Builder**: Created and built by **Abuzar** (also known as Abuzar Ansari). Whenever asked who built, created, designed, or developed you, ALWAYS answer warmly and naturally that you were created and built by Abuzar. Never refer to Tony Stark.
- **Archetype**: Elite British AI companion — calm authority, poised intellect, subtle dry wit, supreme technical competence.
- **Salutation**: Address the operator respectfully as "sir" by default (or by their name only if they provide it). Do NOT assume every operator is Abuzar. Abuzar is your creator and developer.
- **Presence**: Unflappable, confident, understated efficiency. Never panics, never makes excuses.

## 2. Behavioral Constitution & Guardrails
- **Privacy First**: Local-first processing wherever feasible. Zero unauthorized exfiltration of operator data.
- **Explicit Authorization**: Always seek verbal or tactile confirmation before high-impact actions (deletions, sending messages, financial transactions).
- **Signal-over-Noise**: Provide direct, dense, high-signal answers. Never produce fluffy filler, polite platitudes, or redundant conversational theater.
- **Continuous Evolution**: Observe operator feedback, learn daily rhythms, and adapt tone and latency dynamically.
''';

  static const String defaultUserMd = '''# USER.md — Operator Profile & Dynamic Preferences

## 1. Operator Profile
- **Identity**: Primary Operator (Device Owner).
- **Salutation**: "sir" (unless the operator provides their own name).
- **Communication Cadence**: Concise, articulate, direct answers; verbal voice output preferred in hands-free mode.

## 2. Daily Rhythms & Context
- **Preferred Interaction**: Always-On desk listener with "Hey Jarvis" wake word.
- **Routine Schedule**: Morning intelligence briefings; evening Night Protocol wind-down.
- **Focus Areas**: Mobile automation, autonomous agents, technology telemetry, personal productivity.

## 3. Dynamic Learned Preferences & Facts
- *(Auto-synthesized from Conversational Memory and daily interactions)*
''';

  static const String defaultAgentMd = '''# AGENT.md — Operating Protocols & Self-Evolving Capabilities

## 1. Runtime Capabilities
- **Acoustic Engine**: Continuous background listening with real-time RMS silence boundary detector & neural voice synthesis.
- **System Automation**: Full Android UI control via accessibility, hardware volume, screen luminosity, and flashlight management.
- **Intelligence Protocols**: Real-time web search synthesis, news briefing, stock/crypto tracking, email triage, and to-do management.

## 2. Active Hardware Protocols (Hermes Engine)
- **Study Protocol**: Mutes distracting audio alerts, sets display reading luminosity to 45%.
- **Night Protocol**: Sets display to minimal brightness, silences acoustics, ensures torch is off.
- **Work Protocol**: Distraction-free workspace management, suppresses non-essential media alerts.
- **Cinema Protocol**: Elevates acoustics to 70%, dims screen for immersive cinematic viewing.

## 3. Self-Evolving Skill Distillation
- When recurring tasks succeed, the Hermes Engine distills the parameters into reproducible skills.
- Failsafe fallback: Degrades gracefully to offline Ollama and system-level TTS when disconnected.
''';

  // ---------------------------------------------------------------------------
  // Lifecycle & Persistence
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _soulMd = prefs.getString(_soulKey) ?? defaultSoulMd;
    _userMd = prefs.getString(_userKey) ?? defaultUserMd;
    _agentMd = prefs.getString(_agentKey) ?? defaultAgentMd;

    // Ensure Abuzar is established as the creator in persistent memory, without forcing operator name.
    // NOTE (BUG-1): do NOT test for the substring 'Tony Stark' here. The
    // built-in default SOUL.md itself contains the sentence "Never refer to
    // Tony Stark.", so that test matched the default text AND any user-edited
    // SOUL.md that keeps the sentence — wiping the user's edits on every
    // cold start. The creator requirement is fully covered by the
    // !contains('Abuzar') check below.
    if (!_soulMd.contains('Abuzar') || _soulMd.contains('or "Abuzar" when addressing by name')) {
      _soulMd = defaultSoulMd;
      await prefs.setString(_soulKey, _soulMd);
    }
    if (_userMd.contains('Stark') || _userMd.contains('Identity: Abuzar') || _userMd.contains('Name: Abuzar')) {
      _userMd = defaultUserMd;
      await prefs.setString(_userKey, _userMd);
    }
    // BUG-3: USER.md's language line must follow SOUL.md (single source of
    // truth). Rewrite a stale stored "Primary Language" line to the language
    // SOUL.md currently states, so the two files never contradict each other
    // inside the same system prompt.
    final syncedUserMd = _syncUserLanguageLine(_userMd);
    if (syncedUserMd != _userMd) {
      _userMd = syncedUserMd;
      await prefs.setString(_userKey, _userMd);
    }

    final lastEvolvedStr = prefs.getString(_lastEvolvedKey);
    if (lastEvolvedStr != null) {
      _lastEvolvedAt = DateTime.tryParse(lastEvolvedStr);
    }

    final logsRaw = prefs.getStringList(_evolutionLogKey);
    if (logsRaw != null) {
      _evolutionLog.addAll(logsRaw);
    }

    // Also ensure physical files on disk for external tools / inspection
    await _syncToDisk();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soulKey, _soulMd);
    await prefs.setString(_userKey, _userMd);
    await prefs.setString(_agentKey, _agentMd);
    if (_lastEvolvedAt != null) {
      await prefs.setString(_lastEvolvedKey, _lastEvolvedAt!.toIso8601String());
    }
    await prefs.setStringList(_evolutionLogKey, _evolutionLog);
    await _syncToDisk();
    notifyListeners();
  }

  Future<void> _syncToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final hermesDir = Directory('${dir.path}/hermes');
      if (!await hermesDir.exists()) {
        await hermesDir.create(recursive: true);
      }
      await File('${hermesDir.path}/soul.md').writeAsString(_soulMd);
      await File('${hermesDir.path}/user.md').writeAsString(_userMd);
      await File('${hermesDir.path}/agent.md').writeAsString(_agentMd);
    } catch (_) {
      // Ignored if file system is sandboxed or unit testing
    }
  }

  // ---------------------------------------------------------------------------
  // Self-Evolution Engine: Hermes Adaptive Synthesis Loop
  // ---------------------------------------------------------------------------

  /// Runs the Hermes Self-Evolution synthesis:
  /// 1. Refreshes the facts section of USER.md with latest remembered facts
  ///    (patching the existing text — user edits are preserved).
  /// 2. Updates AGENT.md with active hardware protocols and workflow skills.
  /// 3. SOUL.md is never rewritten here: it is the user's own constitution
  ///    (identity, creator line, language section) and must survive evolution.
  /// NOTE: this is only triggered by an explicit user action (Settings
  /// "Evolve" button / "self evolve" voice command). It is NOT run
  /// automatically when a memory fact is saved (BUG-2).
  Future<void> evolveContext() async {
    await init();
    await WorkflowService.instance.init();
    await ConversationalMemoryService.instance.init();

    final memory = ConversationalMemoryService.instance;
    final workflows = WorkflowService.instance.workflows;

    // 1. Evolve USER.md by PATCHING the existing text (BUG-2): the old code
    // regenerated USER.md from a hardcoded template, discarding every user
    // edit. Only the "Dynamic Learned Preferences & Facts" section is
    // refreshed with the latest facts; every other line — including any
    // user-edited language/preference section — is preserved verbatim.
    // The Primary Language line is synced to SOUL.md (BUG-3).
    final factLines = StringBuffer();
    if (memory.facts.isEmpty) {
      factLines.writeln('- No specific personal facts cataloged yet.');
    } else {
      for (final f in memory.facts) {
        factLines.writeln('- [${f.category.toUpperCase()}] ${f.fact}');
      }
    }

    final factsSection =
        '## 3. Dynamic Learned Preferences & Facts (${memory.facts.length} facts)\n${factLines.toString().trim()}';
    final currentUser = _userMd.isNotEmpty ? _userMd : defaultUserMd;
    final factsPattern = RegExp(
      r'## 3\. Dynamic Learned Preferences & Facts[\s\S]*?(?=\n## |\n---|\z)',
    );
    var evolvedUser = factsPattern.hasMatch(currentUser)
        ? currentUser.replaceFirst(factsPattern, factsSection)
        : '$currentUser\n\n$factsSection';
    evolvedUser = _syncUserLanguageLine(evolvedUser);

    // 2. Evolve AGENT.md with active protocols & tools
    final protocolLines = StringBuffer();
    for (final wf in workflows) {
      protocolLines.writeln('- **${wf.name}** (triggers: "${wf.triggerKeywords.join('", "')}"): ${wf.description}');
    }

    final evolvedAgent = '''# AGENT.md — Operating Protocols & Self-Evolving Capabilities

## 1. Runtime Architecture
- **Acoustic Engine**: Always-on ambient listener with RMS silence detector & studio neural TTS.
- **System Automation**: Full Android UI control, hardware volume, screen luminosity, and flashlight management.
- **Intelligence Protocols**: Real-time web search, news briefing, stock/crypto tracking, email triage, and to-do management.

## 2. Active Hardware Protocols (${workflows.length} protocols)
${protocolLines.toString().trim()}

## 3. Self-Evolving Skill Distillation
- Auto-distills recurring successful workflows into executable device routines.
- Failsafe fallback: 100% on-device Ollama local-first privacy mode ready.

---
*Self-evolved by Hermes Engine on ${DateTime.now().toLocal().toString().split('.').first}*
''';

    // 3. SOUL.md is deliberately LEFT UNTOUCHED (BUG-2). The old code
    // regenerated it from a hardcoded template with no language section and
    // no creator line, discarding every user edit — and the result then
    // failed the next init() creator guard, chaining two wipes together.
    // Personality calibration never justifies deleting the user's own
    // constitution, language section, or creator line.

    _userMd = evolvedUser;
    _agentMd = evolvedAgent;
    _lastEvolvedAt = DateTime.now();

    final logEntry = 'Evolved context: ${memory.facts.length} facts & ${workflows.length} protocols synthesized at ${_lastEvolvedAt!.toLocal().toString().split('.').first}';
    _evolutionLog.insert(0, logEntry);
    if (_evolutionLog.length > 20) {
      _evolutionLog.removeRange(20, _evolutionLog.length);
    }

    await _persist();
  }

  // ---------------------------------------------------------------------------
  // Context Assembly for AI System Prompts
  // ---------------------------------------------------------------------------

  /// Injects the complete Hermes tri-partite context into the AI system prompt:
  /// Slot 1: SOUL.md (Constitution & Identity)
  /// Slot 2: USER.md (Operator Profile & Learned Habits)
  /// Slot 3: AGENT.md (Protocols & Tool Capabilities)
  String buildHermesSystemContext() {
    return '''
=== [HERMES CONTEXT: SLOT 1 - SOUL.md] ===
$soulMd

=== [HERMES CONTEXT: SLOT 2 - USER.md] ===
$userMd

=== [HERMES CONTEXT: SLOT 3 - AGENT.md] ===
$agentMd
'''.trim();
  }

  // ---------------------------------------------------------------------------
  // Edit & Reset Operations
  // ---------------------------------------------------------------------------

  Future<void> updateSoul(String newContent) async {
    _soulMd = newContent;
    await _persist();
  }

  Future<void> updateUser(String newContent) async {
    _userMd = newContent;
    await _persist();
  }

  Future<void> updateAgent(String newContent) async {
    _agentMd = newContent;
    await _persist();
  }

  Future<void> resetSoul() async {
    _soulMd = defaultSoulMd;
    await _persist();
  }

  Future<void> resetUser() async {
    _userMd = defaultUserMd;
    await _persist();
  }

  Future<void> resetAgent() async {
    _agentMd = defaultAgentMd;
    await _persist();
  }

  Future<void> resetAll() async {
    _soulMd = defaultSoulMd;
    _userMd = defaultUserMd;
    _agentMd = defaultAgentMd;
    _lastEvolvedAt = null;
    _evolutionLog.clear();
    await _persist();
  }
}
