import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Sound effects synthesized in code and played from memory (no audio assets).
class SoundFx {
  bool enabled = true;

  static const int _rate = 22050;
  final Map<String, Uint8List> _wav = {};
  final Map<String, AudioPlayer> _players = {};
  final Random _rng = Random();

  SoundFx() {
    _add('swap', _tone(500, 760, 70, 0.45));
    _add('bad', _tone(220, 130, 170, 0.5));
    for (var i = 0; i <= 5; i++) {
      _add('match$i', _tone(523 * pow(1.12, i).toDouble(), 640 * pow(1.12, i).toDouble(), 150, 0.5));
    }
    _add(
        'perfect',
        _concat([
          _tone(523, 523, 90, 0.5),
          _tone(659, 659, 90, 0.5),
          _tone(784, 784, 90, 0.5),
          _tone(1047, 1047, 260, 0.55),
        ]));
    _add('boom', _boom(420));
    _add('rainbow', _concat([_tone(300, 1500, 380, 0.5), _tone(1500, 1500, 120, 0.4)]));
    _add('spawn', _concat([_tone(800, 1200, 90, 0.45), _tone(1200, 1600, 120, 0.45)]));
    _add('shuffle', _tone(400, 900, 220, 0.4));
    _add(
        'over',
        _concat([
          _tone(440, 440, 160, 0.5),
          _tone(349, 349, 160, 0.5),
          _tone(262, 262, 380, 0.5),
        ]));
  }

  void play(String name) {
    if (!enabled) return;
    final bytes = _wav[name];
    if (bytes == null) return;
    try {
      final player = _players.putIfAbsent(name, () {
        final p = AudioPlayer();
        unawaited(p.setPlayerMode(PlayerMode.lowLatency).catchError((_) {}));
        return p;
      });
      unawaited(player.play(BytesSource(bytes)).catchError((_) {}));
    } catch (_) {}
  }

  void dispose() {
    for (final p in _players.values) {
      unawaited(p.dispose().catchError((_) {}));
    }
    _players.clear();
  }

  void _add(String name, List<int> pcm) => _wav[name] = _toWav(pcm);

  List<int> _tone(double f0, double f1, int ms, double vol) {
    final n = _rate * ms ~/ 1000;
    final out = List<int>.filled(n, 0);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      phase += 2 * pi * (f0 + (f1 - f0) * t) / _rate;
      final attack = min(1.0, i / (_rate * 0.004));
      final env = attack * pow(1 - t, 1.4);
      final s = sin(phase) + 0.3 * sin(2 * phase);
      out[i] = (s * env * vol * 0.75 * 32767).round().clamp(-32767, 32767);
    }
    return out;
  }

  List<int> _boom(int ms) {
    final n = _rate * ms ~/ 1000;
    final out = List<int>.filled(n, 0);
    var low = 0.0;
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      low += 0.18 * ((_rng.nextDouble() * 2 - 1) - low);
      phase += 2 * pi * (110 - 70 * t) / _rate;
      final env = pow(1 - t, 2.0);
      final s = low * 1.6 + sin(phase) * 0.6;
      out[i] = (s * env * 0.8 * 32767).round().clamp(-32767, 32767);
    }
    return out;
  }

  List<int> _concat(List<List<int>> parts) => [for (final p in parts) ...p];

  /// Wraps 16-bit mono PCM in a WAV container.
  Uint8List _toWav(List<int> pcm) {
    final dataLen = pcm.length * 2;
    final b = ByteData(44 + dataLen);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, _rate, Endian.little);
    b.setUint32(28, _rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      b.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
