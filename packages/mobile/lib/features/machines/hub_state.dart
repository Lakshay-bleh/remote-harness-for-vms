import 'dart:convert';

import 'protocol.dart';

/// Row ids at or above this came over the socket (the hub's own ids are far below it).
const localRowBase = 1e15;

/// A message the person just sent, shown before the hub has echoed it. Replaced by the echo.
const optimisticRowBase = 2e15;

bool isLocalRow(MessageDto m) => m.id >= localRowBase;
bool isOptimisticRow(MessageDto m) => m.id >= optimisticRowBase;

bool _truthy(Object? v) => v != null && v != false && v != '' && v != 0;

/// The words of a user message row (empty for anything else).
String _userText(MessageDto m) {
  final msg = m.message;
  if (msg is! Map || msg['type'] != 'user' || !_truthy(msg['local'])) return '';
  final inner = msg['message'];
  final content = inner is Map ? inner['content'] : null;
  if (content is String) return content.trim();
  if (content is List) {
    return content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => '${b['text'] ?? ''}').join('\n').trim();
  }
  return '';
}

bool _isUserPrompt(MessageDto m) {
  final msg = m.message;
  return msg is Map && msg['type'] == 'user' && _truthy(msg['local']);
}

/// How many prompts with these words the list already holds (what an echo of a new one is counted against).
int promptCount(List<MessageDto> rows, String text) => rows.where((r) => !isOptimisticRow(r) && _isUserPrompt(r) && _userText(r) == text).length;

/// The row to show for something the person just sent. [rows] is the chat as it stands.
MessageDto optimisticPrompt(num id, String sessionId, String vmId, String text, List<MessageDto> rows, {DateTime? now}) => MessageDto(
      id: id,
      sessionId: sessionId,
      vmId: vmId,
      createdAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
      message: {
        'type': 'user',
        'local': true,
        'optimistic': true,
        'seen': promptCount(rows, text),
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text}
          ],
        },
      },
    );

/// Drops each optimistic prompt the hub has since echoed (one more prompt with the same words than when it was sent),
/// and any that never got an echo for a long time (it did not reach the hub, so it must not keep the chat spinning).
List<MessageDto> settleOptimistic(List<MessageDto> rows, {DateTime? now}) {
  if (!rows.any(isOptimisticRow)) return rows;
  final t = (now ?? DateTime.now()).toUtc();
  final echoedByText = <String, int>{};
  final out = <MessageDto>[];
  for (final r in rows) {
    if (!isOptimisticRow(r)) {
      out.add(r);
      continue;
    }
    final text = _userText(r);
    final msg = r.message as Map;
    final seen = msg['seen'] is num ? (msg['seen'] as num).toInt() : 0;
    final already = echoedByText[text] ?? 0;
    final echoed = promptCount(rows, text) > seen + already;
    if (echoed) echoedByText[text] = already + 1;
    final sentAt = DateTime.tryParse(r.createdAt);
    final lost = sentAt != null && t.difference(sentAt) > const Duration(minutes: 3);
    if (!echoed && !lost) out.add(r);
  }
  return out;
}

/// The newest row the hub itself numbered (not one that came over the socket).
num hubTail(List<MessageDto> rows) {
  num tail = 0;
  for (final r in rows) {
    if (!isLocalRow(r) && r.id > tail) tail = r.id;
  }
  return tail;
}

