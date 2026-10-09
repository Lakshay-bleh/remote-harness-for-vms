import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../composer/chat_composer.dart';
import 'approval_card.dart';
import 'assistant_api.dart';
import 'chat_meta_store.dart';
import 'chat_state.dart';
import 'conversation.dart';
import 'conversations.dart';
import 'machine_sheet.dart';

const suggestions = [
  'What can you help me with?',
  'Check my latest deployments and tell me if anything is wrong',
  'Look at the errors from the last day and find the cause',
  'Fix the failing build in my repository',
];

/// The Escanor assistant: one conversation at a time, the chats in the drawer.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  // Quick while the assistant is starting, then only an occasional check.
  late Loader<AssistantStatus> _status = Loader(api.assistantStatus, every: const Duration(milliseconds: 1500));
  AssistantStatus? _lastStatus;
  bool _wasReady = false;
  Loader<AssistantCapabilities>? _caps;
  late final Conversation _chat;
  final _scroll = ScrollController();
  int _seenBlocks = -1;
  bool _seenRunning = false;
  Timer? _slowCheck;
  // When this phone first saw the current turn working: older servers say nothing about progress, so time counts from here.
  int? _seenSince;

  @override
  void initState() {
    super.initState();
    _status.addListener(_onStatus);
    _chat = Conversation(id: ref.read(navProvider).conversationId, onCreated: _created);
    _chat.addListener(_changed);
  }

  void _created(String id) {
    ref.read(navProvider.notifier).setConversation(id);
    ref.read(conversationsProvider.notifier).reload();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onStatus() {
    final s = _status.data;
    if (s != null) _lastStatus = s;
    if (s != null && s.ready && !_wasReady) {
      _wasReady = true;
      // Not from inside the loader's own notification: it is replaced.
      scheduleMicrotask(_slowDown);
    }
    _changed();
  }

  /// Ready: from now on an occasional check is enough, and what the assistant can reach is worth knowing.
  void _slowDown() {
    if (!mounted) return;
    final old = _status;
    old.removeListener(_onStatus);
    _status = Loader(api.assistantStatus, every: const Duration(seconds: 30), start: false)..addListener(_onStatus);
    old.dispose();
    _slowCheck = Timer(const Duration(seconds: 30), () {
      if (mounted) _status.reload();
    });
    _caps ??= Loader(() => api.assistantCapabilities(), every: const Duration(seconds: 30))..addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _slowCheck?.cancel();
    _status.removeListener(_onStatus);
    _status.dispose();
    _caps?.removeListener(_changed);
    _caps?.dispose();
    _chat.removeListener(_changed);
    _chat.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followNewest(List<DisplayBlock> blocks) {
    if (blocks.length == _seenBlocks && _chat.state.running == _seenRunning) return;
    final first = _seenBlocks < 0;
    _seenBlocks = blocks.length;
    _seenRunning = _chat.state.running;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (first || MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navProvider.select((n) => n.conversationId), (_, next) => _chat.open(next));
    final c = context.c;
    final status = _status.data ?? _lastStatus;
    final ready = status?.ready == true;

    if (_status.loading && status == null) return const Center(child: Spinner());
    if (!ready) {
      return _Setup(message: status?.message ?? _status.error ?? 'Getting your assistant ready…', state: status?.state);
    }

    final meta = ref.watch(chatMetaProvider);
    final list = ref.watch(conversationsProvider).list;
    final title = chatName(_chat.id, meta, list) ?? 'New chat';
    final caps = _caps?.data;
    final usable = (caps?.integrations ?? const <CapabilityIntegration>[]).where((i) => i.availableToAssistant == true).toList();
    final blocks = toDisplay(_chat.state);
    _followNewest(blocks);
    // While a turn runs: what it is doing and for how long, ticking every second.
    final working = _chat.state.running && _chat.state.pending == 0;
    if (!working) {
      _seenSince = null;
    } else {
      _seenSince ??= DateTime.now().millisecondsSinceEpoch;
    }
    final seenSince = _seenSince;
    final phone = MediaQuery.sizeOf(context).width < 768;
    final machineState = caps?.machineState ?? 'unknown';

    return Column(children: [
      ValueListenableBuilder<VoidCallback?>(
        valueListenable: openChatDrawer,
        builder: (context, open, _) => ScreenHeader(
          title: title,
          onMenu: phone && open != null
              ? () {
                  haptic();
                  openChatDrawer.value?.call();
                }
              : null,
          actions: [
            Semantics(
              button: true,
              label: 'Machine',
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.pill),
                onTap: () => showMachineSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: machineTone(c, machineState), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(machineLabel(machineState).split(',').first, style: TextStyle(fontSize: 12, color: c.body)),
                  ]),
                ),
              ),
            ),
            IconButton(
              tooltip: 'New chat',
              onPressed: () {
                haptic();
                ref.read(navProvider.notifier).openChat(null);
              },
              icon: Icon(Icons.edit_square, size: 20, color: c.body),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          children: [
            if (blocks.isEmpty) _Intro(onPick: (s) => _chat.send(s)),
            for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: 16), child: _Block(key: ValueKey(b.key), block: b, chat: _chat)),
            if (working)
              ThinkingLine(
                label: (now) => _chat.stopping
                    ? 'Stopping…'
                    : thinkingLabel(_chat.state.progress, math.max(now, seenSince ?? 0), seenSince),
              ),
          ],
        ),
      ),
      if (_chat.error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Notice(_chat.error!, tone: NoticeTone.error)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (usable.isNotEmpty)
            InkWell(
              onTap: () => ref.read(navProvider.notifier).go(AppTab.connections),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Connected:', style: TextStyle(fontSize: 12, color: c.muted)),
                  for (final i in usable.take(5))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(Radii.pill)),
                      child: Text(i.name, style: TextStyle(fontSize: 12, color: c.body)),
                    ),
                  if (usable.length > 5) Text('+${usable.length - 5}', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            )
          else if (caps != null)
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => ref.read(navProvider.notifier).go(AppTab.connections),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Connect a service so I can work on it',
                      style: TextStyle(fontSize: 12, color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary)),
                ),
              ),
            ),
          ChatComposer(
            placeholder: 'Message your assistant',
            running: _chat.state.running,
            stopping: _chat.stopping,
            sendWhileRunning: _chat.canSend,
            onSend: (t, files) => _chat.send(t, files),
            onStop: _chat.stop,
          ),
        ]),
      ),
    ]);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});
  final void Function(String) onPick;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('What should we work on?', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, color: c.ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Text('Ask in your own words. I’ll ask before I change anything.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.muted)),
            const SizedBox(height: 20),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  shape: StadiumBorder(side: BorderSide(color: c.hairline)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      haptic();
                      onPick(s);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(s, style: TextStyle(fontSize: 14, color: c.body)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.block, required this.chat});
  final DisplayBlock block;
  final Conversation chat;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = block;
    switch (b.type) {
      case BlockType.approval:
        return ApprovalCard(item: b.item!, onAnswer: (allow) => chat.answer(b.item!.requestId, allow));
      case BlockType.user:
        return Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.85,
            alignment: Alignment.centerRight,
            child: Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: b.optimistic ? 0.7 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surfaceCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: SelectableText(b.text, style: TextStyle(fontSize: 15, height: 1.5, color: c.ink)),
                ),
              ),
            ),
          ),
        );
      case BlockType.assistant:
        return FractionallySizedBox(widthFactor: 0.92, alignment: Alignment.centerLeft, child: Md(b.text));
      case BlockType.error:
        return Notice(b.text, tone: NoticeTone.error);
      case BlockType.activity:
        return _Activity(text: b.text, live: b.live);
      case BlockType.notice:
        // A quiet line about the turn itself: "Stopped.", or "X wasn't available, so Y is answering".
        return Text(b.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.mutedSoft));
    }
  }
}

