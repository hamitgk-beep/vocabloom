import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart' show readingFont;

/// The opening animation (about 4.5 s): an open book flies in from afar
/// with its ribbons waving and a trail of gold dust behind it, straightens
/// up as it comes close and shuts, "Storilex" shows on its cover, then the
/// word gives way to a shining gold S. A tap skips it.
class IntroAnimation extends StatefulWidget {
  final VoidCallback onDone;
  const IntroAnimation({super.key, required this.onDone});

  /// Length of the animation itself, before the fade into the app.
  static const length = Duration(milliseconds: 4500);

  @override
  State<IntroAnimation> createState() => _IntroAnimationState();
}

class _IntroAnimationState extends State<IntroAnimation> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: IntroAnimation.length)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    })
    ..forward();
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _done = false;

  void _finish() {
    if (_done) return;
    _done = true;
    _fade.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      key: const ValueKey('intro-animation'),
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: FadeTransition(
        opacity: ReverseAnimation(_fade),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: IntroPainter(_c.value * IntroAnimation.length.inMilliseconds / 1000, dark: dark),
          ),
        ),
      ),
    );
  }
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// 0 before [a], 1 after [b], eased in between.
double _ramp(double t, double a, double b, [Curve curve = Curves.easeInOut]) => curve.transform(_clamp01((t - a) / (b - a)));

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Draws the intro at [t] seconds. Public so tests can render any moment.
class IntroPainter extends CustomPainter {
  final double t;
  final bool dark;
  IntroPainter(this.t, {this.dark = true});

  static const _flyEnd = 1.9, _closeStart = 1.75, _closeEnd = 2.65;
  static const _titleIn = 2.6, _titleOut = 3.25, _sIn = 3.4;

  static const _gold = Color(0xFFE2B95C);
  static const _goldLight = Color(0xFFFFF0B8);
  static const _goldDeep = Color(0xFF9A6A24);

