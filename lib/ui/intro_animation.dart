import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The opening film: "Storilex" on the book's cover turns into the gold S,
/// then the book opens and light pours out of its pages. The app comes out
/// of that light: the view flies in and the bright pages open into the app.
/// A tap jumps to that last step.
///
/// The film is a silent animated WebP: Flutter decodes it on every
/// platform with no video plugin.
class IntroAnimation extends StatefulWidget {
  final VoidCallback onDone;
  const IntroAnimation({super.key, required this.onDone});

  static String film = 'assets/brand/intro.webp';

  /// How long the app takes to come out of the book.
  static const reveal = Duration(milliseconds: 1200);

  @override
  State<IntroAnimation> createState() => _IntroAnimationState();
}

class _IntroAnimationState extends State<IntroAnimation> with TickerProviderStateMixin {
  ui.Codec? _codec;
  ui.Image? _frame;
  ui.FrameInfo? _next;
  Duration _shownAt = Duration.zero;
  Duration _frameLength = Duration.zero;
  Color _edge = const Color(0xFF1B120C);
  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _out = AnimationController(vsync: this, duration: IntroAnimation.reveal);
  bool _decoding = false, _ended = false, _done = false;

  @override
  void initState() {
    super.initState();
    _out.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_done) {
        _done = true;
        widget.onDone();
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(IntroAnimation.film);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final first = await codec.getNextFrame();
      if (!mounted) return;
      _edge = await _edgeColour(first.image) ?? _edge;
      if (!mounted) return;
      setState(() {
        _codec = codec;
        _frame = first.image;
        _frameLength = first.duration;
      });
      _prefetch();
      _ticker.start();
    } catch (_) {
      // No film (or it cannot be decoded): straight into the app.
      if (mounted && !_done) {
        _done = true;
        widget.onDone();
      }
    }
  }

  static Future<Color?> _edgeColour(ui.Image img) async {
    final b = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (b == null) return null;
    // Average of a few pixels along the top edge, where the film is plain.
    var r = 0, g = 0, bl = 0, n = 0;
    for (var x = 4; x < img.width - 4; x += img.width ~/ 12) {
      final i = (2 * img.width + x) * 4;
      r += b.getUint8(i);
      g += b.getUint8(i + 1);
      bl += b.getUint8(i + 2);
      n++;
    }
    return Color.fromARGB(255, r ~/ n, g ~/ n, bl ~/ n);
  }

  Future<void> _prefetch() async {
    final c = _codec;
    if (c == null || _decoding || _next != null || _ended) return;
    if (_framesSeen + (_next == null ? 0 : 1) >= c.frameCount) {
      _ended = true;
      return;
    }
    _decoding = true;
    try {
      final f = await c.getNextFrame();
      if (!mounted) {
        f.image.dispose();
        return;
      }
      _next = f;
    } catch (_) {
      _ended = true;
    } finally {
      _decoding = false;
    }
  }

  int _framesSeen = 1;

  void _tick(Duration now) {
    if (_out.isAnimating || _done) return;
    if (_next != null && now - _shownAt >= _frameLength) {
      final n = _next!;
      _next = null;
      _frame?.dispose();
      setState(() {
        _frame = n.image;
        _frameLength = n.duration;
        _shownAt = now;
        _framesSeen++;
      });
      _prefetch();
    } else if (_next == null) {
      _prefetch();
    }
    if (_ended && now - _shownAt >= _frameLength) _startReveal();
  }

  void _startReveal() {
    if (_out.isAnimating || _out.isCompleted) return;
    _ticker.stop();
    _out.forward();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _out.dispose();
    _frame?.dispose();
    _next?.image.dispose();
    _codec?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('intro-animation'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_frame == null) return;
        _startReveal();
      },
      child: AnimatedBuilder(
        animation: _out,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: IntroFilmPainter(_frame, reveal: _out.value, edge: _edge),
        ),
      ),
    );
  }
}

