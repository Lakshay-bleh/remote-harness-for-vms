import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/prefs.dart' show haptic;
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import '../machines/message_format.dart' show relativeTime;
import 'autopilot_api.dart';
import 'autopilot_models.dart';
import 'trigger_sheets.dart';

enum _Section { overview, runs, automations, rules }

const _sectionLabels = {
  _Section.overview: 'Overview',
  _Section.runs: 'Runs',
  _Section.automations: 'Automations',
  _Section.rules: 'Rules',
};


/// Automations: everything Escanor does on its own. A goal you hand it, the automations that start it with nobody asking (a
/// schedule, a failed deployment, an incident, a drop in health), every run in detail, and the rules it works inside. The same
/// thing the website's Automations page shows, on the same account.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});
  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  // Looks again every 15 seconds, and when the app comes back to the front, so a run that finished while the phone was in a pocket shows.
  late final Loader<AutopilotOverview> _data = Loader(() => api.autopilotOverview(), every: const Duration(seconds: 15));
  _Section _section = _Section.overview;
  bool _working = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _data.addListener(_changed);
  }

  @override
  void dispose() {
    _data.removeListener(_changed);
    _data.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Do something to the account, show what went wrong in words, and look again.
  Future<bool> _do(Future<void> Function() action, {String? done}) async {
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      await action();
      if (!mounted) return true;
      if (done != null) toast(context, done);
      _data.reload();
      return true;
    } catch (e) {
      if (mounted) setState(() => _notice = errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startGoal() async {
    final started = await showESheet<bool>(context, title: 'Give it a goal', builder: (_) => const StartGoalSheet());
    if (started == true) {
      _data.reload();
      if (mounted) setState(() => _section = _Section.runs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _data.data;
    return Material(
      color: c.canvas,
      child: Column(children: [
        ScreenHeader(title: 'Automations', subtitle: d == null ? null : autopilotHeadline(d.policy, d.active, d.needsYou.length), actions: [
          if (d != null && !d.policy.paused && d.canManage && d.policy.enabled)
            IconButton(
              tooltip: 'Stop everything now',
              onPressed: _working ? null : () => _stopAll(),
              icon: Icon(Icons.stop_circle_outlined, size: 24, color: c.error),
            ),
          IconButton(tooltip: 'Refresh', onPressed: _data.refreshing ? null : _data.reload, icon: Icon(Icons.refresh_rounded, size: 22, color: c.body)),
        ]),
        _SectionBar(
          value: _section,
          badges: {_Section.overview: d?.needsYou.length ?? 0},
          onChanged: (s) => setState(() => _section = s),
        ),
        if (_data.refreshing && d != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(context, d)),
      ]),
    );
  }

  Future<void> _stopAll() async {
    final ok = await confirm(context,
        title: 'Stop everything now?', message: 'Every run stops and nothing new starts until you resume it.', ok: 'Stop everything', danger: true);
    if (ok) await _do(() => api.pauseAutopilot(), done: 'Stopped.');
  }

  Widget _body(BuildContext context, AutopilotOverview? d) {
    if (d == null) {
      if (_data.error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Notice(_data.error!, tone: NoticeTone.error),
              const SizedBox(height: 12),
              EButton(label: 'Try again', kind: ButtonKind.quiet, onPressed: _data.reload),
            ]),
          ),
        );
      }
      return const Center(child: Spinner());
    }
    final children = switch (_section) {
      _Section.overview => _overview(context, d),
      _Section.runs => _runs(context, d),
      _Section.automations => _automations(context, d),
      _Section.rules => _rules(context, d),
    };
    return RefreshIndicator(
      onRefresh: () async {
        _data.reload();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (_notice != null) ...[Notice(_notice!, tone: NoticeTone.error), const SizedBox(height: 12)],
          if (!d.assistantReady && d.assistantMessage.isNotEmpty) ...[
            Notice('The assistant is not ready yet: ${d.assistantMessage}', tone: NoticeTone.warn),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ overview

  List<Widget> _overview(BuildContext context, AutopilotOverview d) {
    final c = context.c;
    final p = d.policy;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p.paused ? 'Stopped' : (p.enabled ? 'Working on its own' : 'Off'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.ink)),
            ),
            if (d.canManage && !p.paused) ESwitch(on: p.enabled, disabled: _working, onChanged: (v) => _do(() => api.setAutopilotPolicy({'enabled': v}), done: v ? 'Turned on.' : 'Turned off.')),
          ]),
          const SizedBox(height: 4),
          Text(autopilotHeadline(p, d.active, d.needsYou.length), style: TextStyle(fontSize: 13, height: 1.4, color: c.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat('Today', '${d.runsToday} ${d.runsToday == 1 ? 'run' : 'runs'}'),
            _Stat('On its own', '${d.autoApprovalsToday} ${d.autoApprovalsToday == 1 ? 'action' : 'actions'}'),
            _Stat('Level', p.levelLabel),
          ]),
          const SizedBox(height: 14),
          if (p.paused && d.canManage)
            EButton(label: 'Resume', expand: true, busy: _working, onPressed: () => _do(() => api.resumeAutopilot(), done: 'Resumed.'))
          else
            EButton(label: 'Give it a goal', icon: Icons.bolt_rounded, expand: true, onPressed: p.paused ? null : _startGoal),
        ]),
      ),
      if (d.needsYou.isNotEmpty) ...[
        const SizedBox(height: 18),
        _Title('Needs your answer'),
        for (final r in d.needsYou) _NeedsYouCard(run: r, canAnswer: d.canManage, busy: _working, onAnswer: (allow) => _do(() => api.answerAutopilotRun(r.id, allow: allow), done: allow ? 'Approved.' : 'Declined.')),
      ],
      const SizedBox(height: 18),
      _Title('Latest runs'),
      if (d.runs.isEmpty)
        const DogState(scene: 'sit', scale: 4, title: 'Nothing yet', text: 'Give it a goal, or set an automation, and its runs show up here.')
      else
        for (final r in d.runs.take(5)) _RunTile(run: r, onTap: () => _openRun(r)),
      if (d.runs.length > 5)
        TextButton(onPressed: () => setState(() => _section = _Section.runs), child: Text('All ${d.runs.length} runs', style: TextStyle(color: c.primary))),
    ];
  }

  void _openRun(AutopilotRun r) => showESheet<void>(context, title: 'Run', builder: (_) => RunDetailSheet(runId: r.id, first: r, canStop: true, onChanged: _data.reload));

  // ------------------------------------------------------------------------------------------------ runs

  List<Widget> _runs(BuildContext context, AutopilotOverview d) {
    if (d.runs.isEmpty) {
      return [
        const DogState(scene: 'sit', scale: 4, title: 'No runs yet', text: 'Everything Escanor does on its own is listed here, with how it went.'),
        const SizedBox(height: 12),
        EButton(label: 'Give it a goal', expand: true, onPressed: d.policy.paused ? null : _startGoal),
      ];
    }
    return [for (final r in d.runs) _RunTile(run: r, onTap: () => _openRun(r))];
  }

  // ------------------------------------------------------------------------------------------------ automations (triggers)

  List<Widget> _automations(BuildContext context, AutopilotOverview d) {
    final c = context.c;
    return [
      Text('Automations start Escanor when nobody is saying anything: at a time you pick, or when something goes wrong.',
          style: TextStyle(fontSize: 13, height: 1.45, color: c.muted)),
      const SizedBox(height: 12),
      if (d.canManage) EButton(label: 'Add an automation', icon: Icons.add_rounded, expand: true, onPressed: () => _addTrigger(d)),
      const SizedBox(height: 12),
      if (d.triggers.isEmpty)
        const DogState(scene: 'sleep', title: 'No automations yet', text: 'Pick one of the ready-made ones, like a check every morning.')
      else
        for (final t in d.triggers)
          _TriggerTile(
            trigger: t,
            canManage: d.canManage,
            onTap: () => _editTrigger(t),
            onToggle: (v) => _do(() => api.editTrigger(t.id, {'enabled': v}), done: v ? 'Turned on.' : 'Turned off.'),
          ),
    ];
  }

  Future<void> _addTrigger(AutopilotOverview d) async {
    final saved = await showESheet<bool>(context, title: 'Add an automation', builder: (_) => TemplatesSheet(templates: d.templates));
    if (saved == true) _data.reload();
  }

  Future<void> _editTrigger(Trigger t) async {
    final changed = await showESheet<bool>(context, title: 'Automation', builder: (_) => TriggerEditor(trigger: t, canManage: _data.data?.canManage ?? false));
    if (changed == true) _data.reload();
  }

  // ------------------------------------------------------------------------------------------------ rules

  List<Widget> _rules(BuildContext context, AutopilotOverview d) {
    final c = context.c;
    final p = d.policy;
    final canEdit = d.canManage;
    return [
      if (!canEdit) const Notice('Only the owner or an admin of the workspace can change these rules.'),
      if (!canEdit) const SizedBox(height: 12),
      Group(title: 'How much it does by itself', footer: 'Deleting, secrets, money and people’s access always wait for you, or are refused, whatever you choose.', children: [
        for (final l in p.levels)
          InkWell(
            onTap: canEdit && !_working ? () => _do(() => api.setAutopilotPolicy({'level': l.id}), done: '${l.label}.') : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.label, style: TextStyle(fontSize: 15, color: c.ink)),
                    const SizedBox(height: 2),
                    Text(l.about, style: TextStyle(fontSize: 12, height: 1.35, color: c.muted)),
                  ]),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.level == l.id ? c.primary : Colors.transparent,
                    border: Border.all(color: p.level == l.id ? c.primary : c.lineStrong),
                  ),
                  child: p.level == l.id ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c.onPrimary))) : null,
                ),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'Checking its own work', children: [
        SwitchRow(
          icon: Icons.fact_check_outlined,
          label: 'Check the goal was really met',
          sub: 'Before a run counts as done, Escanor looks for proof, and keeps going if it is not there.',
          on: p.verify,
          disabled: !canEdit || _working,
          onChanged: (v) => _do(() => api.setAutopilotPolicy({'verify': v})),
        ),
        SwitchRow(
          icon: Icons.warning_amber_rounded,
          label: 'Allow things that cannot be undone',
          sub: 'Deleting and disconnecting may then happen without asking.',
          on: p.allowIrreversible,
          disabled: !canEdit || _working,
          onChanged: (v) => _do(() => api.setAutopilotPolicy({'allow_irreversible': v})),
        ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'What it may do, by kind', children: [
        for (final cat in p.categories)
          SRow(
            label: cat.label,
            value: modeLabels[cat.mode] ?? cat.mode,
            icon: cat.locked ? Icons.lock_outline_rounded : null,
            onTap: canEdit && modesUpTo(cat.maxMode).length > 1 ? () => _pickMode(cat) : null,
          ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'Tell me', children: [
        for (final n in notifyChoices)
          SwitchRow(
            label: n.label,
            on: p.notifyOn.contains(n.id),
            disabled: !canEdit || _working,
            onChanged: (v) {
              final next = [...p.notifyOn.where((x) => x != n.id), if (v) n.id];
              _do(() => api.setAutopilotPolicy({'notify_on': next}));
            },
          ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'Limits', footer: 'Escanor stops a run that goes past these.', children: [
        for (final e in _budgetRows(p)) SRow(label: e.$1, value: e.$2),
      ]),
    ];
  }

  List<(String, String)> _budgetRows(AutopilotPolicy p) {
    String v(String k, [String unit = '']) => p.budgets[k] == null ? '—' : '${p.budgets[k]}$unit';
    return [
      ('Longest run', v('max_minutes_per_run', ' min')),
      ('Most steps in a run', v('max_steps_per_run')),
      ('Runs a day', v('max_runs_per_day')),
      ('Runs at once', v('max_concurrent_runs')),
      ('Actions on its own, per run', v('max_auto_approvals_per_run')),
      ('Actions on its own, per day', v('max_auto_approvals_per_day')),
      ('Waits for an answer', v('ask_timeout_minutes', ' min')),
    ];
  }

  Future<void> _pickMode(AutopilotCategory cat) async {
    final v = await showChoiceSheet<String>(context,
        title: cat.label, value: cat.mode, options: [for (final m in modesUpTo(cat.maxMode)) Choice(m, modeLabels[m] ?? m)]);
    if (v == null || v == cat.mode) return;
    final overrides = {for (final x in _data.data?.policy.categories ?? const <AutopilotCategory>[]) x.id: x.mode, cat.id: v};
    await _do(() => api.setAutopilotPolicy({'overrides': overrides}), done: 'Saved.');
  }
}

// ------------------------------------------------------------------------------------------------ pieces

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.value, required this.onChanged, required this.badges});
  final _Section value;
  final ValueChanged<_Section> onChanged;
  final Map<_Section, int> badges;

  /// Four equal tabs that always fit, whatever the width of the phone: nothing hides off to the side.
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
      child: Row(children: [
        for (final s in _Section.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: s == value,
              child: InkWell(
                onTap: () {
                  haptic();
                  onChanged(s);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: s == value ? c.primary : Colors.transparent, width: 2))),
                  alignment: Alignment.center,
                  child: Text(
                    '${_sectionLabels[s]}${(badges[s] ?? 0) > 0 ? ' · ${badges[s]}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: s == value ? FontWeight.w600 : FontWeight.w400, color: s == value ? c.ink : c.muted),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: context.c.muted)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.canvas, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label  ', style: TextStyle(fontSize: 12, color: c.muted)),
        TextSpan(text: value, style: TextStyle(fontSize: 12, color: c.ink, fontWeight: FontWeight.w500)),
      ])),
    );
  }
}

