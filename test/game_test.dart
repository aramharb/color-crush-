import 'package:color_crush/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new board has no matches and at least one move', () {
    for (var i = 0; i < 20; i++) {
      final g = GameController()..newGame();
      expect(g.findMatches().cleared, isEmpty);
      expect(g.hasMoves(), isTrue);
      expect(g.moves, GameController.startMoves);
    }
  });

  test('detects color run, number run and perfect match', () {
    final g = GameController()..newGame();
    // Clear to a known pattern with no accidental runs.
    for (var x = 0; x < 8; x++) {
      for (var y = 0; y < 8; y++) {
        g.grid[x][y] = Tile((x + 2 * y) % 5, 1 + (3 * x + y) % 5, x.toDouble(), y.toDouble());
      }
    }
    expect(g.findMatches().cleared, isEmpty);

    // color run (different numbers)
    for (var x = 0; x < 3; x++) {
      g.grid[x][0] = Tile(0, 1 + x, x.toDouble(), 0);
    }
    var m = g.findMatches();
    expect(m.cleared.length, 3);
    expect(m.totals, isEmpty);

    // perfect: same color and number
    for (var x = 0; x < 3; x++) {
      g.grid[x][0] = Tile(0, 4, x.toDouble(), 0);
    }
    m = g.findMatches();
    expect(m.totals, {const Pt(1, 0)});

    // 4 in a row -> bomb spawn, 5 -> rainbow spawn
    for (var x = 0; x < 4; x++) {
      g.grid[x][0] = Tile(0, 4, x.toDouble(), 0);
    }
    expect(g.findMatches().spawns.values, contains(GameController.bomb));
    for (var x = 0; x < 5; x++) {
      g.grid[x][0] = Tile(0, 4, x.toDouble(), 0);
    }
    expect(g.findMatches().spawns.values, contains(GameController.rainbow));
  });
}
