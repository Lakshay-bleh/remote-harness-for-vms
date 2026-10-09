import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import 'animals.dart';
import 'companion.dart';
import 'pixel_dog.dart';
import 'sprites.dart';

/// What each scene is called on the preview's buttons.
const Map<Scene, String> sceneLabel = {
  Scene.run: 'Loading',
  Scene.sniff: 'Looking up',
  Scene.dig: 'Digging',
  Scene.sit: 'All clear',
  Scene.sleep: 'Waiting',
  Scene.lick: 'Say something',
  Scene.home: 'At home',
  Scene.react: 'When tapped',
};

/// CONTRACT (owned by the companion feature). Settings > Companion: pick the animal that keeps you company on every
/// empty and loading screen.
class CompanionSettingsPage extends StatefulWidget {
  const CompanionSettingsPage({super.key});
  @override
  State<CompanionSettingsPage> createState() => _CompanionSettingsPageState();
}

class _CompanionSettingsPageState extends State<CompanionSettingsPage> {
  Scene _scene = Scene.sit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([companionChoice, companionSound]),
      builder: (context, _) {
        final c = context.c;
        final chosen = companionChoice.value;
        final sound = companionSound.value;
        final info = animalInfo(chosen);
        return SettingsPage(title: 'Companion', subtitle: 'Who keeps you company', children: [
          // the preview
          Semantics(
            label: 'Preview',
            container: true,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
              child: Column(children: [
                LayoutBuilder(builder: (context, box) {
                  final scale = (box.maxWidth / W).floorToDouble().clamp(1.0, 7.0);
                  return Center(child: PixelDog(animal: chosen, scene: _scene, scale: scale));
                }),
                const SizedBox(height: 8),
                Text('${info.name} the ${info.kind.toLowerCase()}', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, color: c.ink)),
                Text(info.blurb, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: c.muted)),
                const SizedBox(height: 4),
                Text('Tap ${info.name} to say hello.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.mutedSoft)),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Scene to preview',
                  container: true,
                  child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                    for (final s in scenes) _SceneChip(label: sceneLabel[s]!, on: s == _scene, onTap: () => setState(() => _scene = s)),
                  ]),
                ),
              ]),
            ),
          ),
          // the six to choose from
          Semantics(
            label: 'Choose a companion',
            container: true,
            child: GridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 112 + 40 * MediaQuery.textScalerOf(context).scale(1),
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [for (final a in animals) _AnimalCard(info: a, on: a.id == chosen)],
            ),
          ),
          Group(children: [
            SwitchRow(label: 'Sounds', sub: 'Woof, meow, toot and the rest when you tap them', on: sound, onChanged: setCompanionSound),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Your companion shows on loading and empty screens on this phone. It does not change how anything works.',
              style: TextStyle(fontSize: 12, height: 1.6, color: c.muted),
            ),
          ),
        ]);
      },
    );
  }
}

class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? c.primary.withValues(alpha: 0.1) : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.primary : c.hairline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            haptic();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(label, style: TextStyle(fontSize: 12.5, color: on ? c.primary : c.body)),
          ),
        ),
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({required this.info, required this.on});
  final AnimalInfo info;
  final bool on;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: on,
      label: '${info.name}, ${info.kind}${on ? ', chosen' : ''}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: on ? [BoxShadow(color: c.primary.withValues(alpha: 0.3), spreadRadius: 2)] : null,
        ),
        child: Material(
          color: c.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl), side: BorderSide(color: on ? c.primary : c.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              haptic();
              setCompanion(info.id);
            },
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(child: PixelDog(animal: info.id, scene: Scene.sit, scale: 3)),
                    const SizedBox(height: 4),
                    Text(info.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
                    Text(info.kind, style: TextStyle(fontSize: 12.5, color: c.muted)),
                  ]),
                ),
              ),
              if (on) Positioned(right: 8, top: 8, child: Icon(Icons.check_circle_rounded, size: 20, color: c.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The name of the chosen companion, for the Settings row ("Shiro", "Bubbly", ... as on the web). To follow a change
/// made on this page, rebuild the row with `ValueListenableBuilder(valueListenable: companionChoice, ...)`.
String companionLabel() => animalInfo(getCompanion()).name;
