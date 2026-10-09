import 'dart:async';

import 'package:flutter/material.dart';

import '../core/prefs.dart' show haptic;
import '../core/theme.dart';
import '../features/companion/dog_spinner.dart';
import '../features/companion/dog_state.dart';
import '../features/machines/hub_markdown.dart';
import 'widgets.dart';

/// The pieces every chat in the app is drawn with: Escanor AI, a chat with Claude on a server, and a chat with a computer
/// running Escanor Desktop. One look, so moving between them never feels like another app: a header with where the chat runs,
/// your words in a bubble on the right, the answer as rich text, steps as quiet lines, one working line with the dog and the
/// time, a question that needs you pinned above the message box, and the message box with its choices as chips.

/// The chat's title bar: the chat's name, then a dot and where it runs ("Escanor · Ready", "build-box · ~/app").
class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key, required this.title, this.place, this.dot, this.onPlaceTap, this.onBack, this.onMenu, this.actions = const []});
  final String title;

  /// Where the chat runs, under the title.
  final String? place;

  /// The colour of the dot before [place]: is that place up?
  final Color? dot;
  final VoidCallback? onPlaceTap;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final where = place;
    Widget? sub;
    if (where != null && where.isNotEmpty) {
      sub = Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) Padding(padding: const EdgeInsets.only(right: 6), child: Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))),
        Flexible(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted))),
        if (onPlaceTap != null) Icon(Icons.expand_more_rounded, size: 14, color: c.muted),
      ]);
      if (onPlaceTap != null) {
        sub = Semantics(
          button: true,
          child: InkWell(borderRadius: BorderRadius.circular(Radii.pill), onTap: onPlaceTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: sub)),
        );
      }
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: c.canvas, border: Border(bottom: BorderSide(color: c.hairline))),
      child: Row(children: [
        if (onBack != null)
          IconButton(onPressed: onBack, tooltip: 'Back', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.body))
        else if (onMenu != null)
          IconButton(onPressed: onMenu, tooltip: 'Chats', icon: Icon(Icons.menu_rounded, size: 22, color: c.body))
        else
          const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, height: 1.25, color: c.ink, fontWeight: FontWeight.w500)),
            ?sub,
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// The messages, newest at the bottom. Drawn from the bottom up, so new output shows without scrolling and an open chat starts at
/// its latest message. [children] are in reading order (oldest first).
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({super.key, required this.children, this.empty});
  final List<Widget> children;

  /// What an empty chat shows instead, centred.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty && empty != null) {
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight), child: Center(child: empty)),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: children.length,
      itemBuilder: (context, i) => children[children.length - 1 - i],
    );
  }
}

/// The space between two messages.
const chatGap = 14.0;

/// What you said: a bubble on the right.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text, this.optimistic = false, this.note, this.media = const []});
  final String text;

  /// Not on the server yet: shown a little faded.
  final bool optimistic;

  /// A quiet line under the words ("Attached: notes.txt").
  final String? note;

  /// Photos sent with it.
  final List<Widget> media;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Opacity(
          opacity: optimistic ? 0.7 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              ...media,
              if (text.isNotEmpty) SelectableText(text, style: TextStyle(fontSize: 15, height: 1.5, color: c.ink)),
              if (note != null && note!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: TextStyle(fontSize: 12, color: c.muted))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The answer: rich text across the screen, code highlighted. Untrusted output: remote images are never fetched and only
/// http(s) links open (see [HubMarkdown]).
class AnswerText extends StatelessWidget {
  const AnswerText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => HubMarkdown(text);
}

enum StepTone { live, done, failed, quiet }

/// One step of the work ("Searching the web", "Read 3 files"): a dot that says how it went, then the words.
class StepDot extends StatefulWidget {
  const StepDot(this.state, {super.key, this.size = 13});
  final StepTone state;
  final double size;
  @override
  State<StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<StepDot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (widget.state) { StepTone.done => c.success, StepTone.failed => c.error, StepTone.live => c.primary, StepTone.quiet => c.mutedSoft };
    final dot = Text('●', style: TextStyle(fontSize: widget.size, height: 1.5, color: color));
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.state == StepTone.live && !still) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
      return SizedBox(width: 20, child: FadeTransition(opacity: Tween(begin: 1.0, end: 0.25).animate(_blink), child: dot));
    }
    if (_blink.isAnimating) _blink.stop();
    return SizedBox(width: 20, child: dot);
  }
}

