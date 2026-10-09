import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../settings/settings_widgets.dart';
import 'account_api.dart';
import 'workspace.dart';

const _wsCache = CachePolicy('workspace-settings', ttl: Duration(minutes: 5), maxAge: Duration(days: 7));

/// Your workspace: its name and defaults, the people in it, and what happened lately.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  final _ws = Loader<Map<String, dynamic>>(fetchWorkspaceSettings, cache: _wsCache);
  final _org = Loader<Map<String, dynamic>?>(fetchOrganization);
  int _asked = activityPage;
  late final _log = Loader<List<dynamic>>(_loadLog);
  final _query = TextEditingController();
  String? _group;
  String? _error;
  bool _saving = false;

  Future<List<dynamic>> _loadLog() => fetchAuditLogs(_asked).catchError((_) => <dynamic>[]);

  @override
  void dispose() {
    _ws.dispose();
    _org.dispose();
    _log.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<bool> _save(Map<String, String> patch) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await updateWorkspaceSettings(patch);
      _ws.reload();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError && e.status == 404 ? 'Only owners and admins can change workspace settings.' : errorText(e, 'Could not save.'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editName(String current) {
    showESheet<void>(context, title: 'Workspace name', builder: (_) => _NameForm(initial: current, save: _save));
  }

  Future<void> _pick(String title, List<({String value, String label})> options, String value, String field) async {
    final v = await showChoiceSheet<String>(context, title: title, options: [for (final o in options) Choice(o.value, o.label)], value: value);
    if (v != null) await _save({field: v});
  }

  Future<void> _role(OrgMember m) async {
    final v = await showChoiceSheet<String>(
      context,
      title: 'Role for ${m.name.isNotEmpty ? m.name : m.email}',
      options: const [Choice('member', 'Member', 'Uses the workspace'), Choice('admin', 'Admin', 'Manages members and settings')],
      value: m.role == 'admin' ? 'admin' : 'member',
    );
    if (v == null) return;
    try {
      await setMemberRole(m.userId, v);
      _org.reload();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'Could not change the role.'));
    }
  }

  void _more() {
    setState(() => _asked = nextActivityLimit(_asked));
    _log.reload();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ws, _org, _log]),
      builder: (context, _) {
        final c = context.c;
        final w = _ws.data == null ? null : WorkspaceSettings.fromJson(_ws.data!);
        final org = _org.data == null ? null : Organization.fromJson(_org.data!);
        final all = [for (final j in _log.data ?? const []) if (j is Map) AuditLine.fromJson(Map<String, dynamic>.from(j))];
        final shown = filterActivity(all, group: _group, query: _query.text);
        final more = canLoadMore(all.length, _asked);

        return SettingsPage(title: 'Workspace and team', children: [
          if (_error != null) Notice(_error!, tone: NoticeTone.error),
          if (_ws.loading && w == null) const BlockSpinner(padding: 32),
          if (_ws.error != null && w == null) Notice(_ws.error!, tone: NoticeTone.error),
          if (w != null)
            Group(title: 'Workspace', footer: 'Only owners and admins can change these.', children: [
              SRow(icon: Icons.edit_outlined, label: 'Name', value: w.workspaceName, onTap: () => _editName(w.workspaceName)),
              SRow(
                icon: Icons.public_rounded,
                label: 'Region',
                value: regionLabel(w.defaultRegion),
                disabled: _saving,
                onTap: () => _pick('Region', regions, w.defaultRegion, 'default_region'),
              ),
              SRow(
                icon: Icons.public_rounded,
                label: 'Environment',
                value: environmentLabel(w.environment),
                disabled: _saving,
                onTap: () => _pick('Environment', environments, w.environment, 'environment'),
              ),
              SRow(label: 'Connected machines', value: '${w.connectedDevices}'),
            ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Team'),
            RowsCard(children: [
              if (_org.loading && org == null)
                const BlockSpinner(padding: 16)
              else if (_org.error != null && org == null)
                CardText(_org.error!, error: true)
              else if (org == null)
                const CardText('Only owners and admins can see the team.')
              else
                for (final m in org.members)
                  SRow(
                    icon: Icons.person_outline_rounded,
                    label: m.name.isNotEmpty ? m.name : m.email,
                    sub: m.name.isNotEmpty ? m.email : null,
                    value: roleLabel(m.role),
                    onTap: org.yourRole == 'owner' && m.role != 'owner' ? () => _role(m) : null,
                  ),
            ]),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Recent activity'),
            if (all.isNotEmpty) ...[
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 15, color: c.ink),
                decoration: const InputDecoration(hintText: 'Search activity', prefixIcon: Icon(Icons.search_rounded, size: 20)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final g in [(value: null as String?, label: 'All', count: all.length), ...activityGroups(all)])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Chip(
                        label: g.label,
                        count: g.count,
                        on: _group == g.value,
                        onTap: () => setState(() => _group = g.value),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            RowsCard(children: [
              if (_log.loading && _log.data == null)
                const BlockSpinner(padding: 16)
              else if (all.isEmpty)
                const CardText('Nothing yet.')
              else if (shown.isEmpty)
                CardText('Nothing matches. ${more ? 'Load more to look further back.' : ''}')
              else
                for (final l in shown)
                  SRow(
                    icon: Icons.history_rounded,
                    label: describeAction(l.action),
                    sub: [l.actorEmail, l.target, l.detail].where((x) => x != null && x.isNotEmpty).join(' · '),
                    value: ago(l.createdAt),
                  ),
            ]),
            if (more) ...[
              const SizedBox(height: 8),
              EButton(
                label: _log.refreshing ? 'Loading…' : 'Show more',
                kind: ButtonKind.quiet,
                expand: true,
                onPressed: _log.refreshing ? null : _more,
              ),
            ],
          ]),
        ]);
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.on, required this.onTap});
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? c.primary.withValues(alpha: 0.1) : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.primary : c.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label, style: TextStyle(color: on ? c.primary : c.body)),
                TextSpan(text: ' $count', style: TextStyle(color: c.muted)),
              ]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _NameForm extends StatefulWidget {
  const _NameForm({required this.initial, required this.save});
  final String initial;
  final Future<bool> Function(Map<String, String>) save;
  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final _name = TextEditingController(text: widget.initial);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = cleanWorkspaceName(_name.text);
    if (n == null) return;
    setState(() => _saving = true);
    final ok = await widget.save({'workspace_name': n});
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        LabeledField(label: null, controller: _name, maxLength: 80, autofocus: true, onChanged: (_) => setState(() {}), onSubmitted: (_) => _submit()),
        const SizedBox(height: 12),
        EButton(
          label: _saving ? 'Saving…' : 'Save',
          expand: true,
          onPressed: _saving || cleanWorkspaceName(_name.text) == null ? null : _submit,
        ),
      ]);
}
