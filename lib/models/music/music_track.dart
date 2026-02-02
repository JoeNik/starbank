import 'package:hive/hive.dart';

part 'music_track.g.dart';

// 修复 typeId 冲突: 之前使用 20 与 QuizConfig 冲突,改为 30
@HiveType(typeId: 30)
class MusicTrack extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String artist;

  @HiveField(3)
  String? album;

  @HiveField(4)
  String? coverUrl;

  @HiveField(5)
  String? url; // Playable URL (might expire, but good for cache)

  @HiveField(6)
  int? durationMs;

  @HiveField(7)
  String platform; // 'kuwo', 'netease', etc.

  @HiveField(8)
  String? lyricUrl;

  @HiveField(9)
  String? lyricContent;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.url,
    this.durationMs,
    required this.platform,
    this.lyricUrl,
    this.lyricContent,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'url': url,
        'durationMs': durationMs,
        'platform': platform,
        'lyricUrl': lyricUrl,
        'lyricContent': lyricContent,
      };

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        id: json['id'] ?? '',
        title: json['title'] ?? 'Unknown',
        artist: json['artist'] ?? 'Unknown',
        album: json['album'],
        coverUrl: json['coverUrl'],
        url: json['url'],
        durationMs: json['durationMs'],
        platform: json['platform'] ?? 'unknown',
        lyricUrl: json['lyricUrl'],
        lyricContent: json['lyricContent'],
      );
}