/// A fresh list from the hub, with what only this phone knows kept: prompts still waiting for an answer, a prompt just
/// sent, rows that arrived over the socket while the list was on its way, and "stopped" markers for a stop the hub's
/// list does not show yet.
///
/// [newSince]: the hub rows up to this id were already on the phone before (an incremental fetch), so a socket row can only
/// match a newer one; only those are compared, which keeps a long chat cheap to refresh.
List<MessageDto> mergeFetched(List<MessageDto> existing, List<MessageDto> fetched, {num? seenLocalUpTo, num? newSince}) {
  final keep = <MessageDto>[];
  final fetchedPermissions = <String>{};
  for (final m in fetched) {
    final msg = m.message;
    if (msg is Map && msg['type'] == 'permission_request') fetchedPermissions.add('${msg['requestId']}');
  }
  String? fetchedJson;
  final lastHubPrompt = fetched.lastIndexWhere(_isUserPrompt);
  final lastHubPromptId = lastHubPrompt < 0 ? -1 : fetched[lastHubPrompt].id;
  for (final m in existing) {
    if (!isLocalRow(m) && m.id >= 0) continue;
    final msg = m.message;
    final type = msg is Map ? msg['type'] : null;
    if (type == sessionEndedType) {
      // Kept while the hub's list has no newer prompt than the one the stop followed.
      final after = msg is Map && msg['afterId'] is num ? msg['afterId'] as num : 0;
      if (lastHubPromptId <= after) keep.add(m);
      continue;
    }
    if (type == 'permission_request') {
      if (!fetchedPermissions.contains('${(msg as Map)['requestId']}')) keep.add(m);
      continue;
    }
    if (isOptimisticRow(m)) {
      keep.add(m);
      continue;
    }
    if (seenLocalUpTo != null && m.id > seenLocalUpTo) {
      // Arrived after the list was asked for: keep it unless the list already has it.
      fetchedJson ??= [for (final f in fetched) if (newSince == null || f.id > newSince) jsonEncode(f.message)].join('\u0000');
      if (!fetchedJson.contains(jsonEncode(m.message))) keep.add(m);
    }
  }
  final merged = keep.isEmpty ? fetched : [...fetched, ...keep];
  return settleOptimistic(merged);
}

/// Everything the Machines screen knows about the hub, and every change to it, as one pure reducer (store.tsx).

class HubState {
  const HubState({
    required this.authed,
    this.vms = const [],
    this.sessionsByVm = const {},
    this.messagesBySession = const {},
    this.resolvedPermissionIds = const {},
    this.partialBySession = const {},
    this.waiting = const {},
    this.selectedVmId,
    this.selectedSessionId,
    this.selectedAccountId,
  });

  final bool authed;
  final List<VmDto> vms;
  final Map<String, List<SessionDto>> sessionsByVm;
  final Map<String, List<MessageDto>> messagesBySession;
  final Set<String> resolvedPermissionIds;

  /// The reply each chat is writing right now, shown live until the finished message arrives.
  final Map<String, String> partialBySession;

  /// Chats where Claude asked for permission and nobody has answered yet: session id -> machine id.
  final Map<String, String> waiting;
  final String? selectedVmId;

  /// A real session id, a new chat's temporary id until the machine names it, or null for a new chat.
  final String? selectedSessionId;
  final String? selectedAccountId;

  HubState copyWith({
    List<VmDto>? vms,
    Map<String, List<SessionDto>>? sessionsByVm,
    Map<String, List<MessageDto>>? messagesBySession,
    Set<String>? resolvedPermissionIds,
    Map<String, String>? partialBySession,
    Map<String, String>? waiting,
    String? Function()? selectedVmId,
    String? Function()? selectedSessionId,
    String? Function()? selectedAccountId,
  }) =>
      HubState(
        authed: authed,
        vms: vms ?? this.vms,
        sessionsByVm: sessionsByVm ?? this.sessionsByVm,
        messagesBySession: messagesBySession ?? this.messagesBySession,
        resolvedPermissionIds: resolvedPermissionIds ?? this.resolvedPermissionIds,
        partialBySession: partialBySession ?? this.partialBySession,
        waiting: waiting ?? this.waiting,
        selectedVmId: selectedVmId != null ? selectedVmId() : this.selectedVmId,
        selectedSessionId: selectedSessionId != null ? selectedSessionId() : this.selectedSessionId,
        selectedAccountId: selectedAccountId != null ? selectedAccountId() : this.selectedAccountId,
      );
}

sealed class HubAction {
  const HubAction();
}

class SetAuthed extends HubAction {
  const SetAuthed(this.authed);
  final bool authed;
}

class SetVms extends HubAction {
  const SetVms(this.vms);
  final List<VmDto> vms;
}

class VmStatus extends HubAction {
  const VmStatus({required this.vmId, required this.name, required this.connected, required this.accounts});
  final String vmId;
  final String name;
  final bool connected;
  final List<ClaudeAccount> accounts;
}

class SetSessions extends HubAction {
  const SetSessions(this.vmId, this.sessions);
  final String vmId;
  final List<SessionDto> sessions;
}

class SetMessages extends HubAction {
  const SetMessages(this.sessionId, this.messages, {this.seenLocalUpTo, this.newSince});
  final String sessionId;
  final List<MessageDto> messages;

