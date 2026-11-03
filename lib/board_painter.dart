import 'dart:math';

import 'package:flutter/material.dart';

import 'game.dart';

const List<Color> kPalette = [
  Color(0xFFFF4D6D), // red      - circle
  Color(0xFFFFD23F), // yellow   - rounded square
  Color(0xFF3DDC97), // green    - diamond
  Color(0xFF4CC9F0), // blue     - hexagon
  Color(0xFF9B6DFF), // violet   - triangle
];

/// Draws the board, tiles and particles. `clock` drives the special-gem pulse.
class BoardPainter extends CustomPainter {
  final GameController game;
  final Animation<double> clock;

  BoardPainter(this.game, this.clock) : super(repaint: Listenable.merge([game, clock]));

  static final List<Path> _shapes = List.generate(5, _shape);
  static final Path _star = () {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + 2 * pi * i / 10;
      final r = i.isEven ? 1.0 : 0.45;
      final x = cos(a) * r, y = sin(a) * r;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }();

  static Path _ngon(int n, double r, double rot) {
    final p = Path();
    for (var i = 0; i < n; i++) {
      final a = rot + 2 * pi * i / n;
      final x = cos(a) * r, y = sin(a) * r;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  static Path _shape(int kind) {
    switch (kind) {
      case 0:
        return Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 1));
      case 1:
        final p = Path();
        for (var i = 0; i < 32; i++) {
          final a = 2 * pi * i / 32;
          final c = cos(a), s = sin(a);
          final x = c.sign * pow(c.abs(), 0.5) * 0.95;
          final y = s.sign * pow(s.abs(), 0.5) * 0.95;
          i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
        }
        return p..close();
      case 2:
        return _ngon(4, 1.12, -pi / 2);
      case 3:
        return _ngon(6, 1.02, 0);
      default:
        return _ngon(3, 1.18, -pi / 2);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / GameController.n;
    final time = clock.value * 4.0; // seconds, wraps every 4s (integer multiples keep it smooth)

    final cellPaint = Paint();
    for (var x = 0; x < GameController.n; x++) {
      for (var y = 0; y < GameController.n; y++) {
        cellPaint.color = Colors.white.withAlpha((x + y).isEven ? 20 : 9);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x * cell + 3, y * cell + 3, cell - 6, cell - 6),
            const Radius.circular(10),
          ),
          cellPaint,
        );
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = 0; x < GameController.n; x++) {
      for (var y = 0; y < GameController.n; y++) {
        final t = game.grid[x][y];
        if (t != null) _drawTile(canvas, t, cell, time);
      }
    }
    canvas.restore();

    final pp = Paint();
    for (final p in game.particles) {
      pp.color = kPalette[p.color].withAlpha((p.life / 0.6 * 255).clamp(0, 255).toInt());
      canvas.drawCircle(Offset(p.x * cell, p.y * cell), (0.05 + 0.08 * p.life) * cell, pp);
    }
  }

  void _drawTile(Canvas c, Tile t, double cell, double time) {
    final cx = (t.x + 0.5) * cell, cy = (t.y + 0.5) * cell;
    final r = cell * 0.40 * t.scale;
    if (r < 1) return;
    final a = (t.alpha * 255).clamp(0, 255).toInt();
    final base = kPalette[t.color];
    final pulse = 0.5 + 0.5 * sin(time * 2 * pi * 0.9);
    final fill = Paint();

    if (t.special == GameController.rainbow) {
      c.save();
      c.translate(cx, cy);
      c.rotate(time / 4.0 * 2 * pi);
      fill.shader = SweepGradient(colors: [...kPalette, kPalette.first])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.05));
      fill.color = Colors.white.withAlpha(a);
      c.drawCircle(Offset.zero, r * 1.05, fill);
      c.restore();
      c.save();
      c.translate(cx, cy);
      c.scale(r * 0.62);
      c.drawPath(_star, Paint()..color = Colors.white.withAlpha(a));
      c.restore();
      return;
    }

    if (t.special == GameController.bomb) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withAlpha(((0.45 + 0.55 * pulse) * a).toInt());
      for (var k = 0; k < 8; k++) {
        final ang = k * pi / 4;
        final r0 = r * (1.12 + 0.06 * pulse), r1 = r * (1.32 + 0.14 * pulse);
        c.drawLine(Offset(cx + cos(ang) * r0, cy + sin(ang) * r0),
            Offset(cx + cos(ang) * r1, cy + sin(ang) * r1), line);
      }
    }

    final shape = _shapes[t.color];
    void poly(double s, double dx, double dy, Color col) {
      c.save();
      c.translate(cx + dx * r, cy + dy * r);
      c.scale(r * s);
      c.drawPath(shape, Paint()..color = col);
      c.restore();
    }

    Color darken(Color col, double f) =>
        Color.fromARGB(255, (col.red * f).toInt(), (col.green * f).toInt(), (col.blue * f).toInt());
    Color lighten(Color col, double f) => Color.fromARGB(
        255,
        (col.red + (255 - col.red) * f).toInt(),
        (col.green + (255 - col.green) * f).toInt(),
        (col.blue + (255 - col.blue) * f).toInt());

    poly(1, 0, 0.12, Colors.black.withAlpha(a * 3 ~/ 10));
    poly(1, 0, 0, darken(base, 0.72).withAlpha(a));
    poly(0.84, -0.03, -0.04, base.withAlpha(a));
    poly(0.46, -0.14, -0.2, lighten(base, 0.5).withAlpha(a ~/ 2));
    c.drawCircle(Offset(cx - r * 0.32, cy - r * 0.38), r * 0.11, Paint()..color = Colors.white.withAlpha(a * 85 ~/ 100));

    final tp = TextPainter(
      text: TextSpan(
        text: '${t.num}',
        style: TextStyle(
          color: Colors.white.withAlpha(a),
          fontSize: r * 1.05,
          fontWeight: FontWeight.w800,
          shadows: [Shadow(color: Colors.black.withAlpha(a * 6 ~/ 10), blurRadius: r * 0.08, offset: Offset(0, r * 0.05))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2 + r * 0.06));

    if (t.special == GameController.bomb) {
      c.drawCircle(Offset(cx + r * 0.62, cy - r * 0.78), r * (0.14 + 0.06 * pulse),
          Paint()..color = const Color(0xFFFFD23F).withAlpha(a));
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
