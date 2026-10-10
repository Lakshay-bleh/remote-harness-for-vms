import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import '../machines/machines_home.dart';
import 'computer_detail.dart';
import 'computer_prefs.dart';
import 'overflow_menu.dart';
import 'pair_sheet.dart';
import 'protocol/client.dart';
import 'rename_sheet.dart';
import 'storage.dart';

/// "Paired 4 Oct 2026" style date for a stored ISO time.
String pairedDate(String iso) {
  final t = DateTime.tryParse(iso);
  return t == null ? '' : DateFormat.yMMMd().format(t.toLocal());
}

/// Forget a computer after asking. Returns true when it was forgotten.
Future<bool> confirmForget(BuildContext context, PairedComputer c, String name) => showConfirmSheet(
  context,
  title: 'Forget $name?',
  body: 'This phone will no longer control it. You can pair it again any time with a new code.',
  action: 'Forget',
  onConfirm: () async => removeComputer(c.id),
);

/// Your own computers running Escanor Desktop: pair one, then watch and control it from here. The Computers tab's first screen.
class ComputersScreen extends StatefulWidget {
  const ComputersScreen({super.key});
  @override
  State<ComputersScreen> createState() => _ComputersScreenState();
}

class _ComputersScreenState extends State<ComputersScreen> {
  List<PairedComputer> _computers = const [];

  @override
  void initState() {
    super.initState();
    _load();
    computersChanges.addListener(_load);
    computerPrefsChanges.addListener(_refresh);
  }

  @override
  void dispose() {
    computersChanges.removeListener(_load);
    computerPrefsChanges.removeListener(_refresh);
    super.dispose();
  }

  void _load() {
    try {
      final next = loadPairedComputers();
      if (mounted) setState(() => _computers = next);
    } catch (_) {
      // storage not ready (tests): nothing paired
    }
  }

  void _refresh() => mounted ? setState(() {}) : null;

  void _open(PairedComputer c) => pushPage(context, ComputerDetail(computer: c));

  void _add() => showPairSheet(
    context,
    onPaired: (c) {
      saveComputer(c);
      if (mounted) _open(c);
    },
  );

  @override
  Widget build(BuildContext context) {
    // The Computers half of the Machines tab: its header (and Add) is the tab's.
    final half = MachinesHalf.offerAdd(context, _add);
    return Material(
      color: context.c.canvas,
      child: Column(
        children: [
          if (!half)
            ScreenHeader(
              title: 'Computers',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: EButton(label: 'Add', icon: Icons.add_rounded, onPressed: _add),
                ),
              ],
            ),
          Expanded(
            child: _computers.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: DogState(
                      scene: 'sleep',
                      title: 'Waiting for your computer',
                      text: 'Install Escanor Desktop on your computer and pair it here. Everything runs on that computer’s own hardware, so there is nothing extra to pay for. You just see the results and approve what matters.',
                      action: EButton(label: 'Add your computer', onPressed: _add),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final c in _computers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _Card(computer: c, onOpen: () => _open(c)),
                        ),
                      // The space under the list is not left empty: the dog keeps watch over your computers.
                      DogState(
                        scene: 'sit',
                        title: _computers.length == 1 ? 'Your computer is all set' : 'Your computers are all set',
                        text: 'Tap one to chat with it, check on it and see what it has been doing. Add another with Add.',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One computer in the list: its name, how it was paired, and its own menu.
class _Card extends StatelessWidget {
  const _Card({required this.computer, required this.onOpen});
  final PairedComputer computer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final prefs = getComputerPrefs(computer.id);
    final name = displayName(computer, prefs);
    return Material(
      color: c.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.canvas, shape: BoxShape.circle),
                      child: Icon(Icons.laptop_rounded, size: 22, color: c.muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
                          ),
                          Text(
                            'Paired ${pairedDate(computer.pairedAt)}${(computer.agentId ?? '').isNotEmpty ? ' · works away from home' : ' · on your Wi-Fi'}',
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          OverflowMenu(
            label: 'Options for $name',
            items: [
              MenuEntry('Open', onOpen),
              MenuEntry(
                'Rename',
                () => showRenameSheet(
                  context,
                  current: prefs.alias,
                  original: computer.name,
                  onSave: (alias) => setComputerPrefs(computer.id, alias: alias),
                ),
                icon: Icons.edit_outlined,
              ),
              MenuEntry('Forget this computer', () => confirmForget(context, computer, name), icon: Icons.delete_outline_rounded, danger: true, divider: true),
            ],
          ),
        ],
      ),
    );
  }
}
