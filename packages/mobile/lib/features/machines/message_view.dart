import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/chat_parts.dart';
import 'autonomy.dart' show roundsText;
import 'diff.dart';
import 'group_messages.dart';
import 'message_format.dart';

/// One item of a machine chat, drawn like the Claude Code CLI draws it (Message.tsx).

TextStyle monoStyle(BuildContext context) => TextStyle(fontFamily: monoFamily, fontSize: 12.5, height: 1.55, color: context.c.muted);

/// The session's folder, so paths show relative to it like the CLI does.
class CwdScope extends InheritedWidget {
  const CwdScope({super.key, required this.cwd, required super.child});
  final String cwd;
  static String of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CwdScope>()?.cwd ?? '';
  @override
  bool updateShouldNotify(CwdScope oldWidget) => cwd != oldWidget.cwd;
}

/// The ⎿ connector: dim, and the content hangs to its right.
class _Response extends StatelessWidget {
  const _Response({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final mono = monoStyle(context);
    return DefaultTextStyle.merge(
      style: mono,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, child: Text(' ⎿ ', style: mono.copyWith(color: context.c.mutedSoft))),
        Expanded(child: child),
      ]),
    );
  }
}

enum DotState { pending, ok, error, plain }

class _Dot extends StatefulWidget {
  const _Dot(this.state);
  final DotState state;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (widget.state) { DotState.ok => c.success, DotState.error => c.error, DotState.plain => c.ink, DotState.pending => c.muted };
    final dot = Text('●', style: monoStyle(context).copyWith(color: color));
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.state == DotState.pending && !still) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
      return SizedBox(width: 20, child: FadeTransition(opacity: Tween(begin: 1.0, end: 0.2).animate(_blink), child: dot));
    }
    if (_blink.isAnimating) _blink.stop();
    return SizedBox(width: 20, child: dot);
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text, this.error = false, this.limit = 3});
  final String text;
  final bool error;
  final int limit;
  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lines = widget.text.replaceAll(RegExp(r'\s+$'), '').split('\n');
    final hidden = lines.length - widget.limit;
    final shown = _open || hidden <= 0 ? lines : lines.take(widget.limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText(shown.join('\n'), style: monoStyle(context).copyWith(color: widget.error ? c.error : c.body)),
      if (hidden > 0)
        _Tap(
          onTap: () => setState(() => _open = !_open),
          text: _open ? 'collapse' : '… +$hidden ${hidden == 1 ? 'line' : 'lines'} (tap to expand)',
        ),
    ]);
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.text});
  final VoidCallback onTap;
  final String text;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(text, style: monoStyle(context).copyWith(color: context.c.mutedSoft)),
        ),
      );
}

class _ExpandInline extends StatefulWidget {
  const _ExpandInline({required this.summary, required this.text, this.label = 'output'});
  final Widget summary;
  final String text;
  final String label;
  @override
  State<_ExpandInline> createState() => _ExpandInlineState();
}

class _ExpandInlineState extends State<_ExpandInline> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        widget.summary,
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('(${_open ? 'collapse' : 'tap to expand ${widget.label}'})', style: monoStyle(context).copyWith(color: c.mutedSoft)),
          ),
        ),
      ]),
      if (_open) SelectableText(widget.text.trim(), style: monoStyle(context).copyWith(color: c.body)),
    ]);
  }
}

/// Bold numbers inside a summary line ("Read **12** lines").
Widget _summary(BuildContext context, String text) {
  final c = context.c;
  final spans = <TextSpan>[];
  text.splitMapJoin(RegExp(r'\d+'), onMatch: (m) {
    spans.add(TextSpan(text: m[0], style: TextStyle(fontWeight: FontWeight.w600, color: c.bodyStrong)));
    return '';
  }, onNonMatch: (s) {
    spans.add(TextSpan(text: s));
    return '';
  });
  return Text.rich(TextSpan(children: spans), style: monoStyle(context));
}