/// The line under the chat while the assistant works: the dog, then [label] for the current time (ms), redrawn every second.
class ThinkingLine extends StatefulWidget {
  const ThinkingLine({super.key, required this.label});
  final String Function(int nowMs) label;
  @override
  State<ThinkingLine> createState() => _ThinkingLineState();
}

class _ThinkingLineState extends State<ThinkingLine> {
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
    return Semantics(
      liveRegion: true,
      child: Row(children: [
        const Spinner(size: 24),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.label(DateTime.now().millisecondsSinceEpoch), style: TextStyle(fontSize: 13, color: c.muted))),
      ]),
    );
  }
}

class _Activity extends StatefulWidget {
  const _Activity({required this.text, required this.live});
  final String text;
  final bool live;
  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000), lowerBound: 0.5, upperBound: 1, value: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Activity old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.live && !still) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FadeTransition(
      opacity: _pulse,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (widget.live) const Spinner(size: 24) else Text('•', style: TextStyle(fontSize: 13, color: c.mutedSoft)),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.text, style: TextStyle(fontSize: 13, color: c.muted))),
      ]),
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.message, this.state});
  final String message;
  final String? state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stuck = state == 'error' || state == 'not_configured';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!stuck) const Padding(padding: EdgeInsets.only(bottom: 12), child: Spinner()),
            Text(stuck ? 'Your assistant isn’t available yet' : 'Getting your assistant ready',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 24, color: c.ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.muted)),
            if (!stuck) ...[
              const SizedBox(height: 12),
              Text('This happens once, and takes a few seconds.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.mutedSoft)),
            ],
          ]),
        ),
      ),
    );
  }
}