Color statusColor(BuildContext context, String status) {
  final c = context.c;
  return switch (status) {
    'succeeded' => c.success,
    'failed' => c.error,
    'needs_you' => c.warning,
    'running' => c.primary,
    _ => c.muted,
  };
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text(runStatusLabels[status] ?? status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.onTap});
  final AutopilotRun run;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final when = run.createdAt == null ? '' : '${relativeTime(run.createdAt!)} ago';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                StatusBadge(run.status),
                const SizedBox(width: 8),
                Expanded(child: Text('${originLabels[run.origin] ?? run.origin}${when.isEmpty ? '' : ' · $when'}', style: TextStyle(fontSize: 12, color: c.muted))),
                if (run.active && run.phase != null) Text(run.phase!, style: TextStyle(fontSize: 11, color: c.mutedSoft)),
              ]),
              const SizedBox(height: 6),
              Text(run.goal, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.35, color: c.ink)),
              if (run.summary != null) ...[
                const SizedBox(height: 4),
                Text(run.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.muted)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _NeedsYouCard extends StatelessWidget {
  const _NeedsYouCard({required this.run, required this.canAnswer, required this.busy, required this.onAnswer});
  final AutopilotRun run;
  final bool canAnswer;
  final bool busy;
  final void Function(bool allow) onAnswer;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = run.waiting;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.08),
        border: Border.all(color: c.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(run.goal, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 6),
        Text(w?.title.isNotEmpty == true ? w!.title : 'Waiting for your answer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
        if (w != null && w.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(w.reason, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.body))),
        if (canAnswer) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: EButton(label: 'Approve', busy: busy, onPressed: () => onAnswer(true))),
            const SizedBox(width: 8),
            Expanded(child: EButton(label: 'Decline', kind: ButtonKind.quiet, onPressed: busy ? null : () => onAnswer(false))),
          ]),
        ] else
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('An owner or admin answers this.', style: TextStyle(fontSize: 12, color: c.muted))),
      ]),
    );
  }
}

class _TriggerTile extends StatelessWidget {
  const _TriggerTile({required this.trigger, required this.canManage, required this.onTap, required this.onToggle});
  final Trigger trigger;
  final bool canManage;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = trigger;
    final last = t.lastFiredAt == null ? 'Has not run yet' : 'Last ran ${relativeTime(t.lastFiredAt!)} ago · ${t.firedCount} ${t.firedCount == 1 ? 'time' : 'times'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(t.when, style: TextStyle(fontSize: 12.5, color: c.body)),
                  Text(last, style: TextStyle(fontSize: 12, color: c.muted)),
                  if (t.lastError != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(t.lastError!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.error))),
                ]),
              ),
              if (canManage) ESwitch(on: t.enabled, onChanged: onToggle) else Text(t.enabled ? 'On' : 'Off', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
