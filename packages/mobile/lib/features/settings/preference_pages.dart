import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import 'settings_widgets.dart';

const _sizes = [(value: 'small', label: 'Small'), (value: 'default', label: 'Default'), (value: 'large', label: 'Large')];

/// Little previews of each theme: page, card and text colours, so the choice can be seen before it is made.
const _swatch = <ThemeChoice, ({Color page, Color card, Color ink, Color line})>{
  ThemeChoice.dark: (page: Color(0xFF050505), card: Color(0xFF151513), ink: Color(0xFFF3F1EC), line: Color(0xFF3E3C37)),
  ThemeChoice.light: (page: Color(0xFFFAF8F4), card: Color(0xFFFFFFFF), ink: Color(0xFF1C1A16), line: Color(0xFFCDC5B7)),
  ThemeChoice.black: (page: Color(0xFF000000), card: Color(0xFF0E0E0D), ink: Color(0xFFF3F1EC), line: Color(0xFF343432)),
};

String _pct(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.value, required this.label, required this.active, required this.onPick});
  final ThemeChoice value;
  final String label;
  final bool active;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _swatch[value];
    final preview = s == null
        ? Row(children: [
            Expanded(child: Container(color: _swatch[ThemeChoice.light]!.page)),
            Expanded(child: Container(color: _swatch[ThemeChoice.dark]!.page)),
          ])
        : Container(
            color: s.page,
            padding: const EdgeInsets.all(10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: s.card, border: Border.all(color: s.line), borderRadius: BorderRadius.circular(Radii.sm)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 32, height: 6, decoration: BoxDecoration(color: s.ink, borderRadius: BorderRadius.circular(Radii.pill))),
                const SizedBox(height: 4),
                Container(width: 48, height: 6, decoration: BoxDecoration(color: s.ink.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(Radii.pill))),
              ]),
            ),
          );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: active,
      label: label,
      child: GestureDetector(
        onTap: () {
          haptic();
          onPick();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: active ? c.primary : c.hairline, width: active ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 64, child: preview),
            Container(
              color: c.surfaceCard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(label, style: TextStyle(fontSize: 13, color: c.ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// How the app looks and feels on this phone. Stored on the phone, since a tablet may want something different.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final p = ref.watch(prefsProvider);
    void set(Prefs Function(Prefs) change) => ref.read(prefsProvider.notifier).update(change);
    String? hint;
    for (final t in themeChoices) {
      if (t.$1 == p.theme) hint = t.$3;
    }
    String startLabel = p.startTab;
    for (final s in startTabs) {
      if (s.value == p.startTab) startLabel = s.label;
    }

    return SettingsPage(title: 'Appearance and feel', children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Theme'),
        for (var i = 0; i < themeChoices.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var j = i; j < i + 2; j++) ...[
              if (j > i) const SizedBox(width: 8),
              Expanded(
                child: j < themeChoices.length
                    ? _ThemeCard(
                        value: themeChoices[j].$1,
                        label: themeChoices[j].$2,
                        active: p.theme == themeChoices[j].$1,
                        onPick: () => set((x) => x.copyWith(theme: themeChoices[j].$1)),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ]),
        ],
        if (hint != null) ...[const SizedBox(height: 6), Footnote(hint)],
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Accent colour'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
          child: Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 12, spacing: 8, children: [
            for (final name in AccentName.values)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: p.accent == name,
                label: accents[name]!.label,
                child: GestureDetector(
                  onTap: () {
                    haptic();
                    set((x) => x.copyWith(accent: name));
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accents[name]!.dark,
                      border: p.accent == name ? Border.all(color: c.ink, width: 2) : null,
                      boxShadow: p.accent == name ? [BoxShadow(color: c.surfaceCard, spreadRadius: -4)] : null,
                    ),
                    child: p.accent == name
                        ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.9))))
                        : null,
                  ),
                ),
              ),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Text size'),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(children: [
            for (final s in _sizes)
              Expanded(
                child: Semantics(
                  inMutuallyExclusiveGroup: true,
                  checked: p.textSize == s.value,
                  child: GestureDetector(
                    onTap: () {
                      haptic();
                      set((x) => x.copyWith(textSize: s.value));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: p.textSize == s.value ? c.canvas : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      alignment: Alignment.center,
                      child: Text(s.label,
                          style: TextStyle(
                              fontSize: 14,
                              color: p.textSize == s.value ? c.ink : c.body,
                              fontWeight: p.textSize == s.value ? FontWeight.w500 : FontWeight.w400)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
          child: Text(
            'The assistant’s answers will look like this. Everything in the app scales with it, from '
            '${_pct(textSizePercent['small']!)}% to ${_pct(textSizePercent['large']!)}%.',
            style: TextStyle(fontSize: 15, height: 1.55, color: c.bodyStrong),
          ),
        ),
      ]),
      Group(
        title: 'Feel',
        footer: 'Haptics give a short tap when you press a button, switch a setting or approve something (needs a vibration motor). '
            'Reduce motion turns off sliding and fading.',
        children: [
          SwitchRow(icon: Icons.vibration_rounded, label: 'Haptic feedback', on: p.haptics, onChanged: (v) => set((x) => x.copyWith(haptics: v))),
          SwitchRow(
              icon: Icons.play_circle_outline_rounded, label: 'Reduce motion', on: p.reduceMotion, onChanged: (v) => set((x) => x.copyWith(reduceMotion: v))),
          SRow(
            icon: Icons.dark_mode_outlined,
            label: 'Open the app on',
            value: startLabel,
            onTap: () async {
              final v = await showChoiceSheet<String>(context,
                  title: 'Open the app on', options: [for (final s in startTabs) Choice(s.value, s.label)], value: p.startTab);
              if (v != null) set((x) => x.copyWith(startTab: v));
            },
          ),
        ],
      ),
    ]);
  }
}

