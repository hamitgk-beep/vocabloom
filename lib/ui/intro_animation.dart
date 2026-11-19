import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart' show readingFont;

/// The opening animation (5 s): an open book flies in from afar with its
/// ribbons waving and a trail of gold dust behind it. As it comes close it
/// stands up and slowly shuts, "Storilex" shows on its cover, then the word
/// gives way to a shining gold S. A tap skips it.
class IntroAnimation extends StatefulWidget {
  final VoidCallback onDone;
  const IntroAnimation({super.key, required this.onDone});

  /// Length of the animation itself, before the fade into the app.
  static const length = Duration(milliseconds: 5000);

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

/// A small 3D vector, enough for the book's corners and normals.
class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V get unit => this * (1 / length);
}

/// A rigid transform (3x3 matrix, row-major, and a translation).
class _Pose {
  final List<double> r;
  final _V t;
  const _Pose(this.r, this.t);
  static const identity = _Pose([1, 0, 0, 0, 1, 0, 0, 0, 1], _V(0, 0, 0));

  _V rot(_V v) => _V(r[0] * v.x + r[1] * v.y + r[2] * v.z, r[3] * v.x + r[4] * v.y + r[5] * v.z, r[6] * v.x + r[7] * v.y + r[8] * v.z);
  _V apply(_V v) => rot(v) + t;

  /// This pose followed by [o].
  _Pose then(_Pose o) {
    final a = o.r, b = r;
    final m = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        m[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
      }
    }
    return _Pose(m, o.apply(t));
  }

  static _Pose move(_V t) => _Pose(const [1, 0, 0, 0, 1, 0, 0, 0, 1], t);
  static _Pose scale(double s) => _Pose([s, 0, 0, 0, s, 0, 0, 0, s], const _V(0, 0, 0));
  static _Pose rotX(double a) => _Pose([1, 0, 0, 0, math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a)], const _V(0, 0, 0));
  static _Pose rotY(double a) => _Pose([math.cos(a), 0, math.sin(a), 0, 1, 0, -math.sin(a), 0, math.cos(a)], const _V(0, 0, 0));
  static _Pose rotZ(double a) => _Pose([math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a), 0, 0, 0, 1], const _V(0, 0, 0));
}

typedef _Art = void Function(Canvas c, double w, double h);

/// One flat side of the book: a rectangle at [o] spanned by [u] and [v]
/// (its outside is u × v), painted by [art] in its own w × h coordinates.
class _Face {
  final _V o, u, v;
  final _Art art;
  final bool twoSided;
  _Face(this.o, this.u, this.v, this.art, {this.twoSided = false});
}

/// Draws the intro at [t] seconds. Public so tests can render any moment.
class IntroPainter extends CustomPainter {
  final double t;
  final bool dark;
  IntroPainter(this.t, {this.dark = true});

  // Timeline (seconds).
  static const _flyEnd = 2.0;
  static const _standStart = 1.55, _standEnd = 3.15;
  static const _closeStart = 1.7, _closeEnd = 3.3;
  static const _titleIn = 3.3, _titleOut = 3.95;
  static const _sIn = 4.15;

  static const _gold = Color(0xFFE2B95C);
  static const _goldLight = Color(0xFFFFF0B8);
  static const _goldDeep = Color(0xFF9A6A24);

  /// Camera distance for the perspective (logical pixels).
  static const _eye = 1500.0;

  // Where the book is on screen at time [tt], and how far away (scale).
  ({Offset pos, double scale}) _place(Size size, double tt) {
    final c = size.center(Offset.zero) + Offset(0, -size.height * 0.03);
    final f = _ramp(tt, 0, _flyEnd, Curves.easeOutCubic);
    final start = c + Offset(-size.width * 0.45, -size.height * 0.42);
    final ctrl = c + Offset(size.width * 0.35, -size.height * 0.5);
    final pos = Offset(
      (1 - f) * (1 - f) * start.dx + 2 * (1 - f) * f * ctrl.dx + f * f * c.dx,
      (1 - f) * (1 - f) * start.dy + 2 * (1 - f) * f * ctrl.dy + f * f * c.dy,
    );
    final bob = math.sin(tt * 4.6) * 8 * (1 - f);
    return (pos: pos + Offset(0, bob), scale: _lerp(0.08, 1, f));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size);