  // Where the book is (screen position, scale, turn) at time [tt].
  ({Offset pos, double scale, double turn}) _place(Size size, double tt) {
    final c = size.center(Offset.zero);
    final f = _ramp(tt, 0, _flyEnd, Curves.easeOutCubic);
    final start = c + Offset(-size.width * 0.42, -size.height * 0.40);
    final ctrl = c + Offset(size.width * 0.30, -size.height * 0.46);
    final pos = Offset(
      (1 - f) * (1 - f) * start.dx + 2 * (1 - f) * f * ctrl.dx + f * f * c.dx,
      (1 - f) * (1 - f) * start.dy + 2 * (1 - f) * f * ctrl.dy + f * f * c.dy,
    );
    // A small float while flying, settling as it arrives.
    final bob = math.sin(tt * 5.2) * 6 * (1 - f);
    return (pos: pos + Offset(0, bob), scale: _lerp(0.1, 1, f), turn: _lerp(-0.55, -0.1, f) * (1 - _ramp(tt, _closeStart, _closeEnd)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size);
    final h = math.min(size.height * 0.5, size.width * 0.62 / 0.72);
    final cw = h * 0.72;
    final place = _place(size, t);
    final close = _ramp(t, _closeStart, _closeEnd, Curves.easeInOutCubic);
    // The open book is twice as wide: it fits the screen while open and
    // grows to full size as it shuts.
    final fit = math.min(1.0, size.width * 0.9 / (2 * cw + 8));
    final grow = _lerp(fit, 1, close);

    _dust(canvas, size, h);

    // Glow behind the book, strongest once the S appears.
    final glowA = 0.25 + 0.55 * _ramp(t, _sIn, _sIn + 0.6);
    canvas.drawCircle(
      place.pos,
      h * 0.9 * place.scale,
      Paint()
        ..shader = RadialGradient(colors: [
          _gold.withValues(alpha: (dark ? 0.35 : 0.28) * glowA),
          _gold.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: place.pos, radius: h * 0.9 * place.scale)),
    );

    // The book: tilted back while far away, upright once it closes.
    final tilt = _lerp(0.85, 0.45, _ramp(t, 0, _flyEnd)) * (1 - close);
    final m = Matrix4.identity()
      ..translateByDouble(place.pos.dx, place.pos.dy, 0, 1)
      ..setEntry(3, 2, 0.0005)
      ..rotateX(-tilt)
      ..rotateZ(place.turn)
      ..scaleByDouble(place.scale * grow, place.scale * grow, 1, 1)
      // Closing moves the spine left so the shut book ends up centred.
      ..translateByDouble(-cw / 2 * close, 0, 0, 1);
    canvas.save();
    canvas.transform(m.storage);
    _book(canvas, cw, h, close);
    canvas.restore();
  }

  void _background(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 0.95,
          colors: dark
              ? const [Color(0xFF4A3220), Color(0xFF24170E), Color(0xFF120B06)]
              : const [Color(0xFFFFF8E8), Color(0xFFF1E2C2), Color(0xFFDCC394)],
          stops: const [0, 0.6, 1],
        ).createShader(r),
    );
  }

  // Gold dust left behind along the flight path.
  void _dust(Canvas canvas, Size size, double h) {
    final rnd = math.Random(7);
    const n = 240;
    const life = 1.35;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final born = i / n * (_flyEnd + 0.2);
      final dx = rnd.nextDouble() - 0.5, dy = rnd.nextDouble() - 0.5;
      final vx = (rnd.nextDouble() - 0.5) * 40, vy = rnd.nextDouble() * 30 + 8;
      final r0 = 1 + rnd.nextDouble() * 2.6;
      final tw = rnd.nextDouble() * 6;
      final age = t - born;
      if (age < 0 || age > life) continue;
      final at = _place(size, born);
      final spread = h * at.scale;
      final pos = at.pos + Offset(dx * spread * 1.2, dy * spread * 0.5 + spread * 0.25) + Offset(vx * age, vy * age);
      final k = 1 - age / life;
      final twinkle = 0.6 + 0.4 * math.sin(t * 14 + tw);
      final a = k * twinkle;
      p
        ..color = (dark ? _goldLight : _goldDeep).withValues(alpha: a)
        ..maskFilter = null;
      canvas.drawCircle(pos, r0 * (0.5 + 0.5 * k), p);
      p
        ..color = _gold.withValues(alpha: (dark ? 0.6 : 0.4) * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 2.2);
      canvas.drawCircle(pos, r0 * 2, p);
    }
    p.maskFilter = null;
  }

  // The book with its spine at x = 0: the left half stays, the right half
  // folds over it as [close] goes from 0 to 1.
  void _book(Canvas canvas, double cw, double h, double close) {
    final top = -h / 2, bottom = h / 2;
    final leather = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7A4B2C), Color(0xFF4A2C19), Color(0xFF2C190D)],
      ).createShader(Rect.fromLTRB(-cw, top, cw, bottom));

    _ribbons(canvas, cw, h, close);

    // Right back cover and pages stay; the cover edge peeks out around the pages.
    canvas.drawRRect(RRect.fromLTRBR(0, top - 4, cw + 4, bottom + 4, const Radius.circular(6)), leather);
    _pageStack(canvas, cw, h, left: false);
    _page(canvas, cw, h, left: false);

    // The left half folds over about the spine, so the shut book shows its
    // front cover with the spine on the left.
    final cosA = math.cos(close * math.pi);
    canvas.save();
    if (cosA >= 0) {
      canvas.scale(cosA, 1);
      canvas.drawRRect(RRect.fromLTRBR(-cw - 4, top - 4, 0, bottom + 4, const Radius.circular(6)), leather);
      _pageStack(canvas, cw, h, left: true);
      _page(canvas, cw, h, left: true);
      // The page darkens as it turns away from the light.
      canvas.drawRect(Rect.fromLTRB(-cw, top, 0, bottom), Paint()..color = Colors.black.withValues(alpha: 0.35 * (1 - cosA)));
    } else {
      // Past the upright point we see the outside of the cover.
      canvas.scale(-cosA, 1);
      _frontCover(canvas, cw, h, leather, -cosA);
    }
    canvas.restore();
    if (cosA > -0.95) canvas.drawLine(Offset(0, top), Offset(0, bottom), Paint()..color = const Color(0x55000000)..strokeWidth = 1.2);
  }

  void _pageStack(Canvas canvas, double cw, double h, {required bool left}) {
    final top = -h / 2, bottom = h / 2;
    for (var i = 3; i >= 1; i--) {
      final c = Paint()..color = i.isOdd ? const Color(0xFFE2CFA6) : const Color(0xFFF4E6C8);
      canvas.drawRect(left ? Rect.fromLTRB(-cw + i * 1.2, top + i * 1.5, -1, bottom + i * 0.6 - 1) : Rect.fromLTRB(1, top + i * 1.5, cw - i * 1.2, bottom + i * 0.6 - 1), c);
    }
  }

  void _page(Canvas canvas, double cw, double h, {required bool left}) {
    final top = -h / 2 + 2, bottom = h / 2 - 2;
    final s = left ? -1.0 : 1.0;
    final path = Path()
      ..moveTo(0, top + 6)
      ..quadraticBezierTo(s * cw * 0.45, top - 6, s * (cw - 4), top)
      ..lineTo(s * (cw - 4), bottom)
      ..quadraticBezierTo(s * cw * 0.45, bottom - 10, 0, bottom - 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: left ? Alignment.centerRight : Alignment.centerLeft,
          end: left ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [Color(0xFFCDB58A), Color(0xFFFFF7E6), Color(0xFFF0E0BE)],
          stops: const [0, 0.18, 1],
        ).createShader(Rect.fromLTRB(-cw, top, cw, bottom)),
    );
    final line = Paint()
      ..color = const Color(0xFF8B6B45).withValues(alpha: 0.35)
      ..strokeWidth = math.max(1, h * 0.012)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 9; i++) {
      final y = top + h * 0.12 + i * h * 0.085;
      final end = cw * (i % 4 == 3 ? 0.55 : 0.82);
      canvas.drawLine(Offset(s * cw * 0.12, y), Offset(s * end, y - 2), line);
    }
  }

  // Two ribbons hanging from the bottom of the spine, waving in the wind.
  void _ribbons(Canvas canvas, double cw, double h, double close) {
    final len = h * 0.34;
    final wind = _lerp(1, 0.25, close);
    for (final (i, color) in [(0, const Color(0xFF8E2F2A)), (1, _gold)]) {
      final x0 = cw * 0.3 + i * cw * 0.12;
      final w = h * (i == 0 ? 0.07 : 0.055);
      final left = <Offset>[], right = <Offset>[];
      for (var k = 0; k <= 14; k++) {
        final u = k / 14;
        final sway = math.sin(u * 4.2 - t * (8 + i * 1.5)) * h * 0.06 * u * wind + u * u * h * 0.05 * wind;
        final y = h / 2 - 6 + u * len;
        left.add(Offset(x0 + sway - w / 2, y));
        right.add(Offset(x0 + sway + w / 2, y));
      }
      final tip = left.last + (right.last - left.last) / 2 + Offset(0, -w * 0.6);
      final path = Path()..moveTo(left.first.dx, left.first.dy);
      for (final q in left.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.lineTo(tip.dx, tip.dy);
      for (final q in right.reversed) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.18)..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  // Front cover of the shut book, drawn over x in [0, cw], spine at 0.
  void _frontCover(Canvas canvas, double cw, double h, Paint leather, double open) {
    final top = -h / 2, bottom = h / 2;
    final r = Rect.fromLTRB(0, top - 4, cw + 4, bottom + 4);
    // Page edges peek out on the open side.
    canvas.drawRRect(RRect.fromLTRBR(cw - 6, top + 1, cw + 6, bottom + 1, const Radius.circular(3)), Paint()..color = const Color(0xFFCDB58A));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), leather);
    canvas.drawRect(Rect.fromLTRB(0, top - 4, cw * 0.13, bottom + 4), Paint()..color = const Color(0x66200F05));
    final goldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_goldLight, _gold, Color(0xFFC08E35), Color(0xFF8A5E1E)],
      ).createShader(r)
      ..style = PaintingStyle.stroke;
    final inner = Rect.fromLTRB(cw * 0.2, top + h * 0.07, cw * 0.92, bottom - h * 0.07);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, const Radius.circular(3)), goldPaint..strokeWidth = math.max(1.4, h * 0.012));
    canvas.drawRRect(RRect.fromRectAndRadius(inner.deflate(h * 0.025), const Radius.circular(2)), goldPaint..strokeWidth = math.max(0.8, h * 0.005));
    final fill = Paint()..shader = goldPaint.shader;
    for (final c in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
      canvas.drawCircle(c, h * 0.014, fill);
    }
    final centre = inner.center;

    // "Storilex" in gold, then the shining S.
    final titleA = _ramp(t, _titleIn, _titleIn + 0.35) * (1 - _ramp(t, _titleOut, _titleOut + 0.3));
    if (titleA > 0) {
      _goldText(canvas, 'Storilex', centre, inner.width * 0.2, titleA, maxWidth: inner.width * 0.86);
    }
    final sA = _ramp(t, _sIn, _sIn + 0.45);
    if (sA > 0) {
      final pop = Curves.easeOutBack.transform(_clamp01((t - _sIn) / 0.6));
      // Laurel ring around the S, as on the app icon.
      final ring = inner.width * 0.36;
      canvas.drawCircle(
        centre,
        ring * 1.15,
        Paint()
          ..shader = RadialGradient(colors: [_goldLight.withValues(alpha: 0.55 * sA), _gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centre, radius: ring * 1.15)),
      );
      canvas.drawCircle(centre, ring * 0.78, Paint()..color = _gold.withValues(alpha: sA)..style = PaintingStyle.stroke..strokeWidth = math.max(1, h * 0.006));
      final leaf = Paint()..color = _gold.withValues(alpha: sA);
      for (final side in [-1.0, 1.0]) {
        for (var i = 0; i < 9; i++) {
          final shown = _ramp(t, _sIn + 0.05 * i, _sIn + 0.05 * i + 0.25);
          if (shown == 0) continue;
          final ang = (110 + i * 17) * math.pi / 180;
          final p = centre + Offset(side * -math.cos(ang) * ring, math.sin(ang) * ring);
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(side * (i * 17 + 20) * math.pi / 180);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: ring * 0.34 * shown, height: ring * 0.15 * shown), leaf);
          canvas.restore();
        }
      }
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(_lerp(0.6, 1, pop));
      _goldText(canvas, 'S', Offset.zero, inner.width * 0.62, sA, italic: true, shine: _ramp(t, _sIn + 0.35, _sIn + 1.0, Curves.easeInOut));
      canvas.restore();
      _sparkles(canvas, centre, ring * 1.25);
    }
  }

  void _goldText(Canvas canvas, String text, Offset centre, double fontSize, double alpha, {double? maxWidth, double letterSpacing = 0, bool italic = false, double shine = -1}) {
    if (maxWidth != null) {
      final w = (TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontFamily: readingFont, fontSize: fontSize, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout()).width;
      if (w > maxWidth) fontSize *= maxWidth / w;
    }
    TextPainter build(Paint fg) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: readingFont, fontSize: fontSize, fontWeight: FontWeight.w700, fontStyle: italic ? FontStyle.italic : FontStyle.normal, letterSpacing: letterSpacing, foreground: fg),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final probe = build(Paint());
    final box = Rect.fromCenter(center: centre, width: probe.width, height: probe.height);
    // Soft glow, then the gold letters with a light band passing over them.
    final glow = build(Paint()
      ..color = _gold.withValues(alpha: 0.7 * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.08));
    glow.paint(canvas, box.topLeft);
    final band = shine < 0 ? -1.0 : _lerp(-0.4, 1.4, shine);
    final fg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _goldLight.withValues(alpha: alpha),
          _gold.withValues(alpha: alpha),
          if (band >= 0) ...[_gold.withValues(alpha: alpha), Colors.white.withValues(alpha: alpha), _gold.withValues(alpha: alpha)],
          _goldDeep.withValues(alpha: alpha),
        ],
        stops: band >= 0 ? [0, 0.3, (band - 0.12).clamp(0.31, 0.97), band.clamp(0.32, 0.98), (band + 0.12).clamp(0.33, 0.99), 1] : const [0, 0.45, 1],
      ).createShader(box);
    build(fg).paint(canvas, box.topLeft);
  }

  void _sparkles(Canvas canvas, Offset c, double r) {
    final rnd = math.Random(3);
    for (var i = 0; i < 9; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final d = r * (0.7 + rnd.nextDouble() * 0.6);
      final start = _sIn + 0.3 + rnd.nextDouble() * 0.8;
      final k = _clamp01((t - start) / 0.55);
      if (k <= 0 || k >= 1) continue;
      final s = math.sin(k * math.pi) * r * (0.08 + rnd.nextDouble() * 0.06);
      final p = c + Offset(math.cos(ang) * d, math.sin(ang) * d);
      final path = Path()
        ..moveTo(p.dx, p.dy - s)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s);
      canvas.drawPath(path, Paint()..color = _goldLight);
    }
  }

  @override
  bool shouldRepaint(IntroPainter old) => old.t != t || old.dark != dark;
}
