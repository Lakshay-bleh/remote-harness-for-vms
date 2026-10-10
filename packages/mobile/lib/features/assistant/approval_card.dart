import 'package:flutter/material.dart';

import '../../ui/chat_parts.dart';
import 'chat_state.dart';

/// "Should I go ahead?" in plain words. The only thing the assistant asks a person for. Drawn like every chat's question
/// ([ApprovalPanel]), so Escanor AI and a machine ask the same way.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.item, required this.onAnswer});
  final AssistantItem item;
  final void Function(bool allow) onAnswer;

  @override
  Widget build(BuildContext context) {
    final answered = item.status != 'pending';
    return ApprovalPanel(
      title: item.title,
      subtitle: item.detail,
      details: item.raw.isEmpty ? null : DetailsBox(item.raw),
      high: item.risk == 'high',
      answered: answered ? (item.status == 'allowed' ? 'You said continue.' : (item.status == 'denied' ? 'You said no.' : '')) : null,
      onAnswer: onAnswer,
    );
  }
}