  /// Set when [messages] is what the phone had plus what was new after this id (see [mergeFetched]).
  final num? newSince;

  /// The newest socket row that existed when the list was asked for; later ones are kept (see [mergeFetched]).
  final num? seenLocalUpTo;
}

/// An older page of a chat (scrolling back): goes in front of what is shown.
class PrependMessages extends HubAction {
  const PrependMessages(this.sessionId, this.messages);
  final String sessionId;
  final List<MessageDto> messages;
}

/// A prompt that did not reach the hub: it is no longer shown as sent.
class RemoveMessage extends HubAction {
  const RemoveMessage(this.sessionId, this.id);
  final String sessionId;
  final num id;
}

/// Everything waiting for an answer in this chat is settled (the run was stopped).
class ResolveAllPermissions extends HubAction {
  const ResolveAllPermissions(this.sessionId);
  final String sessionId;
}

class AppendMessage extends HubAction {
  const AppendMessage(this.sessionId, this.message);
  final String sessionId;
  final MessageDto message;
}

class SessionCreated extends HubAction {
  const SessionCreated(
      {required this.vmId, required this.tempId, required this.sessionId, required this.cwd, required this.title, required this.accountId, this.now});
  final String vmId;
  final String tempId;
  final String sessionId;
  final String cwd;
  final String title;
  final String accountId;
  final DateTime? now;
}

class SessionWentIdle extends HubAction {
  const SessionWentIdle(this.vmId, this.sessionId, {this.now});
  final String vmId;
  final String sessionId;
  final DateTime? now;
}

class PermissionResolved extends HubAction {
  const PermissionResolved(this.requestId, {this.sessionId});
  final String requestId;

  /// The chat it was asked in, when known: it stops waiting.
  final String? sessionId;
}

/// The reply a chat is writing, so far.
class SetPartial extends HubAction {
  const SetPartial(this.sessionId, this.text);
  final String sessionId;
  final String text;
}

/// An answer that did not reach the machine: the question is open again.
class PermissionReopened extends HubAction {
  const PermissionReopened(this.requestIds);
  final List<String> requestIds;
}

class Select extends HubAction {
  const Select({this.vmId, this.sessionId, this.accountId});
  final String? vmId;
  final String? sessionId;
  final String? accountId;
}

