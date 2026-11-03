import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound.dart';

class Pt {
  final int x, y;
  const Pt(this.x, this.y);
  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;
  @override
  int get hashCode => x * 31 + y;
}

class Tile {
  int color, num;
  double x, y;
  double scale = 1, alpha = 1;

  /// 0 none, 1 bomb (clears 3x3), 2 rainbow (swap: clears a color).
  int special = 0;
  Tile(this.color, this.num, this.x, this.y);
}

class Particle {
  double x, y, vx, vy, life;
  final int color;
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color);
}

class MatchResult {
  final Set<Pt> cleared = {};
  final Set<Pt> totals = {};
  final Map<Pt, int> spawns = {};
}

/// Match-3 where every tile has a COLOR and a NUMBER.
///  - 3+ in a line with the same color OR the same number -> match
///  - 3+ with the same color AND number -> PERFECT: clears row + column, +2 moves
///  - match 4 -> bomb (3x3), match 5+ -> rainbow (swap: clears a color)
/// All positions/velocities are in board-cell units.
class GameController extends ChangeNotifier {
  static const int n = 8;
  static const int colorCount = 5;
  static const int numCount = 5;
  static const int startMoves = 25;
  static const int bomb = 1;
  static const int rainbow = 2;

  final SoundFx sfx = SoundFx();
  final Random _rng = Random();
  final List<List<Tile?>> grid = List.generate(n, (_) => List<Tile?>.filled(n, null));
  final List<Particle> particles = [];

  int score = 0;
  int moves = startMoves;
  int best = 0;
  bool busy = false;
  bool gameOver = false;
  Pt? selected;
  bool _dragging = false;
  Offset _down = Offset.zero;