class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.text, this.state = StepTone.quiet});
  final String text;
  final StepTone state;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StepDot(state),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: state == StepTone.failed ? c.error : c.muted))),
    ]);
  }
}

/// A quiet line about the chat itself ("Stopped.", "Model A wasn’t available, so Model B is answering").
class ChatNote extends StatelessWidget {
  const ChatNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.5, color: context.c.mutedSoft));
}

/// Whole seconds as "12s", "3m 05s", "1h 02m".
String elapsedText(int secs) {
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  if (m < 60) return '${m}m ${(secs % 60).toString().padLeft(2, '0')}s';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// While it works: the dog, what it is doing, and for how long, redrawn every second. Every chat uses this one line, so a slow
/// answer never looks like a frozen app.
class WorkingLine extends StatefulWidget {
  const WorkingLine({super.key, required this.text, this.startedAtMs, this.extra, this.slowHint});

  /// What it is doing ("Asking Gemini · step 2", "Running the tests"). An ellipsis is added.
  final String text;

  /// Since when (ms since epoch); null shows no time.
  final int? startedAtMs;

  /// More, after the time ("thinking", "3 rounds").
  final String? extra;

  /// Said under the line once it has taken 20 seconds.
  final String? slowHint;

  @override
  State<WorkingLine> createState() => _WorkingLineState();
}

class _WorkingLineState extends State<WorkingLine> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _tick; // start ticking
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final start = widget.startedAtMs;
    final secs = start == null ? null : ((DateTime.now().millisecondsSinceEpoch - start) ~/ 1000).clamp(0, 1 << 31);
    final what = widget.text.trim().replaceAll(RegExp(r'[.…]+$'), '');
    final after = [if (secs != null) elapsedText(secs), if (widget.extra != null && widget.extra!.isNotEmpty) widget.extra!].join(' · ');
    return Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Padding(padding: EdgeInsets.only(right: 8), child: DogSpinner(size: 28)),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${what.isEmpty ? 'Thinking' : what}…', style: TextStyle(color: c.primary, fontWeight: FontWeight.w500)),
                if (after.isNotEmpty) TextSpan(text: '  $after', style: TextStyle(color: c.mutedSoft)),
              ]),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ]),
        if (widget.slowHint != null && secs != null && secs >= 20)
          Padding(padding: const EdgeInsets.only(left: 36, top: 2), child: Text(widget.slowHint!, style: TextStyle(fontSize: 12, color: c.muted))),
      ]),
    );
  }
}

/// A question that needs you ("Run a command?"), pinned above the message box so it is never scrolled away. Plain words first,
/// what exactly will happen underneath, then Continue or Don’t do this.
class ApprovalPanel extends StatefulWidget {
  const ApprovalPanel({
    super.key,
    required this.title,
    required this.onAnswer,
    this.subtitle,
    this.question,
    this.details,
    this.detailsOpen = false,
    this.high = false,
    this.answered,
  });

  final String title;
  final String? subtitle;

  /// Asked just above the buttons ("Do you want to proceed?").
  final String? question;

  /// What exactly will happen: a command, an edit, a file.
  final Widget? details;

  /// Show [details] at once (when they are the question) instead of behind "Show details".
  final bool detailsOpen;

  /// Something that cannot be taken back.
  final bool high;

  /// What was said, once it was ("You said continue."). Null while it waits.
  final String? answered;

  /// Throws when the answer did not arrive: the buttons come back.
  final FutureOr<void> Function(bool allow) onAnswer;