HubState reduceHub(HubState state, HubAction action) {
  switch (action) {
    case SetAuthed(:final authed):
      // Signing out must not leave one person's machines and chats in memory for the next to see.
      return authed ? HubState(
              authed: true,
              vms: state.vms,
              sessionsByVm: state.sessionsByVm,
              messagesBySession: state.messagesBySession,
              resolvedPermissionIds: state.resolvedPermissionIds,
              partialBySession: state.partialBySession,
              waiting: state.waiting,
              selectedVmId: state.selectedVmId,
              selectedSessionId: state.selectedSessionId,
              selectedAccountId: state.selectedAccountId,
            ) : const HubState(authed: false);
    case SetVms(:final vms):
      return state.copyWith(vms: vms);
    case VmStatus():
      final exists = state.vms.any((v) => v.id == action.vmId);
      final vms = exists
          ? [for (final v in state.vms) v.id == action.vmId ? v.copyWith(connected: action.connected, accounts: action.accounts) : v]
          : [...state.vms, VmDto(id: action.vmId, name: action.name, connected: action.connected, accounts: action.accounts)];
      return state.copyWith(vms: vms);
    case SetSessions(:final vmId, :final sessions):
      // The hub's list says which of this machine's chats are waiting for an answer.
      final waiting = {...state.waiting};
      for (final s in sessions) {
        if (s.status == 'waiting') {
          waiting[s.id] = vmId;
        } else if (waiting[s.id] == vmId) {
          waiting.remove(s.id);
        }
      }
      return state.copyWith(sessionsByVm: {...state.sessionsByVm, vmId: sessions}, waiting: waiting);
    case SetMessages(:final sessionId, :final messages, :final seenLocalUpTo, :final newSince):
      final existing = state.messagesBySession[sessionId] ?? const <MessageDto>[];
      final merged = mergeFetched(existing, messages, seenLocalUpTo: seenLocalUpTo, newSince: newSince);
      final vmId = merged.isEmpty ? state.waiting[sessionId] : merged.last.vmId;
      final open = hasOpenPrompt(merged, state.resolvedPermissionIds);
      final waiting = {...state.waiting};
      if (open && vmId != null && vmId.isNotEmpty) {
        waiting[sessionId] = vmId;
      } else if (!open) {
        waiting.remove(sessionId);
      }
      return state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: merged},
        partialBySession: {...state.partialBySession}..remove(sessionId),
        waiting: waiting,
      );
    case PrependMessages(:final sessionId, :final messages):
      final existing = state.messagesBySession[sessionId] ?? const <MessageDto>[];
      num? oldest;
      for (final r in existing) {
        if (!isLocalRow(r) && r.id >= 0 && (oldest == null || r.id < oldest)) oldest = r.id;
      }
      final older = [for (final m in messages) if (oldest == null || m.id < oldest) m];
      if (older.isEmpty) return state;
      return state.copyWith(messagesBySession: {...state.messagesBySession, sessionId: [...older, ...existing]});
    case AppendMessage(:final sessionId, :final message):
      final existing = state.messagesBySession[sessionId] ?? const <MessageDto>[];
      final next = _isUserPrompt(message) && !isOptimisticRow(message) ? settleOptimistic([...existing, message]) : [...existing, message];
      final m = message.message;
      final type = m is Map ? m['type'] : null;
      final isPrompt = type == 'permission_request';
      // Anything Claude finished writing (or a prompt for permission) replaces the live text.
      final replacesPartial = type != null && type != 'user' && state.partialBySession.containsKey(sessionId);
      return state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: next},
        partialBySession: replacesPartial ? ({...state.partialBySession}..remove(sessionId)) : null,
        waiting: isPrompt && message.vmId.isNotEmpty ? {...state.waiting, sessionId: message.vmId} : null,
      );
    case SetPartial(:final sessionId, :final text):
      return state.copyWith(partialBySession: {...state.partialBySession, sessionId: text});
    case RemoveMessage(:final sessionId, :final id):
      final rows = state.messagesBySession[sessionId];
      if (rows == null) return state;
      return state.copyWith(messagesBySession: {...state.messagesBySession, sessionId: [for (final r in rows) if (r.id != id) r]});
    case ResolveAllPermissions(:final sessionId):
      final ids = <String>{};
      for (final r in state.messagesBySession[sessionId] ?? const <MessageDto>[]) {
        final m = r.message;
        if (m is Map && m['type'] == 'permission_request') ids.add('${m['requestId']}');
      }
      return state.copyWith(resolvedPermissionIds: {...state.resolvedPermissionIds, ...ids}, waiting: {...state.waiting}..remove(sessionId));
    case SessionCreated():
      final merged = settleOptimistic([...?state.messagesBySession[action.tempId], ...?state.messagesBySession[action.sessionId]]);
      final messages = {...state.messagesBySession, action.sessionId: merged}..remove(action.tempId);
      final existing = state.sessionsByVm[action.vmId] ?? const [];
      final withoutTemp = existing.where((s) => s.id != action.tempId && s.id != action.sessionId);
      final now = (action.now ?? DateTime.now()).toUtc().toIso8601String();
      final sessions = {
        ...state.sessionsByVm,
        action.vmId: [
          SessionDto(
            id: action.sessionId,
            vmId: action.vmId,
            cwd: action.cwd,
            title: action.title,
            createdAt: now,
            lastMessageAt: now,
            status: 'active',
            accountId: action.accountId,
          ),
          ...withoutTemp,
        ],
      };
      final selected = state.selectedSessionId == action.tempId ? action.sessionId : state.selectedSessionId;
      return state.copyWith(messagesBySession: messages, sessionsByVm: sessions, selectedSessionId: () => selected);
    case SessionWentIdle(:final vmId, :final sessionId):
      // Marks the end of whatever turn was running (a stopped or crashed run sends no result), so the chat stops spinning.
      final rows = state.messagesBySession[sessionId];
      final at = action.now ?? DateTime.now();
      final marker = MessageDto(
          id: -at.millisecondsSinceEpoch,
          sessionId: sessionId,
          vmId: vmId,
          message: {'type': sessionEndedType, 'afterId': hubTail(rows ?? const [])},
          createdAt: at.toUtc().toIso8601String());
      final settled = state.partialBySession.containsKey(sessionId) || state.waiting.containsKey(sessionId)
          ? state.copyWith(
              partialBySession: {...state.partialBySession}..remove(sessionId),
              waiting: {...state.waiting}..remove(sessionId),
            )
          : state;
      final ended = rows == null ? settled : settled.copyWith(messagesBySession: {...settled.messagesBySession, sessionId: [...rows, marker]});
      final list = ended.sessionsByVm[vmId];
      if (list == null) return ended;
      return ended.copyWith(sessionsByVm: {
        ...ended.sessionsByVm,
        vmId: [for (final s in list) s.id == sessionId ? s.copyWith(status: 'idle') : s],
      });
    case PermissionResolved(:final requestId, :final sessionId):
      final resolved = {...state.resolvedPermissionIds, requestId};
      final sid = sessionId ?? _sessionOfPrompt(state, requestId);
      final stillOpen = sid != null && hasOpenPrompt(state.messagesBySession[sid] ?? const [], resolved);
      return state.copyWith(resolvedPermissionIds: resolved, waiting: sid == null || stillOpen ? null : ({...state.waiting}..remove(sid)));
    case PermissionReopened(:final requestIds):
      final sid = requestIds.isEmpty ? null : _sessionOfPrompt(state, requestIds.first);
      final rows = sid == null ? null : state.messagesBySession[sid];
      final vmId = rows == null || rows.isEmpty ? null : rows.last.vmId;
      return state.copyWith(
        resolvedPermissionIds: state.resolvedPermissionIds.difference(requestIds.toSet()),
        waiting: sid != null && vmId != null && vmId.isNotEmpty ? {...state.waiting, sid: vmId} : null,
      );
    case Select():
      return state.copyWith(selectedVmId: () => action.vmId, selectedSessionId: () => action.sessionId, selectedAccountId: () => action.accountId);
  }
}