    // The shut book fills a bit under half the screen height.
    final hPage = math.min(size.height * 0.44, size.width * 0.55 / 0.7);
    final wPage = hPage * 0.7;
    final place = _place(size, t);
    final stand = _ramp(t, _standStart, _standEnd, Curves.easeInOutCubic);
    final close = _ramp(t, _closeStart, _closeEnd, Curves.easeInOutSine);
    // While open the book is twice as wide; keep it on the screen.
    final fit = math.min(1.0, size.width * 0.86 / (2 * wPage * 1.1));
    final s = place.scale * _lerp(fit, 1, close);

    _dust(canvas, size, hPage);

    final glowA = 0.3 + 0.6 * _ramp(t, _sIn, _sIn + 0.6);
    final gr = hPage * 0.95 * place.scale;
    canvas.drawCircle(
      place.pos,
      gr,
      Paint()
        ..shader = RadialGradient(colors: [
          _gold.withValues(alpha: (dark ? 0.34 : 0.26) * glowA),
          _gold.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: place.pos, radius: gr)),
    );

    // Lying back (pages up, as on a table) while flying, upright once shut.
    final tilt = _lerp(_lerp(-1.1, -0.9, _ramp(t, 0, _flyEnd)), 0, stand);
    final turn = _lerp(-0.42, -0.06, _ramp(t, 0, _flyEnd)) * (1 - stand);
    final yaw = 0.25 * math.sin(close * math.pi);
    _book(canvas, place.pos, s, tilt, turn, yaw, wPage, hPage, close);
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
    const n = 260;
    const life = 1.4;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final born = i / n * (_flyEnd + 0.4);
      final dx = rnd.nextDouble() - 0.5, dy = rnd.nextDouble() - 0.5;
      final vx = (rnd.nextDouble() - 0.5) * 40, vy = rnd.nextDouble() * 30 + 8;
      final r0 = 1 + rnd.nextDouble() * 2.6;
      final tw = rnd.nextDouble() * 6;
      final age = t - born;
      if (age < 0 || age > life) continue;
      final at = _place(size, born);
      final spread = h * at.scale;
      final pos = at.pos + Offset(dx * spread * 1.4, dy * spread * 0.5 + spread * 0.2) + Offset(vx * age, vy * age);
      final k = 1 - age / life;
      final a = k * (0.6 + 0.4 * math.sin(t * 14 + tw));
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

  // ---- The 3D book -------------------------------------------------------
  //
  // Book space: x to the right, y down, z towards the viewer. The spine runs
  // along x = 0. The back half (back cover and half the pages) lies in
  // 0 ≤ z ≤ T/2; the front half (front cover and the other pages) is hinged
  // at the spine and swings from open (flat on the left, pages up) to shut
  // (on top of the back half, cover facing the viewer).