/// An edit as removed/added lines.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.name, required this.input});
  final String name;
  final Map<String, dynamic> input;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mono = monoStyle(context);
    final lines = editDiff(name, input);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(color: c.surfaceSoft, border: Border.all(color: c.hairlineSoft), borderRadius: BorderRadius.circular(Radii.xs)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in lines)
              Container(
                color: switch (l.type) { DiffType.add => c.success.withValues(alpha: 0.2), DiffType.del => c.error.withValues(alpha: 0.15), DiffType.ctx => null },
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  SizedBox(
                    width: 16,
                    child: Text(switch (l.type) { DiffType.add => '+', DiffType.del => '-', DiffType.ctx => ' ' }, style: mono.copyWith(color: c.mutedSoft)),
                  ),
                  Text(l.text.isEmpty ? ' ' : l.text, softWrap: false, style: mono.copyWith(color: l.type == DiffType.ctx ? c.muted : c.bodyStrong)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The first lines of a file being written.
class WritePreview extends StatefulWidget {
  const WritePreview({super.key, required this.content});
  final String content;
  @override
  State<WritePreview> createState() => _WritePreviewState();
}

class _WritePreviewState extends State<WritePreview> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lines = widget.content.split('\n');
    final shown = _open ? lines : lines.take(10).toList();
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.surfaceSoft, border: Border.all(color: c.hairlineSoft), borderRadius: BorderRadius.circular(Radii.xs)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(shown.join('\n'), softWrap: false, style: monoStyle(context).copyWith(color: c.body)),
        ),
        if (lines.length > 10)
          _Tap(onTap: () => setState(() => _open = !_open), text: _open ? 'collapse' : '… +${lines.length - 10} lines (tap to expand)'),
      ]),
    );
  }
}

class _ToolResultBody extends StatelessWidget {
  const _ToolResultBody({required this.tool});
  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = tool.result;
    if (r == null) return const SizedBox.shrink();
    final cwd = CwdScope.of(context);
    final text = r.text;
    final name = tool.name;
    final input = tool.input;
    if (isRejected(text)) {
      return _Response(child: Text('Interrupted · What should Claude do instead?', style: TextStyle(color: c.mutedSoft)));
    }
    if (r.isError) return _Response(child: _Expandable(text: toolErrorText(text), error: true, limit: 10));
    switch (name) {
      case 'Edit':
      case 'MultiEdit':
        return _Response(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _summary(context, editSummaryText(name, input)),
            DiffView(name: name, input: input),
          ]),
        );
      case 'Write':
        final n = '${input['content'] ?? ''}'.split('\n').length;
        return _Response(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Wrote '),
              TextSpan(text: '$n', style: TextStyle(fontWeight: FontWeight.w600, color: c.bodyStrong)),
              TextSpan(text: ' ${n == 1 ? 'line' : 'lines'} to '),
              TextSpan(text: displayPath(input['file_path'], cwd), style: TextStyle(fontWeight: FontWeight.w600, color: c.bodyStrong)),
            ]), style: monoStyle(context)),
            WritePreview(content: '${input['content'] ?? ''}'),
          ]),
        );
      case 'WebSearch':
        return _Response(child: _Expandable(text: text));
    }
    final s = resultSummary(tool, cwd);
    if (s != null) {
      final line = _summary(context, s.text);
      return _Response(child: s.expandable ? _ExpandInline(summary: line, text: text, label: s.expandLabel ?? 'output') : line);
    }
    if (text.trim().isEmpty) return _Response(child: Text(name == 'Bash' ? '(No output)' : 'Done', style: TextStyle(color: c.mutedSoft)));
    return _Response(child: _Expandable(text: text));
  }
}

class _SubActivity extends StatelessWidget {
  const _SubActivity({required this.tool});
  final ToolItem tool;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cwd = CwdScope.of(context);
    final running = tool.result == null;
    if (tool.sub.isEmpty) return running ? _Response(child: Text('Initializing…', style: TextStyle(color: c.mutedSoft))) : const SizedBox.shrink();
    if (!running) return const SizedBox.shrink();
    final shown = tool.sub.length > 3 ? tool.sub.sublist(tool.sub.length - 3) : tool.sub;
    final hidden = tool.sub.length - shown.length;
    return _Response(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in shown)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: toolName('${s['name'] ?? ''}', asMap(s['input'])), style: TextStyle(fontWeight: FontWeight.w600, color: c.bodyStrong)),
              TextSpan(text: '(${toolArgs('${s['name'] ?? ''}', asMap(s['input']), cwd)})'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (hidden > 0) Text('+$hidden more tool uses', style: TextStyle(color: c.mutedSoft)),
      ]),
    );
  }
}

