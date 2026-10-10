import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../machines/message_format.dart' show timeAgo;
import 'autopilot_api.dart';
import 'autopilot_models.dart';
import 'automations_screen.dart' show StatusBadge;

const _examples = [
  'Check everything connected and fix what is safe to fix',
  'Find out why the last deployment failed',
  'Make sure my production site is healthy and tell me if it is not',
];

/// Hand Escanor a goal. It works on it by itself, checks the result, and keeps going until it is met or it cannot be.
class StartGoalSheet extends StatefulWidget {
  const StartGoalSheet({super.key});
  @override
  State<StartGoalSheet> createState() => _StartGoalSheetState();
}

class _StartGoalSheetState extends State<StartGoalSheet> {
  final _goal = TextEditingController();
  final _criteria = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _goal.dispose();
    _criteria.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final goal = _goal.text.trim();
    if (goal.length < 3) {
      setState(() => _error = 'Say what you want done.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.startAutopilotRun(goal, criteria: _criteria.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('Say what you want done. Escanor does it, checks the result itself, fixes what went wrong and keeps going until it is done. It only comes back to you if it truly needs you.',
          style: TextStyle(fontSize: 13, height: 1.45, color: c.muted)),
      const SizedBox(height: 12),
      TextField(
        controller: _goal,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 1200,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(hintText: 'What should it do?'),
        style: TextStyle(fontSize: 15, color: c.ink),
      ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in _examples) ActionChip(label: Text(e, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _goal.text = e)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _criteria,
        minLines: 1,
        maxLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(hintText: 'How will we know it worked? (optional)'),
        style: TextStyle(fontSize: 14, color: c.ink),
      ),
      if (_error != null) ...[const SizedBox(height: 4), Notice(_error!, tone: NoticeTone.error)],
      const SizedBox(height: 12),
      EButton(label: 'Start', icon: Icons.bolt_rounded, expand: true, busy: _busy, onPressed: _start),
    ]);
  }
}

/// One run: how it went, what it decided on its own, and the steps it took. Refreshes while it is running.
class RunDetailSheet extends StatefulWidget {
  const RunDetailSheet({super.key, required this.runId, required this.first, required this.canStop, required this.onChanged});
  final String runId;
  final AutopilotRun first;
  final bool canStop;
  final VoidCallback onChanged;
  @override
  State<RunDetailSheet> createState() => _RunDetailSheetState();
}

class _RunDetailSheetState extends State<RunDetailSheet> {
  late AutopilotRun _run = widget.first;
  Timer? _timer;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_run.active) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await api.autopilotRun(widget.runId);
      if (mounted) setState(() => _run = r);
    } catch (e) {
      if (mounted && _run.steps.isEmpty) setState(() => _error = errorText(e));
    }
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    try {
      await api.stopAutopilotRun(widget.runId);
      widget.onChanged();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _run;
    Widget section(String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
            const SizedBox(height: 4),
            SelectableText(text, style: TextStyle(fontSize: 14, height: 1.45, color: c.ink)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        StatusBadge(r.status),
        const SizedBox(width: 8),
        if (r.createdAt != null) Text('Started ${timeAgo(r.createdAt!)}', style: TextStyle(fontSize: 12, color: c.muted)),
        const Spacer(),
        if (r.phase != null && r.active) Text(r.phase!, style: TextStyle(fontSize: 12, color: c.mutedSoft)),
      ]),
      const SizedBox(height: 12),
      if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 10)],
      section('Goal', r.goal),
      if (r.criteria.isNotEmpty) section('Counts as done when', r.criteria),
      if (r.waiting != null) section('Waiting for you', '${r.waiting!.title}\n${r.waiting!.reason}'),
      if (r.summary != null) section('How it went', r.summary!),
      if (r.verification != null) section('Checked', r.verification!),
      if (r.stopReason != null) section('Stopped because', r.stopReason!),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _Count('Done on its own', r.autoApprovals),
        _Count('Declined', r.denials),
        _Count('Nudged back on track', r.nudges),
        _Count('Tried again', r.retries),
      ]),
      if (r.decisions.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('WHAT IT DECIDED', style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
        const SizedBox(height: 6),
        for (final d in r.decisions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(d.decision == 'allow' ? Icons.check_circle_outline_rounded : (d.decision == 'deny' ? Icons.block_rounded : Icons.help_outline_rounded),
                  size: 16, color: d.decision == 'allow' ? c.success : (d.decision == 'deny' ? c.error : c.warning)),
              const SizedBox(width: 8),
              Expanded(child: Text(d.title.isEmpty ? d.reason : '${d.title}${d.reason.isEmpty ? '' : ' · ${d.reason}'}', style: TextStyle(fontSize: 12.5, height: 1.35, color: c.body))),
            ]),
          ),
      ],
      if (r.steps.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('STEPS', style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
        const SizedBox(height: 6),
        for (var i = 0; i < r.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i + 1}. ${r.steps[i]}', style: TextStyle(fontSize: 12.5, height: 1.35, color: c.body)),
          ),
      ],
      if (r.active && widget.canStop) ...[
        const SizedBox(height: 16),
        EButton(label: 'Stop this run', kind: ButtonKind.danger, expand: true, busy: _stopping, onPressed: _stop),
      ],
    ]);
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.n);
  final String label;
  final int n;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (n == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text('$label · $n', style: TextStyle(fontSize: 12, color: c.body)),
    );
  }
}

