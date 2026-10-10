import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'chat_meta.dart';
import 'chat_meta_store.dart';

/// Your assistant chats, organised like any chat app: search, pinned on top, then by recency, with a menu on each. Search
/// matches names at once, then (with [search]) what was said inside every chat, by words and by meaning.
class ChatList extends ConsumerStatefulWidget {
  const ChatList({super.key, required this.chats, required this.activeId, required this.onOpen, required this.onDelete, this.hint = false, this.search});
  final List<ChatItem> chats;

  /// Look inside the chats on the server: best first, with the words that matched. Null searches names only.
  final Future<List<({String id, String snippet})>> Function(String query)? search;
  final String? activeId;
  final void Function(String id) onOpen;
  final void Function(String id, String name) onDelete;

  /// Show the empty-state hint.
  final bool hint;

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList> {
  final _query = TextEditingController();
  bool _showArchived = false;

  // The server's answer for [_hitsFor] (null until it comes), and whether one is on its way.
  Timer? _debounce;
  String _hitsFor = '';
  List<({String id, String snippet})>? _hits;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(_typed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Names match as you type; the server is asked once typing pauses.
  void _typed() {
    final q = _query.text.trim();
    _debounce?.cancel();
    if (q == _hitsFor) return setState(() {});
    final search = widget.search;
    setState(() {
      _hits = null;
      _hitsFor = '';
      _looking = search != null && q.length >= 2;
    });
    if (!_looking) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      List<({String id, String snippet})>? hits;
      try {
        hits = await search!(q);
      } catch (_) {
        hits = null; // offline or an older server: the names still match
      }
      if (!mounted || _query.text.trim() != q) return; // typed on since: this answer is for another search
      setState(() {
        _hits = hits ?? const [];
        _hitsFor = q;
        _looking = false;
      });
    });
  }

  void _menu(ChatRow row) {
    final c = context.c;
    final meta = ref.read(chatMetaProvider.notifier);
    final title = row.name.length > 40 ? '${row.name.substring(0, 40)}…' : row.name;
    showESheet<void>(context, title: title, builder: (ctx) {
      void act(VoidCallback fn) {
        haptic();
        Navigator.of(ctx).pop();
        fn();
      }

      Widget item(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Row(children: [
                  Icon(icon, size: 20, color: danger ? c.error : c.body),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 15, color: danger ? c.error : c.ink)),
                ]),
              ),
            ),
          );

      return Column(mainAxisSize: MainAxisSize.min, children: [
        item(row.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, row.pinned ? 'Unpin' : 'Pin to the top',
            row.archived ? null : () => act(() => meta.update((m) => togglePinned(m, row.id)))),
        Divider(height: 1, color: c.hairline),
        item(Icons.edit_outlined, 'Rename', () {
          Navigator.of(ctx).pop();
          _rename(row);
        }),
        Divider(height: 1, color: c.hairline),
        item(row.archived ? Icons.unarchive_outlined : Icons.archive_outlined, row.archived ? 'Move back to chats' : 'Archive',
            () => act(() => meta.update((m) => toggleArchived(m, row.id)))),
        Divider(height: 1, color: c.hairline),
        item(Icons.delete_outline_rounded, 'Delete', () => act(() => widget.onDelete(row.id, row.name)), danger: true),
      ]);
    });
  }

  void _rename(ChatRow row) {
    showESheet<void>(context, title: 'Rename chat', builder: (ctx) => _RenameForm(row: row, onSave: (name) => ref.read(chatMetaProvider.notifier).update((m) => rename(m, row.id, name))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = ref.watch(chatMetaProvider);
    final chats = widget.chats;
    final query = _query.text;
    final searching = query.trim().isNotEmpty;
    final sections = searching ? const <ChatSection>[] : organise(chats, meta, showArchived: _showArchived);
    final found = searching ? searchResults(chats, meta, query, _hitsFor == query.trim() ? _hits : null) : const <SearchRow>[];
    final archivedCount = meta.archived.where((id) => chats.any((ch) => ch.id == id)).length;

    final children = <Widget>[
      if (chats.isEmpty && widget.hint)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text('Your chats will show up here.', style: TextStyle(fontSize: 14, color: c.muted))),
      if (searching && found.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Semantics(
            header: true,
            child: Text('${found.length} ${found.length == 1 ? 'result' : 'results'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
          ),
        ),
      for (final f in found) _Row(row: f.row, snippet: f.snippet, active: f.row.id == widget.activeId, onOpen: () => widget.onOpen(f.row.id), onMenu: () => _menu(f.row)),
      if (searching && _looking)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Looking inside your chats…', style: TextStyle(fontSize: 13, color: c.muted)),
          ]),
        )
      else if (searching && found.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Text('No chats match “${query.trim()}”.', style: TextStyle(fontSize: 14, color: c.muted))),
      for (final s in sections) ...[
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(children: [
              if (s.key == 'pinned') Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.push_pin_rounded, size: 12, color: c.muted)),
              Text(s.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
            ]),
          ),
        ),
        for (final r in s.rows) _Row(row: r, active: r.id == widget.activeId, onOpen: () => widget.onOpen(r.id), onMenu: () => _menu(r)),
        const SizedBox(height: 6),
      ],
      if (!searching && archivedCount > 0)
        InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: () => setState(() => _showArchived = !_showArchived),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              Icon(Icons.inbox_outlined, size: 16, color: c.muted),
              const SizedBox(width: 8),
              Text(_showArchived ? 'Hide archived' : 'Archived ($archivedCount)', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
        ),
      const SizedBox(height: 16),
    ];

    return Column(children: [
      if (chats.length > 3)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _query,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 14, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Search chats',
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.muted),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear search', onPressed: _query.clear, icon: Icon(Icons.close_rounded, size: 16, color: c.muted)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.lineStrong)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.lineStrong)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.pill), borderSide: BorderSide(color: c.primary.withValues(alpha: 0.6))),
            ),
          ),
        ),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: children)),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.active, required this.onOpen, required this.onMenu, this.snippet = ''});
  final ChatRow row;

  /// What matched inside the chat, under its name.
  final String snippet;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? c.surfaceCard : Colors.transparent,
        shape: snippet.isEmpty ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onMenu,
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: active ? c.ink : c.body)),
                  if (snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.4, color: c.muted)),
                    ),
                ]),
              ),
            ),
            IconButton(
              tooltip: 'Options for ${row.name}',
              onPressed: onMenu,
              icon: Icon(Icons.more_horiz_rounded, size: 20, color: c.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RenameForm extends StatefulWidget {
  const _RenameForm({required this.row, required this.onSave});
  final ChatRow row;
  final void Function(String name) onSave;
  @override
  State<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends State<_RenameForm> {
  late final _name = TextEditingController(text: widget.row.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_name.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _name,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: TextStyle(fontSize: 15, color: c.ink),
        decoration: InputDecoration(hintText: widget.row.title, counterText: '', semanticCounterText: ''),
      ),
      const SizedBox(height: 8),
      Text('Leave it empty to go back to the name Escanor gave it. Names are saved on this phone.', style: TextStyle(fontSize: 12, color: c.muted)),
      const SizedBox(height: 12),
      EButton(label: 'Save', expand: true, onPressed: _save),
    ]);
  }
}