class ToolUseView extends StatelessWidget {
  const ToolUseView({super.key, required this.tool, this.waitingForPermission = false, this.live = false});
  final ToolItem tool;
  final bool waitingForPermission;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cwd = CwdScope.of(context);
    final r = tool.result;
    final state = r != null ? (r.isError || isRejected(r.text) ? DotState.error : DotState.ok) : DotState.pending;
    final server = mcpServer(tool.name);
    final args = toolArgs(tool.name, tool.input, cwd);
    final mono = monoStyle(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Dot(state == DotState.pending && !live ? DotState.plain : state),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: toolName(tool.name, tool.input), style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
              if (args.isNotEmpty) TextSpan(text: '($args)', style: TextStyle(color: c.body)),
              if (server != null) TextSpan(text: ' ($server MCP)', style: TextStyle(color: c.mutedSoft)),
            ]), style: mono),
          ),
        ]),
        if (r == null && waitingForPermission) _Response(child: Text('Waiting for permission…', style: TextStyle(color: c.mutedSoft))),
        if (r == null && !waitingForPermission && tool.name == 'Bash' && live) _Response(child: Text('Running…', style: TextStyle(color: c.mutedSoft))),
        if (tool.name == 'Task' || tool.name == 'Agent') _SubActivity(tool: tool),
        _ToolResultBody(tool: tool),
      ]),
    );
  }
}

/// Consecutive Read/Grep/Glob calls: "Searched for 2 patterns, read 3 files".
class _CollapsedGroup extends StatefulWidget {
  const _CollapsedGroup({required this.tools, required this.live});
  final List<ToolItem> tools;
  final bool live;
  @override
  State<_CollapsedGroup> createState() => _CollapsedGroupState();
}

class _CollapsedGroupState extends State<_CollapsedGroup> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cwd = CwdScope.of(context);
    final active = widget.live && widget.tools.any((t) => t.result == null);
    final last = widget.tools.last;
    final mono = monoStyle(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            active ? const _Dot(DotState.pending) : const SizedBox(width: 20),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${groupSummary(widget.tools, active)} '),
                TextSpan(text: '(${_open ? 'tap to collapse' : 'tap to expand'})', style: TextStyle(color: c.mutedSoft)),
              ]), style: mono.copyWith(color: active ? c.ink : c.muted)),
            ),
          ]),
        ),
        if (active && !_open)
          _Response(
            child: Text(
              last.name == 'Read' ? displayPath(last.input['file_path'], cwd) : '"${last.input['pattern']}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.mutedSoft),
            ),
          ),
        if (_open) for (final t in widget.tools) ToolUseView(key: ValueKey(t.key), tool: t, live: widget.live),
      ]),
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking({required this.text});
  final String text;
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mono = monoStyle(context).copyWith(fontStyle: FontStyle.italic, color: c.mutedSoft);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(onTap: () => setState(() => _open = !_open), child: Text('∴ Thinking${_open ? '…' : ' (tap to expand)'}', style: mono)),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: SelectableText(widget.text, style: mono.copyWith(fontStyle: FontStyle.normal, color: c.muted, height: 1.6)),
          ),
      ]),
    );
  }
}

/// "Pondering… 12s · thinking" while a turn runs: the line every chat shows while it works.
class BusySpinner extends StatefulWidget {
  const BusySpinner({super.key, required this.startedAt, required this.thinking, this.task, this.rounds = 0});
  final int startedAt;
  final bool thinking;
  final String? task;

  /// How many times it has been told to keep going on its own (autonomous chats).
  final int rounds;
  @override
  State<BusySpinner> createState() => _BusySpinnerState();
}

class _BusySpinnerState extends State<BusySpinner> {
  final String _verb = spinnerVerbs[Random().nextInt(spinnerVerbs.length)];

  @override
  Widget build(BuildContext context) {
    final extra = [if (widget.thinking) 'thinking', if (widget.rounds > 0) roundsText(widget.rounds)].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: WorkingLine(text: widget.task ?? _verb, startedAtMs: widget.startedAt, extra: extra.isEmpty ? null : extra),
    );
  }
}

class TodoListView extends StatelessWidget {
  const TodoListView({super.key, required this.todos});
  final List<Todo> todos;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = todos.where((t) => t.status == 'completed').length;
    final doing = todos.where((t) => t.status == 'in_progress').length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _Response(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('${plural(todos.length, 'task')} ($done done, $doing in progress, ${todos.length - done - doing} open)',
                style: TextStyle(color: c.mutedSoft)),
          ),
          for (final t in todos)
            Text.rich(TextSpan(children: [
              TextSpan(
                text: '${t.status == 'completed' ? '✔' : t.status == 'in_progress' ? '◼' : '◻'} ',
                style: TextStyle(
                  decoration: TextDecoration.none,
                  color: t.status == 'completed' ? c.success : t.status == 'in_progress' ? c.primary : c.body,
                ),
              ),
              TextSpan(
                text: t.content,
                style: t.status == 'completed'
                    ? TextStyle(color: c.mutedSoft, decoration: TextDecoration.lineThrough, decorationColor: c.mutedSoft)
                    : t.status == 'in_progress'
                        ? TextStyle(fontWeight: FontWeight.w600, color: c.ink)
                        : TextStyle(color: c.body),
              ),
            ])),
        ]),
      ),
    );
  }
}