  String? message;
  double messageAlpha = 0;
  double messageScale = 1;
  double flash = 0;
  int _msgId = 0;
  bool _particleLoop = false;
  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      best = _prefs?.getInt('best') ?? 0;
      sfx.enabled = _prefs?.getBool('sound') ?? true;
    } catch (_) {}
    newGame();
  }

  @override
  void dispose() {
    sfx.dispose();
    super.dispose();
  }

  void toggleSound() {
    sfx.enabled = !sfx.enabled;
    _prefs?.setBool('sound', sfx.enabled);
    notifyListeners();
  }

  // ===================================================================
  // Setup
  // ===================================================================

  void newGame() {
    score = 0;
    moves = startMoves;
    busy = false;
    gameOver = false;
    selected = null;
    message = null;
    flash = 0;
    particles.clear();
    for (var x = 0; x < n; x++) {
      for (var y = 0; y < n; y++) {
        grid[x][y] = null;
      }
    }
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        int c, num;
        do {
          c = _rng.nextInt(colorCount);
          num = 1 + _rng.nextInt(numCount);
        } while (_createsRun(x, y, c, num));
        grid[x][y] = Tile(c, num, x.toDouble(), y.toDouble());
      }
    }
    if (!hasMoves()) _reshuffleInstant();
    notifyListeners();
  }

  bool _createsRun(int x, int y, int c, int num) {
    if (x >= 2) {
      final a = grid[x - 1][y]!, b = grid[x - 2][y]!;
      if ((a.color == c && b.color == c) || (a.num == num && b.num == num)) return true;
    }
    if (y >= 2) {
      final a = grid[x][y - 1]!, b = grid[x][y - 2]!;
      if ((a.color == c && b.color == c) || (a.num == num && b.num == num)) return true;
    }
    return false;
  }

  // ===================================================================
  // Matching
  // ===================================================================

  @visibleForTesting
  MatchResult findMatches() {
    final r = MatchResult();
    for (var dir = 0; dir < 2; dir++) {
      for (var line = 0; line < n; line++) {
        Tile at(int i) => dir == 0 ? grid[i][line]! : grid[line][i]!;
        Pt pt(int i) => dir == 0 ? Pt(i, line) : Pt(line, i);
        for (var mode = 0; mode < 2; mode++) {
          int key(Tile t) => mode == 0 ? t.color : t.num;
          var start = 0;
          for (var i = 1; i <= n; i++) {
            final same = i < n &&
                at(i).special != rainbow &&
                at(i - 1).special != rainbow &&
                key(at(i)) == key(at(i - 1));
            if (same) continue;
            final len = i - start;
            if (len >= 3) {
              var total = true;
              for (var j = start; j < i; j++) {
                if (at(j).color != at(start).color || at(j).num != at(start).num) total = false;
                r.cleared.add(pt(j));
              }
              final mid = pt((start + i - 1) ~/ 2);
              if (total) r.totals.add(mid);
              if (len >= 4) {
                final kind = len >= 5 ? rainbow : bomb;
                if ((r.spawns[mid] ?? 0) < kind) r.spawns[mid] = kind;
              }
            }
            start = i;
          }
        }
      }
    }
    return r;
  }

  @visibleForTesting
  bool hasMoves() {
    for (var x = 0; x < n; x++) {
      for (var y = 0; y < n; y++) {
        for (final d in const [Pt(1, 0), Pt(0, 1)]) {
          final ox = x + d.x, oy = y + d.y;
          if (ox >= n || oy >= n) continue;
          final a = grid[x][y];
          grid[x][y] = grid[ox][oy];
          grid[ox][oy] = a;
          final ok = a!.special == rainbow ||
              grid[x][y]!.special == rainbow ||
              findMatches().cleared.isNotEmpty;
          grid[ox][oy] = grid[x][y];
          grid[x][y] = a;
          if (ok) return true;
        }
      }
    }
    return false;
  }

  void _reshuffleInstant() {
    var guard = 0;
    do {
      for (var x = 0; x < n; x++) {
        for (var y = 0; y < n; y++) {
          final t = grid[x][y]!;
          t.color = _rng.nextInt(colorCount);
          t.num = 1 + _rng.nextInt(numCount);
          t.special = 0;
        }
      }
      guard++;
    } while ((findMatches().cleared.isNotEmpty || !hasMoves()) && guard < 200);
  }

  // ===================================================================
  // Turn flow
  // ===================================================================

  Future<void> trySwap(Pt a, Pt b) async {
    busy = true;
    sfx.play('swap');
    await _swap(a, b);
    final ta = grid[a.x][a.y]!, tb = grid[b.x][b.y]!;
    if (ta.special == rainbow || tb.special == rainbow) {
      moves--;
      await _activateRainbow(a, b);
      await _resolve(2);
    } else if (findMatches().cleared.isEmpty) {
      sfx.play('bad');
      await _swap(a, b); // invalid move: swap back
      busy = false;
      notifyListeners();
      return;
    } else {
      moves--;
      await _resolve(1);
    }
    await _finishTurn();
  }

  Future<void> _swap(Pt a, Pt b) async {
    final ta = grid[a.x][a.y]!, tb = grid[b.x][b.y]!;
    grid[a.x][a.y] = tb;
    grid[b.x][b.y] = ta;
    await _moveTiles([
      (ta, b.x.toDouble(), b.y.toDouble()),
      (tb, a.x.toDouble(), a.y.toDouble()),
    ], 170, Curves.easeInOut);
  }

  Future<void> _resolve(int combo) async {
    while (true) {
      final m = findMatches();
      if (m.cleared.isEmpty) break;
      final toClear = <Pt>{...m.cleared};
      for (final t in m.totals) {
        for (var i = 0; i < n; i++) {
          toClear.add(Pt(i, t.y));
          toClear.add(Pt(t.x, i));
        }
      }
      await _clearTiles(toClear, m.spawns, m.totals.length, combo, null);
      combo++;
    }
  }

  /// Swapping a rainbow gem clears every tile of the neighbour's color (or the whole board).
  Future<void> _activateRainbow(Pt a, Pt b) async {
    final ta = grid[a.x][a.y]!, tb = grid[b.x][b.y]!;
    final both = ta.special == rainbow && tb.special == rainbow;
    final target = ta.special == rainbow ? tb.color : ta.color;
    final toClear = <Pt>{a, b};
    for (var x = 0; x < n; x++) {
      for (var y = 0; y < n; y++) {
        if (both || grid[x][y]!.color == target) toClear.add(Pt(x, y));
      }
    }
    await _clearTiles(toClear, const {}, 0, 1, both ? 'RAINBOW BLAST!' : 'RAINBOW!');
  }

  Future<void> _clearTiles(
      Set<Pt> toClear, Map<Pt, int> spawns, int perfects, int combo, String? label) async {
    // Bombs in the cleared set explode a 3x3 area (chains).
    var bombs = 0;
    final exploded = <Pt>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in toClear.toList()) {
        if (exploded.contains(p) || grid[p.x][p.y]!.special != bomb) continue;
        exploded.add(p);
        bombs++;
        changed = true;
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            final q = Pt(p.x + dx, p.y + dy);
            if (q.x >= 0 && q.x < n && q.y >= 0 && q.y < n) toClear.add(q);
          }
        }
      }
    }
    // 4-match -> bomb, 5-match -> rainbow: that tile survives and is upgraded.
    final survivors = {
      for (final e in spawns.entries)
        if (!exploded.contains(e.key)) e.key: e.value
    };
    toClear.removeAll(survivors.keys);

    score += toClear.length * 10 * combo + perfects * 300 * combo + bombs * 50 * combo;
    if (perfects > 0) {
      moves += 2 * perfects;
      showMessage('PERFECT MATCH!\n+${2 * perfects} moves');
      flash = 1;
      unawaited(_anim(500, Curves.decelerate, (f) => flash = 1 - f));
      HapticFeedback.heavyImpact();
      sfx.play('perfect');
    } else if (label != null) {
      showMessage(label);
      HapticFeedback.heavyImpact();
      sfx.play('rainbow');
    } else if (bombs > 0) {
      showMessage('BOOM!');
      HapticFeedback.heavyImpact();
      sfx.play('boom');
    } else {
      if (combo >= 2) showMessage('COMBO x$combo');
      HapticFeedback.selectionClick();
      sfx.play('match${min(combo - 1, 5)}');
    }

    final tiles = [for (final p in toClear) grid[p.x][p.y]!];
    final big = perfects > 0 || bombs > 0 || label != null;
    for (final t in tiles) {
      _burst(t, big ? 16 : 9);
    }
    await _anim(220, Curves.easeIn, (f) {
      for (final t in tiles) {
        t.scale = 1 - f;
        t.alpha = 1 - f;
      }
    });
    for (final p in toClear) {
      grid[p.x][p.y] = null;
    }
    if (survivors.isNotEmpty) {
      survivors.forEach((p, kind) {
        final t = grid[p.x][p.y];
        if (t == null) return;
        t.special = kind;
        t.scale = 0.5;
        unawaited(_scaleTo(t, 1));
      });
      sfx.play('spawn');
    }
    await _collapse();
  }

  Future<void> _collapse() async {
    final targets = <(Tile, double, double)>[];
    for (var x = 0; x < n; x++) {
      var write = n - 1;
      for (var y = n - 1; y >= 0; y--) {
        final t = grid[x][y];
        if (t == null) continue;
        if (y != write) {
          grid[x][y] = null;
          grid[x][write] = t;
          targets.add((t, x.toDouble(), write.toDouble()));
        }
        write--;
      }
      final missing = write + 1;
      for (var y = write; y >= 0; y--) {
        final t = Tile(_rng.nextInt(colorCount), 1 + _rng.nextInt(numCount), x.toDouble(),
            (y - missing).toDouble());
        grid[x][y] = t;
        targets.add((t, x.toDouble(), y.toDouble()));
      }
    }
    await _moveTiles(targets, 400, Curves.bounceOut);
  }

  Future<void> _finishTurn() async {
    if (moves <= 0) {
      gameOver = true;
      sfx.play('over');
      if (score > best) {
        best = score;
        _prefs?.setInt('best', best);
      }
      busy = false;
      notifyListeners();
      return;
    }
    if (!hasMoves()) {
      showMessage('No moves left\nShuffling...');
      sfx.play('shuffle');
      _reshuffleInstant();
      final all = [for (var x = 0; x < n; x++) for (var y = 0; y < n; y++) grid[x][y]!];
      for (final t in all) {
        t.scale = 0;
      }
      await _anim(350, Curves.easeOutBack, (f) {
        for (final t in all) {
          t.scale = f;
        }
      });
    }
    busy = false;
    notifyListeners();
  }

  // ===================================================================
  // Animation helpers
  // ===================================================================

  Future<void> _anim(int ms, Curve curve, void Function(double) update) async {
    final sw = Stopwatch()..start();
    while (true) {
      final t = (sw.elapsedMilliseconds / ms).clamp(0.0, 1.0);
      update(curve.transform(t));
      notifyListeners();
      if (t >= 1) break;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _moveTiles(List<(Tile, double, double)> targets, int ms, Curve curve) async {
    if (targets.isEmpty) return;
    final sx = [for (final t in targets) t.$1.x];
    final sy = [for (final t in targets) t.$1.y];
    await _anim(ms, curve, (f) {
      for (var i = 0; i < targets.length; i++) {
        final (tile, tx, ty) = targets[i];
        tile.x = sx[i] + (tx - sx[i]) * f;
        tile.y = sy[i] + (ty - sy[i]) * f;
      }
    });
  }

  Future<void> _scaleTo(Tile t, double target) {
    final from = t.scale;
    return _anim(120, Curves.decelerate, (f) => t.scale = from + (target - from) * f);
  }

  void showMessage(String msg) {
    message = msg;
    final id = ++_msgId;
    unawaited(_anim(1100, Curves.easeInOut, (f) {
      messageAlpha = f < 0.6 ? 1 : 1 - (f - 0.6) / 0.4;
      messageScale = 0.7 + 0.3 * min(1.0, f * 5);
    }).then((_) {
      if (id == _msgId) {
        message = null;
        notifyListeners();
      }
    }));
  }

  void _burst(Tile t, int count) {
    for (var i = 0; i < count; i++) {
      final ang = _rng.nextDouble() * 2 * pi;
      final sp = 1.5 + _rng.nextDouble() * 4.0;
      particles.add(Particle(t.x + 0.5, t.y + 0.5, cos(ang) * sp, sin(ang) * sp - 1.5, 0.6, t.color));
    }
    if (!_particleLoop) unawaited(_runParticles());
  }

  Future<void> _runParticles() async {
    _particleLoop = true;
    final sw = Stopwatch()..start();
    var last = 0.0;
    while (particles.isNotEmpty) {
      await WidgetsBinding.instance.endOfFrame;
      final now = sw.elapsedMicroseconds / 1e6;
      final dt = min(0.05, now - last);
      last = now;
      for (final p in particles) {
        p.life -= dt;
        p.vy += 11 * dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
      particles.removeWhere((p) => p.life <= 0);
      notifyListeners();
    }
    _particleLoop = false;
  }

  // ===================================================================
  // Input (positions are board-local pixels; `cell` is the cell size in px)
  // ===================================================================

  Pt? _cellAt(Offset p, double cell) {
    final x = (p.dx / cell).floor(), y = (p.dy / cell).floor();
    if (p.dx < 0 || p.dy < 0 || x >= n || y >= n) return null;
    return Pt(x, y);
  }

  void _select(Pt? p) {
    final old = selected;
    if (old != null && grid[old.x][old.y] != null) unawaited(_scaleTo(grid[old.x][old.y]!, 1));
    selected = p;
    if (p != null && grid[p.x][p.y] != null) unawaited(_scaleTo(grid[p.x][p.y]!, 1.15));
  }

  void pointerDown(Offset p, double cell) {
    if (busy || gameOver) return;
    final c = _cellAt(p, cell);
    if (c == null) return;
    final s = selected;
    if (s != null && (s.x - c.x).abs() + (s.y - c.y).abs() == 1) {
      _select(null);
      unawaited(trySwap(s, c));
      return;
    }
    _select(c);
    _down = p;
    _dragging = true;
  }

  void pointerMove(Offset p, double cell) {
    final s = selected;
    if (!_dragging || busy || gameOver || s == null) return;
    final d = p - _down;
    if (d.distance < cell * 0.35) return;
    _dragging = false;
    final target = d.dx.abs() > d.dy.abs()
        ? Pt(s.x + (d.dx > 0 ? 1 : -1), s.y)
        : Pt(s.x, s.y + (d.dy > 0 ? 1 : -1));
    _select(null);
    if (target.x >= 0 && target.x < n && target.y >= 0 && target.y < n) {
      unawaited(trySwap(s, target));
    }
  }

  void pointerUp() => _dragging = false;
}