  void _book(Canvas canvas, Offset pos, double s, double tilt, double turn, double yaw, double w, double h, double close) {
    final thick = h * 0.15, c = h * 0.014, m = h * 0.022;
    final half = thick / 2;
    // Hinge angle: π open, 0 shut.
    final theta = math.pi * (1 - close);
    _Pose hingeAt(double a) => _Pose.move(_V(0, 0, -half)).then(_Pose.rotY(-a)).then(_Pose.move(_V(0, 0, half)));
    final hinge = hingeAt(theta);
    // The open book's middle is the spine, the shut one's is half a cover to the right.
    final centre = _Pose.move(_V(-w / 2 * close, 0, -half));
    final model = centre.then(_Pose.scale(s)).then(_Pose.rotZ(turn)).then(_Pose.rotY(yaw)).then(_Pose.rotX(tilt));

    // Painting order: the viewer is always on the +z side, so the leaves
    // hinged at the spine stack by how far they stand up: flat ones first,
    // the most upright last. [order] holds that rank for each face.
    final faces = <(_Face, _Pose, double)>[];
    double rank(double a, [double within = 0]) => -(a - math.pi / 2).abs() + within * 0.001;
    void box(double x0, double x1, double y0, double y1, double z0, double z1, _Pose pose, _Art all, double order, {_Art? front, _Art? back}) {
      faces.add((_Face(_V(x0, y0, z1), _V(x1 - x0, 0, 0), _V(0, y1 - y0, 0), front ?? all), pose, order)); // +z
      faces.add((_Face(_V(x1, y0, z0), _V(x0 - x1, 0, 0), _V(0, y1 - y0, 0), back ?? all), pose, order)); // -z
      faces.add((_Face(_V(x1, y0, z1), _V(0, 0, z0 - z1), _V(0, y1 - y0, 0), all), pose, order)); // +x
      faces.add((_Face(_V(x0, y0, z0), _V(0, 0, z1 - z0), _V(0, y1 - y0, 0), all), pose, order)); // -x
      faces.add((_Face(_V(x0, y1, z1), _V(x1 - x0, 0, 0), _V(0, 0, z0 - z1), all), pose, order)); // +y
      faces.add((_Face(_V(x0, y0, z0), _V(x1 - x0, 0, 0), _V(0, 0, z1 - z0), all), pose, order)); // -y
    }

    final top = -h / 2, bottom = h / 2;
    // Back half: cover plate, then pages.
    box(0, w + m, top - m, bottom + m, 0, c, _Pose.identity, _leatherArt, rank(0, 0));
    box(0, w, top, bottom, c, half, _Pose.identity, _edgeArt, rank(0, 1), front: (cv, fw, fh) => _pageArt(cv, fw, fh, spineLeft: true));
    // Front half, on the hinge: past upright its cover is underneath.
    final coverOnTop = theta < math.pi / 2;
    box(0, w, top, bottom, half, thick - c, hinge, _edgeArt, rank(theta, coverOnTop ? 0 : 1), back: (cv, fw, fh) => _pageArt(cv, fw, fh, spineLeft: false));
    box(0, w + m, top - m, bottom + m, thick - c, thick, hinge, _leatherArt, rank(theta, coverOnTop ? 1 : 0), front: _coverArt);
    // Loose pages that lag behind the cover as it shuts.
    for (final k in [0.12, 0.24, 0.38]) {
      // They lie with the front pages while open and fan out as it shuts.
      final a = (theta - k * 1.6 * math.sin(close * math.pi)).clamp(0.0, math.pi);
      faces.add((
        _Face(_V(0, top + 1, half + 0.3), _V(w * 0.985, 0, 0), _V(0, h - 2, 0), (cv, fw, fh) => _pageArt(cv, fw, fh, spineLeft: true), twoSided: true),
        hingeAt(a),
        rank(a, 0.5),
      ));
    }
    // The spine: a band joining the two covers' spine edges.
    final b1 = hinge.apply(_V(0, 0, thick));
    if (b1.length > 1) {
      faces.add((_Face(_V(0, top - m, 0), b1, _V(0, h + 2 * m, 0), _spineArt, twoSided: true), _Pose.identity, -10.0));
    }

    // Cull the sides facing away and paint far to near.
    final drawn = <({_Face f, _Pose pose, double depth, _V n})>[];
    for (final (f, pose, order) in faces) {
      final full = pose.then(model);
      final o = full.apply(f.o), u = full.rot(f.u), v = full.rot(f.v);
      final n = u.cross(v).unit;
      final mid = o + u * 0.5 + v * 0.5;
      final toEye = const _V(0, 0, _eye) - mid;
      final facing = n.dot(toEye);
      if (!f.twoSided && facing <= 0) continue;
      drawn.add((f: f, pose: full, depth: order, n: facing < 0 ? n * -1 : n));
    }
    drawn.sort((a, b) => a.depth.compareTo(b.depth));
    final light = const _V(-0.3, 0.15, 0.94).unit;
    final persp = Matrix4.translationValues(pos.dx, pos.dy, 0)..multiply(Matrix4.identity()..setEntry(3, 2, -1 / _eye));
    for (final d in drawn) {
      final f = d.f;
      final o = d.pose.apply(f.o), u = d.pose.rot(f.u), v = d.pose.rot(f.v);
      final fw = f.u.length, fh = f.v.length;
      final uh = u * (1 / fw), vh = v * (1 / fh), nh = uh.cross(vh).unit;
      // Face space (x, y) -> book space -> perspective -> screen.
      final mtx = Matrix4(
        uh.x, uh.y, uh.z, 0, //
        vh.x, vh.y, vh.z, 0,
        nh.x, nh.y, nh.z, 0,
        o.x, o.y, o.z, 1,
      );
      canvas.save();
      canvas.transform((persp.clone()..multiply(mtx)).storage);
      f.art(canvas, fw, fh);
      final lit = 0.42 + 0.58 * math.max(0.0, d.n.dot(light));
      canvas.drawRect(Rect.fromLTWH(-0.5, -0.5, fw + 1, fh + 1), Paint()..color = Colors.black.withValues(alpha: (1 - lit) * 0.7));
      canvas.restore();
    }

    // Ribbons hang from the bottom of the pages near the spine.
    Offset proj(_V p) {
      final k = _eye / (_eye - p.z);
      return pos + Offset(p.x * k, p.y * k);
    }

    final a0 = model.apply(_V(w * 0.3, bottom, half)), a1 = model.apply(_V(w * 0.42, bottom, half));
    _ribbons(canvas, proj(a0), proj(a1), h * s, close);
  }