/// The permission prompt, pinned above the message box: the same question card every chat uses, with exactly what will run
/// (the command, the edit, the file) shown at once.
class PermissionPanel extends StatelessWidget {
  const PermissionPanel({super.key, required this.toolName, required this.input, required this.onAnswer, this.resolved = false});
  final String toolName;
  final Map<String, dynamic> input;
  final bool resolved;

  /// 'allow' or 'deny'. Throws when the answer did not reach the machine.
  final Future<void> Function(String behavior) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cwd = CwdScope.of(context);
    final name = toolName;
    final isEdit = name == 'Edit' || name == 'MultiEdit';
    final target = displayPath(input['file_path'] ?? input['notebook_path'], cwd);
    final mono = monoStyle(context);
    Widget detail;
    if (isEdit) {
      detail = DiffView(name: name, input: input);
    } else if (name == 'Bash') {
      detail = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ('${input['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${input['description']}', style: TextStyle(fontSize: 14, color: c.body))),
        DetailsBox('${input['command'] ?? ''}'),
      ]);
    } else if (name == 'Write') {
      detail = WritePreview(content: '${input['content'] ?? ''}');
    } else {
      final args = toolArgs(name, input, cwd);
      detail = SelectableText('${_toolLabel(name, input)}(${args.isNotEmpty ? args : jsonEncode(input)})', style: mono.copyWith(color: c.body));
    }
    return ApprovalPanel(
      title: permissionTitle(name),
      subtitle: target,
      details: detail,
      detailsOpen: true,
      question: permissionQuestion(name, target),
      answered: resolved ? 'Resolved' : null,
      onAnswer: (allow) => onAnswer(allow ? 'allow' : 'deny'),
    );
  }
}

/// The tool's name as shown (the widget's own `toolName` field hides the function inside it).
String _toolLabel(String name, Map<String, dynamic> input) => toolName(name, input);

/// One display item.
class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.item, required this.live, required this.waitingForPermission});
  final DisplayItem item;
  final bool live;
  final bool waitingForPermission;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mono = monoStyle(context);
    final it = item;
    switch (it) {
      case UserItem():
        final text = [for (final b in it.blocks) if (b['type'] == 'text') '${b['text'] ?? ''}'].join('\n\n');
        return Padding(
          padding: const EdgeInsets.only(top: chatGap),
          child: UserBubble(text: text, media: [for (final b in it.blocks) if (b['type'] != 'text') _ImageBlock(block: b)]),
        );
      case TextItem():
        return Padding(padding: const EdgeInsets.only(top: 10), child: AnswerText(it.text));
      case ThinkingItem():
        return _Thinking(text: it.text);
      case ToolItem():
        return ToolUseView(tool: it, live: live, waitingForPermission: waitingForPermission && it.result == null);
      case GroupItem():
        return _CollapsedGroup(tools: it.tools, live: live);
      case TurnEndItem():
        final t = turnEndText(it.data);
        if (t == null) return const SizedBox.shrink();
        if (t.response) {
          return Padding(padding: const EdgeInsets.only(top: 10), child: _Response(child: Text(t.text, style: TextStyle(color: c.mutedSoft))));
        }
        return Padding(padding: const EdgeInsets.only(top: 10), child: Text(t.text, style: mono.copyWith(color: c.mutedSoft)));
      case SystemItem():
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('✻ ${it.text}', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 11, color: c.mutedSoft)),
        );
      case ErrorItem():
        return Padding(padding: const EdgeInsets.only(top: 10), child: _Response(child: Text(it.text, style: TextStyle(color: c.error))));
      case PermissionItem():
        // drawn as the panel above the message box instead
        return const SizedBox.shrink();
    }
  }
}

class _ImageBlock extends StatefulWidget {
  const _ImageBlock({required this.block});
  final Map<String, dynamic> block;
  @override
  State<_ImageBlock> createState() => _ImageBlockState();
}

class _ImageBlockState extends State<_ImageBlock> {
  Uint8List? _bytes;
  Object? _source;

  Uint8List? _decode() {
    final data = asMap(widget.block['source'])['data'];
    if (identical(data, _source)) return _bytes;
    _source = data;
    try {
      _bytes = data is String && data.isNotEmpty ? base64Decode(data) : null;
    } catch (_) {
      _bytes = null;
    }
    return _bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode();
    if (bytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 256),
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
    );
  }
}
