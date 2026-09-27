import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// 棋妙岛音效：参照原型 WebAudio 合成思路，
/// 在内存里合成 16bit PCM WAV，用 just_audio 的 StreamAudioSource 播放，
/// 无需新增任何资源文件。
class WqSfx {
  WqSfx._();

  static AudioPlayer? _player;
  static bool enabled = true;

  static const int _rate = 22050;

  /// 落子：低频短促「嗒」
  static void stone() => _play([
        _Tone(190, 0.07, 'triangle', 0.30),
        _Tone(540, 0.035, 'square', 0.06, delay: 0.008),
      ]);

  /// 轻点/翻页「啵」
  static void pop() => _play([
        _Tone(660, 0.08, 'sine', 0.20),
        _Tone(920, 0.09, 'sine', 0.13, delay: 0.05),
      ]);

  /// 得星/庆祝：上行琶音
  static void star() => _play([
        _Tone(660, 0.13, 'sine', 0.14),
        _Tone(830, 0.13, 'sine', 0.14, delay: 0.07),
        _Tone(1040, 0.13, 'sine', 0.14, delay: 0.14),
      ]);

  /// 提子：上行三连音
  static void capture() => _play([
        _Tone(290, 0.10, 'triangle', 0.24),
        _Tone(430, 0.11, 'triangle', 0.20, delay: 0.06),
        _Tone(640, 0.15, 'sine', 0.14, delay: 0.13),
      ]);

  /// 差一点点：下行「唔唔」
  static void oops() => _play([
        _Tone(330, 0.11, 'sine', 0.13),
        _Tone(245, 0.16, 'sine', 0.13, delay: 0.09),
      ]);

  static void _play(List<_Tone> tones) {
    if (!enabled) return;
    try {
      final total = tones.fold<double>(0, (t, x) => max(t, x.delay + x.dur));
      final n = (total * _rate).ceil() + _rate ~/ 20;
      final mix = Float64List(n);
      for (final t in tones) {
        _renderTone(mix, t);
      }
      final bytes = _wavBytes(mix);
      final player = _player ??= AudioPlayer();
      player.stop().then((_) => player.setAudioSource(_ToneSource(bytes))).then((_) {
        player.play();
      }).catchError((_) {});
    } catch (_) {
      // 音效失败不影响功能
    }
  }

  static void _renderTone(Float64List mix, _Tone t) {
    final start = (t.delay * _rate).floor();
    final len = (t.dur * _rate).ceil();
    for (var k = 0; k < len && start + k < mix.length; k++) {
      final phase = 2 * pi * t.freq * k / _rate;
      double v;
      switch (t.type) {
        case 'square':
          v = sin(phase) > 0 ? 1.0 : -1.0;
          break;
        case 'triangle':
          v = 2 / pi * asin(sin(phase));
          break;
        default:
          v = sin(phase);
      }
      // 指数衰减包络，末尾 3ms 收到 0 防爆音
      final env = exp(-4.5 * k / len) * min(1.0, (len - k) / (_rate * 0.003));
      mix[start + k] += v * t.gain * env;
    }
  }

  static Uint8List _wavBytes(Float64List samples) {
    final data = BytesBuilder();
    for (final v in samples) {
      final clamped = v.clamp(-1.0, 1.0);
      final int16 = (clamped * 32767).round();
      data.addByte(int16 & 0xff);
      data.addByte((int16 >> 8) & 0xff);
    }
    final pcm = data.takeBytes();
    final out = BytesBuilder();
    final dataLen = pcm.length;
    // RIFF 头
    out.add(utf8.encode('RIFF'));
    _addU32(out, 36 + dataLen);
    out.add(utf8.encode('WAVE'));
    out.add(utf8.encode('fmt '));
    _addU32(out, 16);
    _addU16(out, 1); // PCM
    _addU16(out, 1); // mono
    _addU32(out, _rate);
    _addU32(out, _rate * 2);
    _addU16(out, 2);
    _addU16(out, 16);
    out.add(utf8.encode('data'));
    _addU32(out, dataLen);
    out.add(pcm);
    return out.takeBytes();
  }

  static void _addU32(BytesBuilder b, int v) {
    b.addByte(v & 0xff);
    b.addByte((v >> 8) & 0xff);
    b.addByte((v >> 16) & 0xff);
    b.addByte((v >> 24) & 0xff);
  }

  static void _addU16(BytesBuilder b, int v) {
    b.addByte(v & 0xff);
    b.addByte((v >> 8) & 0xff);
  }
}

class _Tone {
  final double freq;
  final double dur;
  final String type;
  final double gain;
  final double delay;

  const _Tone(this.freq, this.dur, this.type, this.gain, {this.delay = 0});
}

class _ToneSource extends StreamAudioSource {
  final Uint8List bytes;

  _ToneSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? bytes.length;
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: bytes.length,
      contentLength: e - s,
      offset: s,
      contentType: 'audio/wav',
      stream: Stream.value(bytes.sublist(s, e)),
    );
  }
}
