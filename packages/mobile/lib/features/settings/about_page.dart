import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/parts.dart';
import 'info_pages.dart' show openLegalDoc;
import 'whats_new.dart';

/// What Escanor is, inside the app.
class AboutEscanorPage extends StatelessWidget {
  const AboutEscanorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = TextStyle(fontSize: 15, height: 1.55, color: c.bodyStrong);
    Widget p(String t) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(t, style: body));
    return SettingsPage(title: 'About Escanor', children: [
      p('Escanor is an assistant that does the work, not just the talking. You tell it what you need; it does it, checks the result itself, '
          'fixes what went wrong and keeps going until it is done. It only comes back to you for the few things that should never happen '
          'without you.'),
      p('It works on your own machines and servers, on the services you connect (code hosting, deployments, monitoring and more), and '
          'on its own while you are away: on a schedule, or the moment a deployment fails or an incident opens.'),
      p('Escanor is made by Escanor Labs in India. What it stores, why, and your choices about it are in the documents below, which read here in the app.'),
      Group(children: [
        SRow(icon: Icons.new_releases_outlined, label: 'What’s new', onTap: () => pushPage(context, const WhatsNewPage())),
        SRow(icon: Icons.verified_user_outlined, label: 'Privacy policy', onTap: () => openLegalDoc(context, 'privacy')),
        SRow(icon: Icons.description_outlined, label: 'Terms of service', onTap: () => openLegalDoc(context, 'terms')),
        SRow(icon: Icons.headset_mic_outlined, label: 'Get help', onTap: () => openLegalDoc(context, 'support')),
      ]),
    ]);
  }
}