/// What a hub event does to the state (the socket subscription in store.tsx). [localId] numbers rows that came
/// over the socket, which have no hub row id.
HubAction? actionForEvent(HubEvent msg, num Function() localId) {
  switch (msg) {
    case VmStatusEvent():
      return VmStatus(vmId: msg.vmId, name: msg.name, connected: msg.connected, accounts: msg.accounts);
    case SdkMessageEvent():
      return AppendMessage(
          msg.sessionId, MessageDto(id: localId(), sessionId: msg.sessionId, vmId: msg.vmId, message: msg.message, createdAt: msg.createdAt));
    case SessionCreatedEvent():
      return SessionCreated(vmId: msg.vmId, tempId: msg.tempId, sessionId: msg.sessionId, cwd: msg.cwd, title: msg.title, accountId: msg.accountId);
    case SessionEndedEvent():
      return SessionWentIdle(msg.vmId, msg.sessionId);
    case PermissionRequestEvent():
      return AppendMessage(
        msg.sessionId,
        MessageDto(
          id: localId(),
          sessionId: msg.sessionId,
          vmId: msg.vmId,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          message: {
            'type': 'permission_request',
            'requestId': msg.requestId,
            'toolName': msg.toolName,
            'input': msg.input,
            'blockedPath': ?msg.blockedPath,
          },
        ),
      );
    case PermissionResolvedEvent():
      return PermissionResolved(msg.requestId, sessionId: msg.sessionId);
    case SdkPartialEvent():
      return SetPartial(msg.sessionId, msg.text);
  }
}

/// The chat a permission prompt was asked in, among the chats this phone has loaded.
String? _sessionOfPrompt(HubState state, String requestId) {
  for (final e in state.messagesBySession.entries) {
    for (final r in e.value) {
      final m = r.message;
      if (m is Map && m['type'] == 'permission_request' && m['requestId'] == requestId) return e.key;
    }
  }
  return null;
}

/// Is Claude in this chat waiting for an answer to a permission prompt? (One that nobody answered, and no turn ended since.)
bool hasOpenPrompt(List<MessageDto> rows, Set<String> resolved) {
  for (var i = rows.length - 1; i >= 0; i--) {
    final m = rows[i].message;
    if (m is! Map) continue;
    final type = m['type'];
    if (type == 'result' || type == sessionEndedType) return false;
    if (type == 'permission_request' && !resolved.contains('${m['requestId']}')) return true;
  }
  return false;
}
