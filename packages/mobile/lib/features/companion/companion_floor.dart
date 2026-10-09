import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Where the controls along the bottom of the screen on show begin (a message box, with whatever sits just above it), as a
/// distance from the top of the screen in logical pixels; null when there are none. The companion rests above them rather
/// than on top of them (it once sat on the message box's attach button).
final ValueNotifier<double?> companionFloor = ValueNotifier<double?>(null);

Object? _owner;

/// Marks [child] as the bottom controls of its screen while that screen is the one on show (a hidden tab, the other half
/// of a switch or a page under another reports nothing).
class CompanionFloor extends StatefulWidget {
  const CompanionFloor({super.key, required this.child});
  final Widget child;
  @override
  State<CompanionFloor> createState() => _CompanionFloorState();
}

class _CompanionFloorState extends State<CompanionFloor> {
  bool _shown = false;

  void _report(double? top) {
    if (top == null) {
      if (!identical(_owner, this)) return;
      _owner = null;
    } else {
      _owner = this;
    }
    // Never in the middle of a frame: listeners rebuild.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      companionFloor.value = top;
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (top == null ? _owner == null : identical(_owner, this)) companionFloor.value = top;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _shown = TickerMode.valuesOf(context).enabled && Visibility.of(context);
    if (!_shown) _report(null);
    return _FloorBox(
      shown: _shown,
      onTop: (y) {
        if (mounted && _shown) _report(y);
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _report(null);
    super.dispose();
  }
}

class _FloorBox extends SingleChildRenderObjectWidget {
  const _FloorBox({required this.shown, required this.onTop, super.child});
  final bool shown;
  final void Function(double top) onTop;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFloorBox(onTop)..shown = shown;
  @override
  void updateRenderObject(BuildContext context, _RenderFloorBox renderObject) => renderObject
    ..onTop = onTop
    ..shown = shown;
}

/// Says where its top is each time it is painted (it moves with the keyboard, grows with the text, ...).
class _RenderFloorBox extends RenderProxyBox {
  _RenderFloorBox(this.onTop);
  void Function(double top) onTop;
  double? _last;
  bool _shown = false;

  set shown(bool value) {
    if (value && !_shown) {
      _last = null; // on show again: say where it is even if it has not moved
      markNeedsPaint();
    }
    _shown = value;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_shown) return;
    final top = localToGlobal(Offset.zero).dy;
    if (top != _last) {
      _last = top;
      onTop(top);
    }
  }

  @override
  void detach() {
    _last = null;
    super.detach();
  }
}

@visibleForTesting
void resetCompanionFloor() {
  _owner = null;
  companionFloor.value = null;
}
