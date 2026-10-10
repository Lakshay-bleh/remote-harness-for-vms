import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'computer_prefs.dart';

/// Give a computer a name you will recognise. Blank goes back to the name the computer gave itself. Saves through [onSave].
Future<void> showRenameSheet(BuildContext context, {required String current, required String original, required void Function(String alias) onSave}) =>
    showESheet<void>(
      context,
      title: 'Rename this computer',
      builder: (_) => _RenameBody(current: current, original: original, onSave: onSave),
    );

class _RenameBody extends StatefulWidget {
  const _RenameBody({required this.current, required this.original, required this.onSave});
  final String current;
  final String original;
  final void Function(String alias) onSave;
  @override
  State<_RenameBody> createState() => _RenameBodyState();
}

class _RenameBodyState extends State<_RenameBody> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final clean = cleanName(_text.text);
    widget.onSave(clean == widget.original ? '' : clean);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(hintText: widget.original, counterText: ''),
          style: TextStyle(fontSize: 16, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'This name is only on this phone. The computer is still called “${widget.original}” on the computer itself. Leave it blank to use that name.',
          style: TextStyle(fontSize: 12, height: 1.45, color: c.muted),
        ),
        const SizedBox(height: 12),
        EButton(label: 'Save', expand: true, onPressed: _save),
      ],
    );
  }
}
