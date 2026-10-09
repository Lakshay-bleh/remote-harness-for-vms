/// Autopilot as the backend describes it (dashboard/autopilot_api.py): the rules Escanor works inside, the goals it is working on or
/// has finished, and the triggers that start it without anyone asking. Everything is read defensively: a field a newer server adds,
/// or one that is missing, never breaks the screen.
library;

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const [];
String _str(Object? v, [String fallback = '']) => v is String ? v : (v == null ? fallback : '$v');
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

class AutopilotLevel {
  const AutopilotLevel({required this.id, required this.label, required this.about});
  final String id;
  final String label;
  final String about;

  factory AutopilotLevel.fromJson(Object? j) {
    final m = _map(j);
    return AutopilotLevel(id: _str(m['id']), label: _str(m['label']), about: _str(m['about']));
  }
}

class AutopilotCategory {
  const AutopilotCategory({required this.id, required this.label, required this.mode, required this.maxMode, required this.locked});
  final String id;
  final String label;

  /// block | ask | auto
  final String mode;

  /// The most permissive mode this category may ever have.
  final String maxMode;
  final bool locked;

  factory AutopilotCategory.fromJson(Object? j) {
    final m = _map(j);
    return AutopilotCategory(id: _str(m['id']), label: _str(m['label']), mode: _str(m['mode'], 'ask'), maxMode: _str(m['max_mode'], 'auto'), locked: _bool(m['locked']));
  }
}

const modeRank = {'block': 0, 'ask': 1, 'auto': 2};

/// The modes a category may be set to, strictest first.
List<String> modesUpTo(String maxMode) => [for (final m in const ['block', 'ask', 'auto']) if ((modeRank[m] ?? 0) <= (modeRank[maxMode] ?? 2)) m];

const modeLabels = {'block': 'Never', 'ask': 'Ask me', 'auto': 'On its own'};

class AutopilotPolicy {
  const AutopilotPolicy({
    this.enabled = false,
    this.paused = false,
    this.level = 'balanced',
    this.allowIrreversible = false,
    this.verify = true,
    this.notifyOn = const [],
    this.budgets = const {},
    this.categories = const [],
    this.levels = const [],
  });
  final bool enabled;
  final bool paused;
  final String level;
  final bool allowIrreversible;
  final bool verify;
  final List<String> notifyOn;
  final Map<String, int> budgets;
  final List<AutopilotCategory> categories;
  final List<AutopilotLevel> levels;

  factory AutopilotPolicy.fromJson(Object? j) {
    final m = _map(j);
    return AutopilotPolicy(
      enabled: _bool(m['enabled']),
      paused: _bool(m['paused']),
      level: _str(m['level'], 'balanced'),
      allowIrreversible: _bool(m['allow_irreversible']),
      verify: _bool(m['verify'], true),
      notifyOn: [for (final v in _list(m['notify_on'])) if (v is String) v],
      budgets: {for (final e in _map(m['budgets']).entries) e.key: _int(e.value)},
      categories: [for (final c in _list(m['categories'])) AutopilotCategory.fromJson(c)],
      levels: [for (final l in _list(m['levels'])) AutopilotLevel.fromJson(l)],
    );
  }

  String get levelLabel {
    for (final l in levels) {
      if (l.id == level) return l.label;
    }
    return level;
  }
}

class Decision {
  const Decision({required this.title, required this.category, required this.decision, required this.reason});
  final String title;
  final String category;

  /// allow | deny | waiting
  final String decision;
  final String reason;

  factory Decision.fromJson(Object? j) {
    final m = _map(j);
    return Decision(title: _str(m['title']), category: _str(m['category']), decision: _str(m['decision']), reason: _str(m['reason']));
  }
}

class Waiting {
  const Waiting({required this.title, required this.category, required this.reason});
  final String title;
  final String category;
  final String reason;
}

/// running | needs_you | succeeded | failed | stopped (the server may add more; they read as plain text)
class AutopilotRun {
  const AutopilotRun({
    required this.id,
    required this.goal,
    required this.criteria,
    required this.origin,
    required this.status,
    required this.phase,
    required this.createdAt,
    required this.finishedAt,
    required this.summary,
    required this.stopReason,
    required this.verification,
    required this.waiting,
    required this.autoApprovals,
    required this.denials,
    required this.nudges,
    required this.retries,
    required this.decisions,
    required this.steps,
  });
  final String id;
  final String goal;
  final String criteria;
  final String origin;
  final String status;
  final String? phase;
  final String? createdAt;
  final String? finishedAt;
  final String? summary;
  final String? stopReason;
  final String? verification;
  final Waiting? waiting;
  final int autoApprovals;
  final int denials;
  final int nudges;
  final int retries;
  final List<Decision> decisions;
  final List<String> steps;

  bool get active => status == 'running' || status == 'needs_you';

