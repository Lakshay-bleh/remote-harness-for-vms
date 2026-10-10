import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../voice/voice_mode.dart';
import 'attachments.dart';
import 'dictation.dart';
import 'read_file.dart';

/// CONTRACT (owned by the assistant/composer feature; keep this constructor).
/// The message box every chat shares: attach (photos, camera, files), dictate, voice mode, send / stop.
/// [attach]: 'all' (photos, PDFs, text), 'media' (photos and text), 'text', or 'none'.
///
/// On the left a plus opens a small menu (photos, camera, files). On the right: speak instead of typing, voice mode (a
/// conversation by voice), or send. Attached files show as chips above the text, with a picture for photos and a button to
/// take any of them off.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.placeholder,
    required this.onSend,
    this.running = false,
    this.disabled = false,
    this.attach = 'all',
    this.chips,
    this.onStop,
    this.stopping = false,
    this.sendWhileRunning = false,
    this.onProblem,
  });
  final String placeholder;
  final void Function(String text, List<Attachment> attachments) onSend;
  final bool running;
  final bool disabled;
  final String attach;

  /// Choices that belong to this chat (machine, mode, model), in a row above the text.
  final Widget? chips;
  final VoidCallback? onStop;

  /// A stop is on its way: the stop button shows it is working instead of looking ignored.
  final bool stopping;

  /// Send stays usable while [running] (a turn that looks lost); the stop button stays beside it.
  final bool sendWhileRunning;
  final void Function(String? message)? onProblem;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _menu = MenuController();
  late final Dictation _dictation = Dictation((t) {
    _text.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  });
  List<Attachment> _files = [];
  int _reading = 0;
  String? _note;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(_changed);
    _dictation.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _dictation.dispose();
    super.dispose();
  }

  void _problem(String? m) {
    setState(() => _note = m);
    widget.onProblem?.call(m);
  }

  String get _allow => widget.attach == 'text' ? 'text' : (widget.attach == 'media' ? 'media' : 'all');

  Future<void> _add(Future<List<Picked>> Function() pick) async {
    _menu.close();
    List<Picked> list;
    try {
      list = await pick();
    } on PlatformException catch (e) {
      final denied = e.code.contains('denied') || e.code.contains('access');
      _problem(denied ? 'Escanor is not allowed to open your photos or camera. Allow it in your phone’s Settings.' : 'Could not attach that file.');
      return;
    } catch (_) {
      _problem('Could not attach that file.');
      return;
    }
    if (!mounted || list.isEmpty) return;
    _problem(null);
    var current = _files;
    for (final f in list) {
      final why = canAdd(current, (name: f.name, type: f.type, size: f.size), _allow);
      if (why != null) {
        _problem(why);
        continue;
      }
      setState(() => _reading++);
      try {
        final a = await f.read();
        if (!mounted) return;
        if (totalBytes([...current, a]) > LIMITS.bytesTotal) {
          _problem('Those files are too big together. Attach fewer, or smaller ones.');
          continue;
        }
        current = [...current, a];
        setState(() => _files = current);
      } catch (e) {
        if (!mounted) return;
        final s = e.toString();
        _problem(s.startsWith('Exception: ') ? s.substring(11) : 'Could not attach that file.');
      } finally {
        if (mounted) setState(() => _reading--);
      }
    }
  }

  bool get _content => _text.text.trim().isNotEmpty || _files.isNotEmpty;

  void _submit() {
    if (!_content || widget.disabled || (widget.running && !widget.sendWhileRunning) || _reading > 0) return;
    haptic();
    _dictation.stop();
    widget.onSend(_text.text.trim(), _files);
    _text.clear();
    setState(() => _files = []);
    _problem(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final err = _note ?? _dictation.error;
    final focused = _focus.hasFocus;
    final media = widget.attach == 'all' || widget.attach == 'media';

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: focused ? c.primary.withValues(alpha: 0.6) : c.lineStrong),
        boxShadow: focused ? [BoxShadow(color: c.primary.withValues(alpha: 0.10), spreadRadius: 4)] : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.chips != null) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: widget.chips!),
        if (_files.isNotEmpty || _reading > 0)
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              children: [
                for (final a in _files)
                  Padding(padding: const EdgeInsets.only(right: 8), child: _FileChip(a: a, onRemove: () => setState(() => _files = _files.where((x) => x.id != a.id).toList()))),
                if (_reading > 0)
                  Container(
                    width: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.lg)),
                    child: const Spinner(size: 32),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (widget.attach != 'none')
              MenuAnchor(
                controller: _menu,
                onOpen: () => setState(() => _menuOpen = true),
                onClose: () => setState(() => _menuOpen = false),
                style: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(c.surfaceCard),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl), side: BorderSide(color: c.lineStrong))),
                ),
                menuChildren: [
                  if (media) ...[
                    _menuItem(context, Icons.image_outlined, 'Photos', () => _add(() => pickPhotos(limit: LIMITS.files - _files.length))),
                    _menuItem(context, Icons.photo_camera_outlined, 'Take a photo', () => _add(takePhoto)),
                  ],
                  _menuItem(context, Icons.description_outlined, widget.attach == 'text' ? 'Text or code file' : 'Files', () => _add(() => pickFiles(allow: _allow))),
                ],
                builder: (context, controller, _) => _RoundButton(
                  tooltip: 'Attach',
                  onPressed: widget.disabled || widget.running
                      ? null
                      : () {
                          haptic();
                          controller.isOpen ? controller.close() : controller.open();
                        },
                  background: _menuOpen ? c.surfaceCard : Colors.transparent,
                  child: AnimatedRotation(
                    turns: _menuOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.add_rounded, size: 24, color: _menuOpen ? c.ink : c.body),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: widget.attach == 'none' ? 8 : 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: CallbackShortcuts(
                    // A hardware keyboard's Enter sends; Shift+Enter (and the phone's own keyboard) makes a new line.
                    bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      enabled: !widget.disabled,
                      minLines: 1,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(fontSize: 16, color: c.ink, height: 1.35),
                      decoration: InputDecoration(
                        hintText: _dictation.listening ? 'Listening…' : widget.placeholder,
                        hintStyle: TextStyle(color: c.mutedSoft),
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_dictation.supported && !widget.running)
              _RoundButton(
                tooltip: _dictation.listening ? 'Stop dictating' : 'Speak your message',
                onPressed: widget.disabled
                    ? null
                    : () {
                        haptic();
                        _dictation.toggle(_text.text);
                      },
                background: _dictation.listening ? c.primary : Colors.transparent,
                pulse: _dictation.listening,
                child: Icon(_dictation.listening ? Icons.mic_rounded : Icons.mic_none_rounded, size: 22, color: _dictation.listening ? c.onPrimary : c.body),
              ),
            if (widget.running && widget.onStop != null)
              _RoundButton(
                tooltip: widget.stopping ? 'Stopping' : 'Stop',
                onPressed: widget.stopping
                    ? null
                    : () {
                        haptic();
                        widget.onStop?.call();
                      },
                background: c.surfaceCard,
                child: widget.stopping ? const Spinner(size: 18) : Icon(Icons.stop_rounded, size: 22, color: c.ink),
              ),
            if (widget.running && (!widget.sendWhileRunning || !_content))
              const SizedBox.shrink()
            else if (_content)
              _RoundButton(
                tooltip: 'Send',
                onPressed: widget.disabled || _reading > 0 ? null : _submit,
                background: c.primary,
                child: Icon(Icons.arrow_upward_rounded, size: 22, color: c.onPrimary),
              )
            else if (voiceModeAvailable)
              _RoundButton(
                tooltip: 'Talk to Escanor',
                onPressed: widget.disabled
                    ? null
                    : () {
                        haptic();
                        _dictation.stop();
                        openVoiceMode();
                      },
                background: c.primary,
                child: Icon(Icons.graphic_eq_rounded, size: 22, color: c.onPrimary),
              )
            else
              _RoundButton(tooltip: 'Send', onPressed: null, background: c.surfaceCard, child: Icon(Icons.arrow_upward_rounded, size: 22, color: c.mutedSoft)),
          ]),
        ),
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Semantics(liveRegion: true, child: Notice(err, tone: NoticeTone.error))),
      box,
    ]);
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final c = context.c;
    return MenuItemButton(
      onPressed: onTap,
      leadingIcon: Icon(icon, size: 20, color: c.muted),
      style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 12)), minimumSize: WidgetStatePropertyAll(Size(220, 48))),
      child: Text(label, style: TextStyle(fontSize: 15, color: c.ink)),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.a, required this.onRemove});
  final Attachment a;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kind = switch (a.kind) { AttachmentKind.text => 'Text', AttachmentKind.pdf => 'PDF', AttachmentKind.image => 'Photo' };
    return Stack(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 28, 6),
        decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: a.preview != null
                ? Image.memory(a.preview!, width: 40, height: 40, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true)
                : Container(width: 40, height: 40, color: c.canvas, child: Icon(Icons.description_outlined, size: 22, color: c.muted)),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink)),
              Text('$kind · ${humanSize(a.size)}', style: TextStyle(fontSize: 11, color: c.muted)),
            ]),
          ),
        ]),
      ),
      Positioned(
        right: 2,
        top: 2,
        child: Semantics(
          button: true,
          label: 'Remove ${a.name}',
          child: InkResponse(
            onTap: onRemove,
            radius: 16,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: c.canvas, shape: BoxShape.circle),
              child: Icon(Icons.close_rounded, size: 13, color: c.muted),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.tooltip, required this.onPressed, required this.background, required this.child, this.pulse = false});
  final String tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final Widget child;
  final bool pulse;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.55, upperBound: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _RoundButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.pulse && !still) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: FadeTransition(
            opacity: _pulse,
            child: Material(
              color: widget.background,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onPressed,
                child: SizedBox(width: 40, height: 40, child: Center(child: widget.child)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
