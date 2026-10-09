import '../../core/api.dart';
import '../composer/attachments.dart';
import 'chat_state.dart';

/// The Escanor assistant's endpoints (escanor/client.ts).
extension AssistantApi on Api {
  Future<AssistantStatus> assistantStatus() async => AssistantStatus.fromJson(await get('/ai/status'));

  Future<AssistantUsage> assistantUsage() async => AssistantUsage.fromJson(await get('/ai/usage'));

  Future<AssistantCapabilities> assistantCapabilities({bool live = false}) async =>
      AssistantCapabilities.fromJson(await get('/ai/capabilities${live ? '?live=true' : ''}'));

  Future<MachineView> assistantMachine({bool logs = false}) async => MachineView.fromJson(await get('/ai/machine?logs=$logs&tail=120'));

  Future<List<AssistantConversation>> assistantConversations() async {
    final r = await get('/ai/conversations');
    final list = r is Map ? r['conversations'] : null;
    return [if (list is List) for (final c in list) AssistantConversation.fromJson(c)];
  }

  /// Send a message (a new conversation when [conversationId] is null). Returns the conversation's id.
  Future<String> assistantSend(String text, {String? conversationId, List<ApiAttachment> attachments = const [], String? model}) async {
    final r = await post('/ai/chat', {
      'text': text,
      'conversation_id': conversationId,
      if (model != null && model.isNotEmpty && model != autoModel) 'model': model,
      if (attachments.isNotEmpty) 'attachments': [for (final a in attachments) a.toJson()],
    });
    return '${(r as Map)['conversation_id']}';
  }

  Future<AssistantMessages> assistantMessages(String id, int after) async =>
      AssistantMessages.fromJson(await get('/ai/conversations/${enc(id)}/messages?after=$after'));

  Future<void> assistantAnswer(String id, String requestId, bool allow) async {
    await post('/ai/conversations/${enc(id)}/permissions/${enc(requestId)}', {'allow': allow});
  }

  /// Stop the conversation's turn. Returns `stopped`: false when it had already finished (servers that do not say: true).
  Future<bool> assistantStop(String id) async {
    final r = await post('/ai/conversations/${enc(id)}/stop');
    final stopped = r is Map ? r['stopped'] : null;
    return stopped is bool ? stopped : true;
  }

  /// The models the assistant can answer with, and what Auto would use right now.
  Future<AssistantModels> assistantModels() async => AssistantModels.fromJson(await get('/ai/models'));

  /// Chats whose words or meaning match [query], best first (the server reads the whole chat, not just its title).
  Future<ChatSearch> assistantSearch(String query, {int limit = 20}) async =>
      ChatSearch.fromJson(await get('/ai/conversations/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit'));

  Future<void> assistantRemove(String id) async {
    await delete('/ai/conversations/${enc(id)}');
  }
}