  factory AutopilotRun.fromJson(Object? j) {
    final m = _map(j);
    final w = m['waiting'];
    final steps = <String>[];
    for (final s in _list(m['steps'])) {
      final sm = _map(s);
      final text = _str(sm['title'], _str(sm['text'], _str(sm['summary'])));
      if (text.isNotEmpty) steps.add(text);
    }
    return AutopilotRun(
      id: _str(m['id']),
      goal: _str(m['goal']),
      criteria: _str(m['criteria']),
      origin: _str(m['origin'], 'manual'),
      status: _str(m['status']),
      phase: _strOrNull(m['phase']),
      createdAt: _strOrNull(m['created_at']),
      finishedAt: _strOrNull(m['finished_at']),
      summary: _strOrNull(m['summary']),
      stopReason: _strOrNull(m['stop_reason']),
      verification: _strOrNull(m['verification']),
      waiting: w is Map ? Waiting(title: _str(w['title']), category: _str(w['category']), reason: _str(w['reason'])) : null,
      autoApprovals: _int(m['auto_approvals']),
      denials: _int(m['denials']),
      nudges: _int(m['nudges']),
      retries: _int(m['retries']),
      decisions: [for (final d in _list(m['decisions'])) Decision.fromJson(d)],
      steps: steps,
    );
  }
}

const triggerKinds = ['schedule', 'deployment_failed', 'incident_opened', 'health_below', 'integration_error'];

const triggerKindLabels = {
  'schedule': 'On a schedule',
  'deployment_failed': 'When a deployment fails',
  'incident_opened': 'When an incident opens',
  'health_below': 'When health drops',
  'integration_error': 'When a tool stops syncing',
};

class Trigger {
  const Trigger({
    required this.id,
    required this.name,
    required this.kind,
    required this.goal,
    required this.criteria,
    required this.config,
    required this.enabled,
    required this.cooldownMinutes,
    required this.lastFiredAt,
    required this.lastError,
    required this.firedCount,
  });
  final String id;
  final String name;
  final String kind;
  final String goal;
  final String criteria;
  final Map<String, dynamic> config;
  final bool enabled;
  final int cooldownMinutes;
  final String? lastFiredAt;
  final String? lastError;
  final int firedCount;

  factory Trigger.fromJson(Object? j) {
    final m = _map(j);
    return Trigger(
      id: _str(m['id']),
      name: _str(m['name']),
      kind: _str(m['kind']),
      goal: _str(m['goal']),
      criteria: _str(m['criteria']),
      config: _map(m['config']),
      enabled: _bool(m['enabled'], true),
      cooldownMinutes: _int(m['cooldown_minutes'], 30),
      lastFiredAt: _strOrNull(m['last_fired_at']),
      lastError: _strOrNull(m['last_error']),
      firedCount: _int(m['fired_count']),
    );
  }

  /// "Every 30 minutes", "Every day at 09:00 UTC", "When health is below 70".
  String get when {
    switch (kind) {
      case 'schedule':
        final every = config['every_minutes'];
        if (every is num) {
          final n = every.toInt();
          if (n % 1440 == 0) return n == 1440 ? 'Every day' : 'Every ${n ~/ 1440} days';
          if (n % 60 == 0) return n == 60 ? 'Every hour' : 'Every ${n ~/ 60} hours';
          return 'Every $n minutes';
        }
        final daily = config['daily_at'];
        return daily is String ? 'Every day at $daily UTC' : 'On a schedule';
      case 'health_below':
        return 'When health is below ${config['threshold'] ?? 70}';
      default:
        return triggerKindLabels[kind] ?? kind;
    }
  }
}

class TriggerTemplate {
  const TriggerTemplate({required this.id, required this.name, required this.kind, required this.goal, required this.criteria, required this.config});
  final String id;
  final String name;
  final String kind;
  final String goal;
  final String criteria;
  final Map<String, dynamic> config;

  factory TriggerTemplate.fromJson(Object? j) {
    final m = _map(j);
    return TriggerTemplate(
        id: _str(m['id']), name: _str(m['name']), kind: _str(m['kind']), goal: _str(m['goal']), criteria: _str(m['criteria']), config: _map(m['config']));
  }
}

class AutopilotOverview {
  const AutopilotOverview({
    required this.policy,
    required this.canManage,
    required this.autoApprovalsToday,
    required this.runsToday,
    required this.active,
    required this.runs,
    required this.needsYou,
    required this.triggers,
    required this.templates,
    required this.assistantReady,
    required this.assistantMessage,
  });
  final AutopilotPolicy policy;
  final bool canManage;
  final int autoApprovalsToday;
  final int runsToday;
  final int active;
  final List<AutopilotRun> runs;
  final List<AutopilotRun> needsYou;
  final List<Trigger> triggers;
  final List<TriggerTemplate> templates;
  final bool assistantReady;
  final String assistantMessage;

