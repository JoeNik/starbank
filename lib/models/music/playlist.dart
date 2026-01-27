import 'package:hive/hive.dart';
import 'music_track.dart';

part 'playlist.g.dart';

@HiveType(typeId: 21)
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
}