  @override
  State<ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends State<ApprovalPanel> {
  late bool _details = widget.detailsOpen;
  bool? _busy;

  Future<void> _respond(bool allow) async {
    haptic();
    setState(() => _busy = allow);
    try {
      await widget.onAnswer(allow);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tone = widget.high ? c.error : c.permission;
    final details = widget.details;
    return Semantics(
      container: true,
      label: 'Permission needed',
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(tone.withValues(alpha: 0.05), c.canvas),
          border: Border.all(color: tone.withValues(alpha: widget.high ? 0.45 : 0.35)),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text((widget.high ? 'Needs your care' : 'Needs your OK').toUpperCase(),
                style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: tone)),
            const SizedBox(height: 4),
            Text(widget.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(widget.subtitle!, style: TextStyle(fontSize: 14, color: c.body))),
            if (details != null) ...[
              if (!widget.detailsOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _details = !_details),
                    child: Text(_details ? 'Hide details' : 'Show details',
                        style: TextStyle(fontSize: 12, color: c.muted, decoration: TextDecoration.underline, decorationColor: c.muted)),
                  ),
                ),
              if (_details) Padding(padding: const EdgeInsets.only(top: 8), child: details),
            ],
            if (widget.answered != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(widget.answered!, style: TextStyle(fontSize: 14, color: c.muted)))
            else ...[
              if (widget.question != null && widget.question!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(widget.question!, style: TextStyle(fontSize: 14, color: c.ink))),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                EButton(label: 'Continue', onPressed: _busy != null ? null : () => _respond(true)),
                EButton(label: 'Don’t do this', kind: ButtonKind.quiet, onPressed: _busy != null ? null : () => _respond(false)),
                if (_busy != null) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Raw details in a code box (a command, the exact request).
class DetailsBox extends StatelessWidget {
  const DetailsBox(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 192),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.md)),
      child: SingleChildScrollView(child: SelectableText(text, style: TextStyle(fontFamily: monoFamily, fontSize: 12, color: c.onCode))),
    );
  }
}

/// A chat with nothing in it yet: the dog, what this chat is for, and a few things to start with.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.title, this.text, this.scene = 'sit', this.suggestions = const [], this.onPick});
  final String title;
  final String? text;
  final String scene;
  final List<String> suggestions;

  /// Null when nothing can be sent right now (offline, still working): the suggestions are shown but do nothing.
  final void Function(String text)? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 448),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DogState(scene: scene, scale: 4, title: title, text: text),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Opacity(
              opacity: onPick == null ? 0.5 : 1,
              child: Material(
                color: Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: c.hairline)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPick == null
                      ? null
                      : () {
                          haptic();
                          onPick!(s);
                        },
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text(s, style: TextStyle(fontSize: 14, color: c.body))),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// Under the messages: anything to say first (an error, a question that needs you), then the message box.
class ChatBottom extends StatelessWidget {
  const ChatBottom({super.key, required this.composer, this.above = const []});
  final Widget composer;
  final List<Widget> above;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.hairline))),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final w in above) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: w),
        composer,
      ]),
    );
  }
}

/// A fact about the chat shown under the message box ("build-box"), or a button when [onTap] is given.
class ChatChip extends StatelessWidget {
  const ChatChip({super.key, required this.icon, required this.label, this.onTap, this.tooltip});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final active = onTap != null;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: active ? c.body : c.muted),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: active ? c.body : c.muted)),
        ),
        if (active) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 14, color: c.body)],
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: active
          ? Tooltip(
              message: tooltip ?? label,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.pill),
                onTap: () {
                  haptic();
                  onTap!();
                },
                child: chip,
              ),
            )
          : chip,
    );
  }
}

/// A choice for the chat (model, folder, permission mode) under the message box.
class ChatDropdownChip extends StatelessWidget {
  const ChatDropdownChip({super.key, required this.icon, required this.title, required this.value, required this.options, required this.onChanged});
  final IconData icon;
  final String title;
  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var current = value;
    for (final o in options) {
      if (o.value == value) current = o.label;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PopupMenuButton<String>(
        tooltip: title,
        initialValue: value,
        onSelected: (v) {
          haptic();
          onChanged(v);
        },
        color: c.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.hairline)),
        position: PopupMenuPosition.over,
        itemBuilder: (_) => [
          for (final o in options)
            PopupMenuItem<String>(
              value: o.value,
              height: 40,
              child: Text(o.label,
                  style: TextStyle(fontSize: 13, color: o.value == value ? c.primary : c.body, fontWeight: o.value == value ? FontWeight.w500 : FontWeight.w400)),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: c.body),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(current, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.body)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: c.body),
          ]),
        ),
      ),
    );
  }
}

/// A row of chips that scrolls sideways when they do not fit.
class ChatChips extends StatelessWidget {
  const ChatChips({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children));
}