/// Ready-made automations, then a blank one.
class TemplatesSheet extends StatelessWidget {
  const TemplatesSheet({super.key, required this.templates});
  final List<TriggerTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Future<void> edit(TriggerTemplate? t) async {
      final saved = await showESheet<bool>(context, title: 'New automation', builder: (_) => TriggerEditor(template: t, canManage: true));
      if (saved == true && context.mounted) Navigator.of(context).pop(true);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Group(children: [
        for (final t in templates)
          SRow(
            label: t.name,
            sub: triggerKindLabels[t.kind],
            onTap: () => edit(t),
          ),
        SRow(icon: Icons.tune_rounded, label: 'Something of my own', sub: 'Pick when it starts and what it should do.', onTap: () => edit(null)),
      ]),
      const SizedBox(height: 10),
      Text('Each one starts a run by itself, with the rules you set in Rules. Nothing here needs you to be in the app.', style: TextStyle(fontSize: 12, height: 1.4, color: c.muted)),
    ]);
  }
}

/// Make or change one automation: when it starts, what it does, and how it is judged done.
class TriggerEditor extends StatefulWidget {
  const TriggerEditor({super.key, this.trigger, this.template, required this.canManage});
  final Trigger? trigger;
  final TriggerTemplate? template;
  final bool canManage;
  @override
  State<TriggerEditor> createState() => _TriggerEditorState();
}