  void _leatherArt(Canvas c, double w, double h) {
    final r = Rect.fromLTWH(0, 0, w, h);
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7A4B2C), Color(0xFF4A2C19), Color(0xFF2C190D)],
        ).createShader(r),
    );
  }

  void _edgeArt(Canvas c, double w, double h) {
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFEADBB8));
    // Fine lines of the many pages along the thin side.
    final thinW = w < h;
    const n = 14;
    final p = Paint()
      ..color = const Color(0xFFC9B285)
      ..strokeWidth = 0.6;
    for (var i = 1; i < n; i++) {
      if (thinW) {
        c.drawLine(Offset(w * i / n, 0), Offset(w * i / n, h), p);
      } else {
        c.drawLine(Offset(0, h * i / n), Offset(w, h * i / n), p);
      }
    }
  }

  void _spineArt(Canvas c, double w, double h) {
    _leatherArt(c, w, h);
    final g = Paint()
      ..color = _gold
      ..strokeWidth = math.max(1, h * 0.006);
    for (final y in [0.12, 0.15, 0.85, 0.88]) {
      c.drawLine(Offset(0, h * y), Offset(w, h * y), g);
    }
  }

  void _pageArt(Canvas c, double w, double h, {required bool spineLeft, bool lines = true}) {
    final r = Rect.fromLTWH(0, 0, w, h);
    c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: spineLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: spineLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [Color(0xFFC9B083), Color(0xFFFFF7E6), Color(0xFFF2E3C3)],
          stops: const [0, 0.16, 1],
        ).createShader(r),
    );
    if (!lines) return;
    final line = Paint()
      ..color = const Color(0xFF8B6B45).withValues(alpha: 0.35)
      ..strokeWidth = math.max(1, h * 0.011)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 11; i++) {
      final y = h * 0.1 + i * h * 0.075;
      final short = i % 4 == 3 ? 0.4 : 0.0;
      final x0 = w * 0.14, x1 = w * (0.86 - short);
      c.drawLine(spineLeft ? Offset(x0, y) : Offset(w - x1, y), spineLeft ? Offset(x1, y) : Offset(w - x0, y), line);
    }
  }

  // Two ribbons hanging from [a] and [b], waving in the wind.
  void _ribbons(Canvas canvas, Offset a, Offset b, double h, double close) {
    final len = h * 0.36;
    final wind = _lerp(1, 0.25, close);
    for (final (i, color, at) in [(0, const Color(0xFF8E2F2A), a), (1, _gold, b)]) {
      final w = h * (i == 0 ? 0.065 : 0.05);
      final left = <Offset>[], right = <Offset>[];
      for (var k = 0; k <= 16; k++) {
        final u = k / 16;
        final sway = math.sin(u * 4.2 - t * (7 + i * 1.5)) * h * 0.06 * u * wind + u * u * h * 0.06 * wind;
        final y = at.dy - 3 + u * len;
        left.add(Offset(at.dx + sway - w / 2, y));
        right.add(Offset(at.dx + sway + w / 2, y));
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
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  // Outside of the front cover, spine side at x = 0.
  void _coverArt(Canvas canvas, double w, double h) {
    _leatherArt(canvas, w, h);
    canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.1, h), Paint()..color = const Color(0x55200F05));
    final r = Rect.fromLTWH(0, 0, w, h);
    final gold = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_goldLight, _gold, Color(0xFFC08E35), Color(0xFF8A5E1E)],
    ).createShader(r);
    final inner = Rect.fromLTRB(w * 0.17, h * 0.075, w * 0.93, h * 0.925);
    final stroke = Paint()
      ..shader = gold
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(inner, const Radius.circular(3)), stroke..strokeWidth = math.max(1.4, h * 0.011));
    canvas.drawRRect(RRect.fromRectAndRadius(inner.deflate(h * 0.022), const Radius.circular(2)), stroke..strokeWidth = math.max(0.8, h * 0.005));
    final fill = Paint()..shader = gold;
    for (final p in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
      canvas.drawCircle(p, h * 0.013, fill);
    }
    final centre = inner.center;

    final titleA = _ramp(t, _titleIn, _titleIn + 0.35) * (1 - _ramp(t, _titleOut, _titleOut + 0.3));
    if (titleA > 0) {
      _goldText(canvas, 'Storilex', centre, inner.width * 0.2, titleA, maxWidth: inner.width * 0.84);
    }
    final sA = _ramp(t, _sIn, _sIn + 0.45);
    if (sA <= 0) return;
    final pop = Curves.easeOutBack.transform(_clamp01((t - _sIn) / 0.6));
    final ring = inner.width * 0.36;
    canvas.drawCircle(
      centre,
      ring * 1.2,
      Paint()
        ..shader = RadialGradient(colors: [_goldLight.withValues(alpha: 0.5 * sA), _gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centre, radius: ring * 1.2)),
    );
    canvas.drawCircle(centre, ring * 0.8, Paint()..color = _gold.withValues(alpha: sA)..style = PaintingStyle.stroke..strokeWidth = math.max(1, h * 0.006));
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
    _goldText(canvas, 'S', Offset.zero, ring * 1.25, sA, shine: _ramp(t, _sIn + 0.35, _sIn + 0.85), byInk: true);
    canvas.restore();
    _sparkles(canvas, centre, ring * 1.3);
  }

  /// Gold letters centred on [centre]. With [byInk] the capital itself is
  /// centred (baseline to cap height), not the line box with its descent.
  void _goldText(Canvas canvas, String text, Offset centre, double fontSize, double alpha, {double? maxWidth, double shine = -1, bool byInk = false}) {
    TextStyle style(Paint fg) => TextStyle(fontFamily: readingFont, fontSize: fontSize, fontWeight: FontWeight.w700, foreground: fg, height: 1);
    if (maxWidth != null) {
      final w = (TextPainter(text: TextSpan(text: text, style: style(Paint())), textDirection: TextDirection.ltr)..layout()).width;
      if (w > maxWidth) fontSize *= maxWidth / w;
    }
    TextPainter build(Paint fg) => TextPainter(text: TextSpan(text: text, style: style(fg)), textDirection: TextDirection.ltr)..layout();
    final probe = build(Paint());
    final baseline = probe.computeLineMetrics().first.baseline;
    // Literata's capitals stand about 0.7 em above the baseline.
    final inkMid = byInk ? baseline - fontSize * 0.35 : probe.height / 2;
    final topLeft = centre - Offset(probe.width / 2, inkMid);
    final box = topLeft & probe.size;
    build(Paint()
          ..color = _gold.withValues(alpha: 0.7 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.07))
        .paint(canvas, topLeft);
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
    build(fg).paint(canvas, topLeft);
  }

  void _sparkles(Canvas canvas, Offset c, double r) {
    final rnd = math.Random(3);
    for (var i = 0; i < 9; i++) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final d = r * (0.7 + rnd.nextDouble() * 0.5);
      final start = _sIn + 0.3 + rnd.nextDouble() * 0.5;
      final k = _clamp01((t - start) / 0.5);
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
