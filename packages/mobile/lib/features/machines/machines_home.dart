import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/nav.dart';
import '../../core/prefs.dart' show haptic;
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../computers/computers_screen.dart';
import 'machines_screen.dart';

/// Servers and computers are one place. Your servers (VMs running the Escanor agent, reached through your hub) and your computers
/// (running Escanor Desktop, paired with a code) are both "a machine Escanor works on", so they share one tab: one "Machines"
/// header with a Servers / Computers switch under it. Each half leaves out its own header and offers its Add button here instead
/// ([MachinesHalf]), so there is never a second title under the switch.
class MachinesHome extends StatefulWidget {
  const MachinesHome({super.key});
  @override
  State<MachinesHome> createState() => _MachinesHomeState();
}

class _MachinesHomeState extends State<MachinesHome> {
  final Set<int> _opened = {};

  /// What Add does on each half (null: nothing to add there right now, e.g. still loading).
  final Map<int, VoidCallback?> _add = {};

  @override
  void initState() {
    super.initState();
    _opened.add(machinesSegment.value);
    machinesSegment.addListener(_changed);
  }

  @override
  void dispose() {
    machinesSegment.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _opened.add(machinesSegment.value));
  }

  void _offer(int half, VoidCallback? add) {
    final had = _add[half] != null;
    _add[half] = add;
    // Offered while building: the header catches up straight after this frame (only when the button comes or goes; the
    // newest callback is used at the tap either way).
    if (had != (add != null)) SchedulerBinding.instance.addPostFrameCallback((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final seg = machinesSegment.value;
    final add = _add[seg];
    return Material(
      color: c.canvas,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 44,
              child: Row(children: [
                Expanded(child: Text('Machines', style: TextStyle(fontSize: 21, height: 1.2, color: c.ink, fontWeight: FontWeight.w500))),
                if (add != null)
                  EButton(
                    label: 'Add',
                    icon: Icons.add_rounded,
                    onPressed: () => _add[machinesSegment.value]?.call(),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SegmentedSwitch(
                  index: seg,
                  segments: const [(label: 'Servers', icon: Icons.dns_outlined), (label: 'Computers', icon: Icons.laptop_outlined)],
                  onChanged: (i) {
                    haptic();
                    machinesSegment.value = i;
                  },
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: IndexedStack(index: seg, children: [
            for (final i in const [0, 1])
              _opened.contains(i)
                  ? MachinesHalf._(offer: (add) => _offer(i, add), child: i == 0 ? const MachinesScreen() : const ComputersScreen())
                  : const SizedBox.shrink(),
          ]),
        ),
      ]),
    );
  }
}

/// Tells a screen it is one half of the Machines tab: it leaves out its own header and offers its Add action to the tab's
/// header with [offerAdd].
class MachinesHalf extends InheritedWidget {
  const MachinesHalf._({required this.offer, required super.child});
  final void Function(VoidCallback? add) offer;

  /// Inside the Machines tab: say what Add does here (null: no Add button). Call it from build.
  static bool offerAdd(BuildContext context, VoidCallback? add) {
    final half = context.getInheritedWidgetOfExactType<MachinesHalf>();
    half?.offer(add);
    return half != null;
  }

  /// Whether this screen is shown as a half of the Machines tab (then it has no header of its own).
  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<MachinesHalf>() != null;

  @override
  bool updateShouldNotify(MachinesHalf oldWidget) => false;
}

/// A two-way (or more) switch: a rounded track with the chosen side raised on it, sliding across when another is picked.
class SegmentedSwitch extends StatelessWidget {
  const SegmentedSwitch({super.key, required this.index, required this.segments, required this.onChanged});
  final int index;
  final List<({String label, IconData icon})> segments;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = segments.length;
    final still = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceSoft, borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: c.hairline)),
      child: Stack(children: [
        AnimatedAlign(
          duration: still ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
          child: FractionallySizedBox(
            widthFactor: 1 / n,
            heightFactor: 1,
            child: DecoratedBox(
              // the same raised gold as the tab bar's chosen tab
              decoration: BoxDecoration(
                color: Color.alphaBlend(c.primary.withValues(alpha: 0.15), c.surfaceCard),
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: c.primary.withValues(alpha: 0.45)),
              ),
            ),
          ),
        ),
        Row(children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                inMutuallyExclusiveGroup: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: i == index ? null : () => onChanged(i),
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(segments[i].icon, size: 16, color: i == index ? c.primary : c.muted),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(segments[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: i == index ? c.ink : c.muted, fontWeight: i == index ? FontWeight.w500 : FontWeight.w400)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}