/// Paints one frame of the film, fitted to the screen on a matching
/// background, and the app's way out of the book: from [reveal] 0 to 1 the
/// light swells, the view flies into the book, and the bright pages open
/// up into the screen, showing what lies under this painter.
double _ramp(double t, double a, double b, [Curve curve = Curves.linear]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class IntroFilmPainter extends CustomPainter {
  final ui.Image? frame;
  final double reveal;
  final Color edge;
  IntroFilmPainter(this.frame, {this.reveal = 0, this.edge = const Color(0xFF1B120C)});

  /// The bright pages in the film's last frame, and the heart of their
  /// light, as fractions of the film.
  static const door = Rect.fromLTRB(.18, .18, .82, .80);
  static const focus = Offset(.5, .48);

  /// Where the film sits on a screen of [size] (the whole film shows).
  static Rect filmRect(Size size, Size film) {
    final s = math.min(size.width / film.width, size.height / film.height);
    final w = film.width * s, h = film.height * s;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final img = frame;
    if (img == null) {
      canvas.drawRect(screen, Paint()..color = edge);
      return;
    }
    final film = filmRect(size, Size(img.width.toDouble(), img.height.toDouble()));
    canvas.saveLayer(screen, Paint());
    canvas.drawRect(screen, Paint()..color = edge);
    final whole = Offset.zero & Size(img.width.toDouble(), img.height.toDouble());
    if (film.left > 1 || film.top > 1) {
      // Wider (or taller) screens: a blurred, dimmed copy of the frame
      // fills the sides, so the film's light reaches the whole screen.
      final s = math.max(size.width / img.width, size.height / img.height);
      final cover = Rect.fromCenter(center: screen.center, width: img.width * s, height: img.height * s);
      canvas.saveLayer(screen, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.clamp));
      canvas.drawImageRect(img, whole, cover, Paint()..filterQuality = FilterQuality.low);
      canvas.restore();
      canvas.drawRect(screen, Paint()..color = edge.withValues(alpha: .55));
    }
    // On the way out the camera flies into the book, towards its light.
    final r = Curves.easeInCubic.transform(reveal);
    final focus = Offset(film.left + IntroFilmPainter.focus.dx * film.width, film.top + IntroFilmPainter.focus.dy * film.height);
    final zoom = 1 + 1.3 * r;
    canvas.save();
    canvas.translate(focus.dx, focus.dy);
    canvas.scale(zoom);
    canvas.translate(-focus.dx, -focus.dy);
    canvas.saveLayer(film, Paint());
    canvas.drawImageRect(img, whole, film, Paint()..filterQuality = FilterQuality.medium);
    _fadeEdges(canvas, film);
    canvas.restore();
    canvas.restore();
    if (reveal > 0) {
      Offset at(Offset p) => focus + (p - focus) * zoom;
      // The light swells first, spreading over the frame.
      final light = (math.sin(math.min(1, reveal * 1.5) * math.pi / 2) * (1 - _ramp(reveal, .55, 1))).clamp(0.0, 1.0);
      final reach = film.width * (.35 + 1.4 * r) * zoom;
      canvas.drawCircle(
        focus,
        reach,
        Paint()
          ..shader = ui.Gradient.radial(
            focus,
            reach,
            [const Color(0xFFFFF6DC).withValues(alpha: .95 * light), const Color(0xFFF2C66B).withValues(alpha: .55 * light), const Color(0x00F2C66B)],
            const [0, .45, 1],
          ),
      );
      // Then the bright pages become a door into the app and open up
      // until it is the whole screen.
      final p = Rect.fromPoints(
        at(Offset(film.left + door.left * film.width, film.top + door.top * film.height)),
        at(Offset(film.left + door.right * film.width, film.top + door.bottom * film.height)),
      );
      final open = _ramp(reveal, .25, 1, Curves.easeIn);
      if (open > 0) {
        final full = screen.inflate(math.max(size.width, size.height) * .5);
        final hole = Rect.lerp(p, full, Curves.easeIn.transform(open))!;
        final clear = Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(0, 0, 0, math.min(1, open * 2.2))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 50 * open);
        canvas.drawRRect(RRect.fromRectAndRadius(hole, Radius.circular(10 + 90 * open)), clear);
      }
      // The last bit of the film fades so no dark rim is left at the edges.
      final tail = _ramp(reveal, .7, 1);
      if (tail > 0) {
        canvas.drawRect(
          screen,
          Paint()
            ..blendMode = BlendMode.dstOut
            ..color = Color.fromRGBO(0, 0, 0, tail),
        );
      }
    }
    canvas.restore();
  }

  /// Fades the film's borders out (inside its own layer), so it melts
  /// into what fills the screen around it.
  void _fadeEdges(Canvas canvas, Rect film) {
    const k = [Color(0x00000000), Color(0xFF000000)];
    final w = film.width * .10, h = film.height * .06;
    final mask = Paint()..blendMode = BlendMode.dstIn;
    if (film.left > 1) {
      canvas.drawRect(Rect.fromLTWH(film.left, film.top, w, film.height), mask..shader = ui.Gradient.linear(film.topLeft, film.topLeft + Offset(w, 0), k));
      canvas.drawRect(Rect.fromLTWH(film.right - w, film.top, w, film.height), mask..shader = ui.Gradient.linear(film.topRight, film.topRight - Offset(w, 0), k));
    }
    if (film.top > 1) {
      canvas.drawRect(Rect.fromLTWH(film.left, film.top, film.width, h), mask..shader = ui.Gradient.linear(film.topLeft, film.topLeft + Offset(0, h), k));
      canvas.drawRect(Rect.fromLTWH(film.left, film.bottom - h, film.width, h), mask..shader = ui.Gradient.linear(film.bottomLeft, film.bottomLeft - Offset(0, h), k));
    }
  }

  @override
  bool shouldRepaint(IntroFilmPainter old) => old.frame != frame || old.reveal != reveal || old.edge != edge;
}