  factory AutopilotOverview.fromJson(Object? j) {
    final m = _map(j);
    final usage = _map(m['usage']);
    final assistant = _map(m['assistant']);
    return AutopilotOverview(
      policy: AutopilotPolicy.fromJson(m['policy']),
      canManage: _bool(m['can_manage']),
      autoApprovalsToday: _int(usage['auto_approvals_today']),
      runsToday: _int(usage['runs_today']),
      active: _int(usage['active']),
      runs: [for (final r in _list(m['runs'])) AutopilotRun.fromJson(r)],
      needsYou: [for (final r in _list(m['needs_you'])) AutopilotRun.fromJson(r)],
      triggers: [for (final t in _list(m['triggers'])) Trigger.fromJson(t)],
      templates: [for (final t in _list(m['templates'])) TriggerTemplate.fromJson(t)],
      assistantReady: _bool(assistant['ready']),
      assistantMessage: _str(assistant['message']),
    );
  }

}

/// The headline over the overview: what Escanor is doing on its own right now, in a sentence.
String autopilotHeadline(AutopilotPolicy p, int active, int waiting) {
  if (p.paused) return 'Stopped. Nothing runs until you resume.';
  if (!p.enabled) return 'Off. Turn it on and Escanor works on its own, inside your rules.';
  if (waiting > 0) return waiting == 1 ? '1 thing needs your answer.' : '$waiting things need your answer.';
  if (active > 0) return active == 1 ? 'Working on 1 goal.' : 'Working on $active goals.';
  return 'On (${p.levelLabel}). Nothing running right now.';
}

const originLabels = {'manual': 'You', 'trigger': 'A trigger', 'schedule': 'A schedule'};

const runStatusLabels = {
  'running': 'Running',
  'needs_you': 'Needs you',
  'succeeded': 'Done',
  'failed': 'Failed',
  'stopped': 'Stopped',
};

const notifyChoices = [
  (id: 'needs_you', label: 'When a run needs me'),
  (id: 'finished', label: 'When a run finishes'),
  (id: 'failed', label: 'When a run fails'),
  (id: 'acted', label: 'Every time it acts on its own'),
];

/// One limit a run works inside, with the range the server accepts (autopilot/policy.py BUDGET_LIMITS). In the order Rules shows them.
typedef BudgetLimit = ({String key, String label, String unit, int min, int max});

const budgetLimits = <BudgetLimit>[
  (key: 'max_minutes_per_run', label: 'Longest run', unit: 'min', min: 1, max: 240),
  (key: 'max_steps_per_run', label: 'Most steps in a run', unit: '', min: 5, max: 300),
  (key: 'max_runs_per_day', label: 'Runs a day', unit: '', min: 0, max: 200),
  (key: 'max_concurrent_runs', label: 'Runs at once', unit: '', min: 1, max: 10),
  (key: 'max_auto_approvals_per_run', label: 'Actions on its own, per run', unit: '', min: 0, max: 100),
  (key: 'max_auto_approvals_per_day', label: 'Actions on its own, per day', unit: '', min: 0, max: 1000),
  (key: 'ask_timeout_minutes', label: 'Waits for an answer', unit: 'min', min: 1, max: 1440),
  (key: 'stall_minutes', label: 'Quiet time before nudging', unit: 'min', min: 2, max: 60),
  (key: 'max_nudges', label: 'Nudges when it goes quiet', unit: '', min: 0, max: 5),
  (key: 'max_retries', label: 'Tries again after a failed check', unit: '', min: 0, max: 3),
];

/// "From 1 to 240 min".
String budgetRangeText(BudgetLimit b) => 'From ${b.min} to ${b.max}${b.unit.isEmpty ? '' : ' ${b.unit}'}';

/// What is wrong with [text] as a value for [b], in words; null when it is a whole number inside the range.
String? budgetProblem(BudgetLimit b, String text) {
  final t = text.trim();
  final n = RegExp(r'^\d+$').hasMatch(t) ? int.tryParse(t) : null;
  if (n == null || n < b.min || n > b.max) return 'Use a whole number from ${b.min} to ${b.max}.';
  return null;
}

/// Why a kind cannot go further than it is, for the rows that are capped. Null when it can be set to anything.
String? ceilingNote(AutopilotCategory cat) {
  if (cat.maxMode == 'auto') return null;
  return switch (cat.id) {
    'billing' => 'Escanor never spends money by itself. That is always refused, and needs a person.',
    'team' => 'Escanor never changes who has access. That is always refused, and needs a person.',
    'secrets' => 'Keys and tokens always wait for you. Escanor can only ask.',
    'destructive' => 'Turn on “Allow things that cannot be undone” first if this should happen on its own.',
    _ => cat.maxMode == 'block' ? 'This is always refused.' : 'This always waits for you.',
  };
}
