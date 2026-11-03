import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'board_painter.dart';
import 'game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final game = GameController();
  await game.init();
  runApp(GemPopApp(game: game));
}

class GemPopApp extends StatelessWidget {
  final GameController game;
  const GemPopApp({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gem Pop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: GamePage(game: game),
    );
  }
}

class GamePage extends StatefulWidget {
  final GameController game;
  const GamePage({super.key, required this.game});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  GameController get game => widget.game;

  @override
  void dispose() {
    _clock.dispose();
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2B1F5C), Color(0xFF0B0720)],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: game,
            builder: (context, _) => Stack(
              children: [
                Column(
                  children: [
                    _header(),
                    Expanded(child: Center(child: _board())),
                    _legend(),
                  ],
                ),
                if (game.flash > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: Colors.white.withAlpha((game.flash * 90).toInt())),
                    ),
                  ),
                if (game.message != null) _message(),
                if (game.gameOver) _gameOver(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    const gold = Color(0xFFFFD23F);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 96),
              const Expanded(
                child: Text('GEM POP',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: gold)),
              ),
              SizedBox(
                width: 96,
                child: TextButton(
                  onPressed: game.toggleSound,
                  child: Text(game.sfx.enabled ? 'SOUND ON' : 'SOUND OFF',
                      style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ),
            ],
          ),
          const Text('SCORE', style: TextStyle(fontSize: 13, color: Colors.white60)),
          Text('${game.score}', style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('MOVES  ${game.moves}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4CC9F0))),
              Text('BEST  ${game.best > game.score ? game.best : game.score}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3DDC97))),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _board() {
    return LayoutBuilder(builder: (context, box) {
      const pad = 10.0;
      final side = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) - 2 * pad - 16;
      if (side <= 0) return const SizedBox.shrink();
      final cell = side / GameController.n;
      return Container(
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(95),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Listener(
          onPointerDown: (e) => game.pointerDown(e.localPosition, cell),
          onPointerMove: (e) => game.pointerMove(e.localPosition, cell),
          onPointerUp: (_) => game.pointerUp(),
          onPointerCancel: (_) => game.pointerUp(),
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(painter: BoardPainter(game, _clock)),
          ),
        ),
      );
    });
  }

  Widget _legend() {
    const style = TextStyle(fontSize: 12, color: Colors.white70);
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Match 3+ by COLOR or by NUMBER', style: style, textAlign: TextAlign.center),
          Text('Same color + number = PERFECT: row & column clear, +2 moves',
              style: TextStyle(fontSize: 12, color: Color(0xFFFFD23F)), textAlign: TextAlign.center),
          Text('Match 4 = BOMB (3x3)   Match 5 = RAINBOW (swap: clear a color)',
              style: style, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _message() {
    final lines = game.message!.split('\n');
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: game.messageAlpha.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: game.messageScale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final l in lines)
                    Text(l,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFD23F),
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
                        )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameOver() {
    final newBest = game.score >= game.best && game.score > 0;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withAlpha(185),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('GAME OVER', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Score ${game.score}', style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(newBest ? 'New best!' : 'Best ${game.best}',
                  style: const TextStyle(fontSize: 20, color: Color(0xFF3DDC97))),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9B6DFF),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                ),
                onPressed: game.newGame,
                child: const Text('PLAY AGAIN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
