import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/chat_parts.dart';
import '../../ui/widgets.dart';
import '../companion/companion_floor.dart';
import '../composer/chat_composer.dart';
import 'approval_card.dart';
import 'assistant_api.dart';
import 'chat_meta_store.dart';
import 'chat_state.dart';
import 'conversation.dart';
import 'conversations.dart';
import 'machine_sheet.dart';
import 'model_choice.dart';

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
  // The models to pick from: asked once, again when the screen comes back.
  final Loader<AssistantModels> _models = Loader(() => api.assistantModels());
  Timer? _slowCheck;
  // When this phone first saw the current turn working: older servers say nothing about progress, so time counts from here.
  int? _seenSince;

  @override
  void initState() {
    super.initState();
    _status.addListener(_onStatus);
    _chat = Conversation(id: ref.read(navProvider).conversationId, onCreated: _created);
    _chat.addListener(_changed);
    _models.addListener(_changed);
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
    _models.removeListener(_changed);
    _models.dispose();
    super.dispose();
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
    final model = ref.watch(assistantModelProvider);
    _chat.model = model;
    final title = chatName(_chat.id, meta, list) ?? 'New chat';
    final caps = _caps?.data;
    final integrations = caps?.integrations ?? const <CapabilityIntegration>[];
    // Unchecked (null) counts: it is connected, and the machine reads connections live once it is up.
    final usable = integrations.where((i) => i.availableToAssistant != false && !i.needsReconnect).toList();
    final blocks = toDisplay(_chat.state);
    // While a turn runs: what it is doing and for how long, ticking every second.
    final working = _chat.state.running && _chat.state.pending == 0;
    if (!working) {
      _seenSince = null;
    } else {
      _seenSince ??= DateTime.now().millisecondsSinceEpoch;
    }
    final progress = _chat.state.progress;
    final since = progress == null ? null : DateTime.tryParse(progress.since)?.millisecondsSinceEpoch;
    final phone = MediaQuery.sizeOf(context).width < 768;
    final machineState = caps?.machineState ?? 'unknown';
    // The question that needs the person, oldest first: pinned above the message box, like on a machine.
    AssistantItem? asking;
    for (final b in blocks) {
      if (b.type == BlockType.approval && b.item!.status == 'pending') {
        asking = b.item;
        break;
      }
    }

    return Column(children: [
      ValueListenableBuilder<VoidCallback?>(
        valueListenable: openChatDrawer,
        builder: (context, open, _) => ChatHeader(
          title: title,
          place: 'Escanor · ${machineLabel(machineState).split(',').first}',
          dot: machineTone(c, machineState),
          onPlaceTap: () => showMachineSheet(context),
          onMenu: phone && open != null
              ? () {
                  haptic();
                  openChatDrawer.value?.call();
                }
              : null,
          actions: [
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
        child: ChatMessageList(
          empty: ChatEmptyState(
            title: 'What should we work on?',
            text: 'Ask in your own words. I’ll ask before I change anything.',
            suggestions: suggestions,
            onPick: (s) => _chat.send(s),
          ),
          children: [
            for (final b in blocks)
              if (!(b.type == BlockType.approval && b.item!.status == 'pending'))
                Padding(padding: const EdgeInsets.only(top: chatGap), child: _Block(key: ValueKey(b.key), block: b)),
            if (working)
              Padding(
                padding: const EdgeInsets.only(top: chatGap),
                child: WorkingLine(
                  text: _chat.stopping ? 'Stopping' : (progress?.text.trim().isNotEmpty == true ? progress!.text : 'Thinking'),
                  startedAtMs: _chat.stopping ? null : since ?? _seenSince,
                ),
              ),
          ],
        ),
      ),
      CompanionFloor(
        child: ChatBottom(
          above: [
            if (_chat.error != null) Notice(_chat.error!, tone: NoticeTone.error),
            if (asking != null) ApprovalCard(key: ValueKey(asking.requestId), item: asking, onAnswer: (allow) => _chat.answer(asking!.requestId, allow)),
          ],
          composer: ChatComposer(
            placeholder: 'Message Escanor',
            running: _chat.state.running,
            stopping: _chat.stopping,
            sendWhileRunning: _chat.canSend,
            onSend: (t, files) => _chat.send(t, files),
            onStop: _chat.stop,
            chips: ChatChips(children: [
              ChatDropdownChip(
                icon: Icons.auto_awesome_outlined,
                title: 'Model',
                value: model,
                options: modelOptions(_models.data, model),
                onChanged: (v) => ref.read(assistantModelProvider.notifier).choose(v),
              ),
              // Services connected but none the assistant can use (or all needing a reconnect) are not "nothing connected".
              if (caps != null && (usable.isNotEmpty || integrations.isEmpty))
                ChatChip(
                  icon: Icons.hub_outlined,
                  label: usable.isEmpty
                      ? 'Connect a service'
                      : usable.length == 1
                          ? usable.first.name
                          : '${usable.first.name} +${usable.length - 1}',
                  tooltip: usable.isEmpty ? 'Connect a service so I can work on it' : 'What I can work on: ${usable.map((i) => i.name).join(', ')}',
                  onTap: () => ref.read(navProvider.notifier).go(AppTab.connections),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.block});
  final DisplayBlock block;

  @override
  Widget build(BuildContext context) {
    final b = block;
    switch (b.type) {
      case BlockType.approval:
        // Answered: what was asked and what was said, as one quiet step (the open question sits above the message box).
        final item = b.item!;
        final said = item.status == 'allowed' ? 'you said continue' : 'you said no';
        return StepLine(text: '${item.title} · $said.', state: item.status == 'allowed' ? StepTone.done : StepTone.failed);
      case BlockType.user:
        return UserBubble(text: b.text, optimistic: b.optimistic);
      case BlockType.assistant:
        return AnswerText(b.text);
      case BlockType.error:
        return Notice(b.text, tone: NoticeTone.error);
      case BlockType.activity:
        return StepLine(text: b.text, state: b.live ? StepTone.live : StepTone.quiet);
      case BlockType.notice:
        return ChatNote(b.text);
    }
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
