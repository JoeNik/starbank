import 'package:hive/hive.dart';
import 'music_track.dart';

part 'playlist.g.dart';

// 修复 typeId 冲突: 之前使用 21 与 QuizQuestion 冲突,改为 31
@HiveType(typeId: 31)
class Playlist extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? coverUrl;

  @HiveField(3)
  List<MusicTrack> tracks;

  @HiveField(4)
  DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.tracks,
    required this.createdAt,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coverUrl': coverUrl,
        'tracks': tracks.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        coverUrl: json['coverUrl'] as String?,
        tracks: (json['tracks'] as List<dynamic>?)
                ?.map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
