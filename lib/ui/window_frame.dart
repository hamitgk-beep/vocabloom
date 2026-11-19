import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';

/// The app's own title bar on Windows: no system bar on top, the minimize,
/// maximize and close buttons sit in the app's top right corner, and the top
/// strip moves the window (double-click maximizes). The Windows runner drops
/// the system bar and answers the "storilex/window" channel.
class WindowFrame extends StatefulWidget {
  final Widget child;

  /// Tests turn it on to see the buttons; otherwise only on Windows.
  final bool? force;
  const WindowFrame({super.key, required this.child, this.force});

  static bool get enabled => !kIsWeb && Platform.isWindows;

  /// Height of the strip that moves the window and holds the buttons.
  static const double height = 32;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> {
  static const _channel = MethodChannel('storilex/window');
  static const _buttonWidth = 46.0;
  bool maximized = false;
  Offset? _down;
  Duration? _lastTap;
  Offset? _lastTapAt;

  bool get _on => widget.force ?? WindowFrame.enabled;

  @override
  void initState() {
    super.initState();
    if (!_on) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'maximized' && mounted) setState(() => maximized = call.arguments == true);
    });
    _call('isMaximized').then((v) {
      if (mounted && v is bool) setState(() => maximized = v);
    });
  }

  Future<Object?> _call(String m) async {
    try {
      return await _channel.invokeMethod(m);
    } catch (_) {
      return null; // an older runner without the channel: nothing to do
    }
  }

  Future<void> _toggle() async {
    final v = await _call('toggleMaximize');
    if (mounted && v is bool) setState(() => maximized = v);
  }

  bool _inStrip(Offset p, double width) => p.dy < WindowFrame.height && p.dx < width - 3 * _buttonWidth;

  @override
  Widget build(BuildContext context) {
    if (!_on) return widget.child;
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final top = mq.padding.top < WindowFrame.height ? WindowFrame.height : mq.padding.top;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton || !_inStrip(e.position, width)) return;
        // Pressing the very top edge resizes the window from the top.
        if (!maximized && e.position.dy < 4) {
          _call('startResizeTop');
          return;
        }
        final last = _lastTap, at = _lastTapAt;
        if (last != null && at != null && e.timeStamp - last < kDoubleTapTimeout && (e.position - at).distance < 8) {
          _lastTap = null;
          _down = null;
          _toggle();
          return;
        }
        _lastTap = e.timeStamp;
        _lastTapAt = e.position;
        _down = e.position;
      },
      onPointerMove: (e) {
        final d = _down;
        if (d != null && (e.position - d).distance > 3) {
          _down = null;
          _lastTap = null;
          _call('startDrag');
        }
      },
      onPointerUp: (_) => _down = null,
      onPointerCancel: (_) => _down = null,
      child: Stack(
        children: [
          // Pages make room at the top for the buttons the way they do for a
          // phone's status bar.
          MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: top),
              viewPadding: mq.viewPadding.copyWith(top: top),
            ),
            child: widget.child,
          ),
          if (!maximized)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: MouseRegion(cursor: SystemMouseCursors.resizeUp, opaque: false),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                _CaptionButton(
                  key: const ValueKey('window-minimize'),
                  kind: _Glyph.minimize,
                  tooltip: L('Simge durumuna küçült', 'Minimize'),
                  onTap: () => _call('minimize'),
                ),
                _CaptionButton(
                  key: const ValueKey('window-maximize'),
                  kind: maximized ? _Glyph.restore : _Glyph.maximize,
                  tooltip: maximized ? L('Önceki boyut', 'Restore') : L('Ekranı kapla', 'Maximize'),
                  onTap: _toggle,
                ),
                _CaptionButton(
                  key: const ValueKey('window-close'),
                  kind: _Glyph.close,
                  tooltip: L('Kapat', 'Close'),
                  onTap: () => _call('close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  final _Glyph kind;
  final String tooltip;
  final VoidCallback onTap;
  const _CaptionButton({super.key, required this.kind, required this.tooltip, required this.onTap});

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool hover = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final close = widget.kind == _Glyph.close;
    final ink = t.colorScheme.onSurface;
    final bg = !hover
        ? Colors.transparent
        : close
        ? (pressed ? const Color(0xFFA4262C) : const Color(0xFFC42B1C))
        : ink.withValues(alpha: pressed ? 0.14 : 0.08);
    final fg = hover && close ? Colors.white : ink.withValues(alpha: 0.8);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = pressed = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTap: () {
          setState(() => pressed = false);
          widget.onTap();
        },
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: _WindowFrameState._buttonWidth,
            height: WindowFrame.height,
            color: bg,
            child: CustomPaint(painter: _GlyphPainter(widget.kind, fg)),
          ),
        ),
      ),
    );
  }
}

/// Thin line glyphs in the Windows style.
class _GlyphPainter extends CustomPainter {
  final _Glyph kind;
  final Color color;
  _GlyphPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = size.center(Offset.zero);
    const h = 5.0;
    switch (kind) {
      case _Glyph.minimize:
        canvas.drawLine(c + const Offset(-h, 0.5), c + const Offset(h, 0.5), p);
      case _Glyph.maximize:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 2 * h, height: 2 * h), const Radius.circular(1.5)), p);
      case _Glyph.restore:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - h, c.dy - h + 2, 2 * h - 2, 2 * h - 2), const Radius.circular(1.5)), p);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - h + 2, c.dy - h + 2)
            ..lineTo(c.dx - h + 2, c.dy - h + 1)
            ..arcToPoint(Offset(c.dx - h + 3.5, c.dy - h), radius: const Radius.circular(1.5))
            ..lineTo(c.dx + h - 1.5, c.dy - h)
            ..arcToPoint(Offset(c.dx + h, c.dy - h + 1.5), radius: const Radius.circular(1.5))
            ..lineTo(c.dx + h, c.dy + h - 3.5)
            ..arcToPoint(Offset(c.dx + h - 1.5, c.dy + h - 2), radius: const Radius.circular(1.5))
            ..lineTo(c.dx + h - 2, c.dy + h - 2),
          p,
        );
      case _Glyph.close:
        canvas.drawLine(c + const Offset(-h, -h), c + const Offset(h, h), p);
        canvas.drawLine(c + const Offset(h, -h), c + const Offset(-h, h), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color;
}