class _TriggerEditorState extends State<TriggerEditor> {
  late final _name = TextEditingController(text: widget.trigger?.name ?? widget.template?.name ?? '');
  late final _goal = TextEditingController(text: widget.trigger?.goal ?? widget.template?.goal ?? '');
  late final _criteria = TextEditingController(text: widget.trigger?.criteria ?? widget.template?.criteria ?? '');
  late String _kind = widget.trigger?.kind ?? widget.template?.kind ?? 'schedule';
  late Map<String, dynamic> _config = Map.of(widget.trigger?.config ?? widget.template?.config ?? const {'daily_at': '09:00'});
  late int _cooldown = widget.trigger?.cooldownMinutes ?? 30;
  late bool _enabled = widget.trigger?.enabled ?? true;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.trigger != null;

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _criteria.dispose();
    super.dispose();
  }

  Map<String, dynamic> _configFor(String kind) {
    if (kind == 'schedule') {
      if (_config.containsKey('every_minutes')) return {'every_minutes': _config['every_minutes']};
      return {'daily_at': _config['daily_at'] ?? '09:00'};
    }
    if (kind == 'health_below') return {'threshold': _config['threshold'] ?? 70};
    return {};
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, Object?>{
      'name': _name.text.trim(),
      'kind': _kind,
      'goal': _goal.text.trim(),
      'criteria': _criteria.text.trim(),
      'config': _configFor(_kind),
      'cooldown_minutes': _cooldown,
      'enabled': _enabled,
    };
    try {
      if (_editing) {
        await api.editTrigger(widget.trigger!.id, body);
      } else {
        await api.addTrigger(body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.runTriggerNow(widget.trigger!.id);
      if (!mounted) return;
      toast(context, 'Started. Find it under Runs.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Delete this automation?', message: 'It will stop starting runs. Runs it already made stay in the list.', ok: 'Delete', danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.removeTrigger(widget.trigger!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // The server keeps schedules in UTC; the person picks a time on their own clock.
  String _localTime(String utc) {
    final p = utc.split(':');
    final h = int.tryParse(p.first) ?? 9;
    final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    final local = DateTime.utc(2000, 1, 1, h, m).toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDaily() async {
    final cur = (_config['daily_at'] as String?) ?? '09:00';
    final local = _localTime(cur).split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(local[0]), minute: int.parse(local[1])));
    if (t == null) return;
    final now = DateTime.now();
    final utc = DateTime(now.year, now.month, now.day, t.hour, t.minute).toUtc();
    setState(() => _config = {'daily_at': '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}'});
  }

  Future<void> _pickEvery() async {
    const options = [(5, 'Every 5 minutes'), (15, 'Every 15 minutes'), (30, 'Every 30 minutes'), (60, 'Every hour'), (180, 'Every 3 hours'), (360, 'Every 6 hours'), (720, 'Every 12 hours'), (1440, 'Every day')];
    final cur = _config['every_minutes'] is int ? _config['every_minutes'] as int : 60;
    final v = await showChoiceSheet<int>(context, title: 'How often', value: cur, options: [for (final o in options) Choice(o.$1, o.$2)]);
    if (v != null) setState(() => _config = {'every_minutes': v});
  }

  Future<void> _pickKind() async {
    final v = await showChoiceSheet<String>(context, title: 'Start it', value: _kind, options: [for (final k in triggerKinds) Choice(k, triggerKindLabels[k] ?? k)]);
    if (v == null || v == _kind) return;
    setState(() {
      _kind = v;
      _config = v == 'schedule' ? {'daily_at': '09:00'} : (v == 'health_below' ? {'threshold': 70} : {});
    });
  }

  Future<void> _pickThreshold() async {
    final cur = (_config['threshold'] as int?) ?? 70;
    final v = await showChoiceSheet<int>(context, title: 'Health below', value: cur, options: [for (final n in const [50, 60, 70, 80, 90]) Choice(n, '$n')]);
    if (v != null) setState(() => _config = {'threshold': v});
  }

  Future<void> _pickCooldown() async {
    const options = [(5, '5 minutes'), (30, '30 minutes'), (60, '1 hour'), (360, '6 hours'), (1440, '1 day')];
    final v = await showChoiceSheet<int>(context, title: 'At least this long between runs', value: _cooldown, options: [for (final o in options) Choice(o.$1, o.$2)]);
    if (v != null) setState(() => _cooldown = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final can = widget.canManage;
    final everyMode = _kind == 'schedule' && _config.containsKey('every_minutes');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _name,
        enabled: can,
        maxLength: 100,
        decoration: const InputDecoration(hintText: 'Name', counterText: ''),
        style: TextStyle(fontSize: 15, color: c.ink),
      ),
      const SizedBox(height: 12),
      Group(title: 'When', children: [
        SRow(label: 'Start it', value: triggerKindLabels[_kind], onTap: can ? _pickKind : null),
        if (_kind == 'schedule') ...[
          SRow(
            label: 'Repeat',
            value: everyMode ? 'Every N minutes' : 'Once a day',
            onTap: can ? () => setState(() => _config = everyMode ? {'daily_at': '09:00'} : {'every_minutes': 60}) : null,
          ),
          if (everyMode)
            SRow(label: 'How often', value: Trigger(id: '', name: '', kind: 'schedule', goal: '', criteria: '', config: _config, enabled: true, cooldownMinutes: 0, lastFiredAt: null, lastError: null, firedCount: 0).when, onTap: can ? _pickEvery : null)
          else
            SRow(label: 'At', value: _localTime((_config['daily_at'] as String?) ?? '09:00'), sub: 'Your time', onTap: can ? _pickDaily : null),
        ],
        if (_kind == 'health_below') SRow(label: 'Health below', value: '${_config['threshold'] ?? 70}', onTap: can ? _pickThreshold : null),
        if (_kind != 'schedule') SRow(label: 'At least this long between runs', value: '$_cooldown min', onTap: can ? _pickCooldown : null),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _goal,
        enabled: can,
        minLines: 3,
        maxLines: 6,
        maxLength: 1200,
        decoration: const InputDecoration(hintText: 'What should it do?'),
        style: TextStyle(fontSize: 14, color: c.ink),
      ),
      TextField(
        controller: _criteria,
        enabled: can,
        minLines: 1,
        maxLines: 3,
        maxLength: 1000,
        decoration: const InputDecoration(hintText: 'Counts as done when… (optional)'),
        style: TextStyle(fontSize: 14, color: c.ink),
      ),
      if (_editing) SwitchRow(label: 'On', on: _enabled, disabled: !can, onChanged: (v) => setState(() => _enabled = v)),
      if (_error != null) ...[const SizedBox(height: 8), Notice(_error!, tone: NoticeTone.error)],
      const SizedBox(height: 12),
      if (can) EButton(label: _editing ? 'Save' : 'Add', expand: true, busy: _busy, onPressed: _save),
      if (can && _editing) ...[
        const SizedBox(height: 8),
        EButton(label: 'Run it now', kind: ButtonKind.quiet, expand: true, onPressed: _busy ? null : _runNow),
        const SizedBox(height: 8),
        EButton(label: 'Delete', kind: ButtonKind.danger, expand: true, onPressed: _busy ? null : _delete),
      ],
      if (!can) Text('Only the owner or an admin of the workspace can change automations.', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}
