import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/parts.dart';
import '../settings/developer_page.dart' show debugInfoFor;
import '../settings/info_pages.dart' show openLegalDoc;
import '../settings/legal_content.dart';
import '../settings/settings_widgets.dart';
import 'privacy_data_page.dart';

/// Help, all inside the app: what to read, how to reach a person (a tracked request), and the details worth sending.
class HelpPage extends ConsumerStatefulWidget {
  const HelpPage({super.key});
  @override
  ConsumerState<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends ConsumerState<HelpPage> {
  final _copied = CopiedFlag();

  @override
  void dispose() {
    _copied.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _copied,
      builder: (context, _) => SettingsPage(title: 'Help', children: [
        Group(
          title: 'Get help',
          footer: 'A report is a tracked request: it gets a reference number, is acknowledged and answered within the legal deadline, and you '
              'follow it under Privacy and your data. Do not include passwords or tokens.',
          children: [
            SRow(
              icon: Icons.headset_mic_outlined,
              label: 'Report a problem or make a complaint',
              onTap: () => pushPage(context, const PrivacyDataPage(initialType: 'grievance')),
            ),
            SRow(icon: Icons.support_outlined, label: 'Support and contact', onTap: () => openLegalDoc(context, 'support')),
            SRow(
              icon: Icons.copy_rounded,
              label: 'Copy debug details',
              value: _copied.value == 'debug' ? 'Copied' : null,
              sub: 'No passwords or tokens in it',
              chevron: false,
              onTap: () => _copied.copy('debug', debugInfoFor(context, ref)),
            ),
          ],
        ),
        Group(title: 'Read in the app', children: [
          for (final d in legalList)
            SRow(
              icon: d.key == 'refunds' || d.key == 'terms' ? Icons.description_outlined : Icons.bug_report_outlined,
              label: d.label,
              onTap: () => openLegalDoc(context, d.key),
            ),
        ]),
      ]),
    );
  }
}