String _labelOf(List<({String value, String label})> list, String v) {
  for (final o in list) {
    if (o.value == v) return o.label;
  }
  return v;
}

/// What a new chat on one of your machines starts with. You can still change it inside the chat.
class ChatDefaultsPage extends ConsumerWidget {
  const ChatDefaultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(prefsProvider);
    void set(Prefs Function(Prefs) change) => ref.read(prefsProvider.notifier).update(change);
    String? modeHint;
    String modeLabel = p.defaultMode;
    for (final m in permissionModes) {
      if (m.value == p.defaultMode) {
        modeHint = m.hint;
        modeLabel = m.label;
      }
    }
    Future<void> pick(String title, List<Choice<String>> options, String value, Prefs Function(Prefs, String) apply) async {
      final v = await showChoiceSheet<String>(context, title: title, options: options, value: value);
      if (v != null) set((x) => apply(x, v));
    }

    return SettingsPage(title: 'New chats', children: [
      Group(
        title: 'Defaults for machine chats',
        footer: 'Applies to chats you start on your machines. The assistant on the Chat tab manages these itself.',
        children: [
          SRow(
            icon: Icons.verified_user_outlined,
            label: 'Permissions',
            sub: modeHint,
            value: modeLabel,
            onTap: () => pick('Permissions', [for (final m in permissionModes) Choice(m.value, m.label, m.hint)], p.defaultMode,
                (x, v) => x.copyWith(defaultMode: v)),
          ),
          SRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Model',
            value: _labelOf([for (final m in models) (value: m.value, label: m.label)], p.defaultModel),
            onTap: () =>
                pick('Model', [for (final m in models) Choice(m.value, m.label)], p.defaultModel, (x, v) => x.copyWith(defaultModel: v)),
          ),
          SRow(
            icon: Icons.speed_rounded,
            label: 'Effort',
            value: _labelOf([for (final m in efforts) (value: m.value, label: m.label)], p.defaultEffort),
            onTap: () =>
                pick('Effort', [for (final m in efforts) Choice(m.value, m.label)], p.defaultEffort, (x, v) => x.copyWith(defaultEffort: v)),
          ),
        ],
      ),
    ]);
  }
}
