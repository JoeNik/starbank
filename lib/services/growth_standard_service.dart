import '../models/baby.dart';
import '../utils/baby_profile_utils.dart';

enum GrowthMetric {
  height,
  weight,
  headCircumference,
}

class GrowthStandardBand {
  final double ageMonths;
  final double low;
  final double median;
  final double high;
  final String sourceLabel;

  const GrowthStandardBand({
    required this.ageMonths,
    required this.low,
    required this.median,
    required this.high,
    required this.sourceLabel,
  });
}

class GrowthStandardService {
  const GrowthStandardService._();

  static const sourceTitle = '国家卫健委儿童生长标准';
  static const sourceDescription = '《7岁以下儿童生长标准》';

  static List<GrowthStandardBand> bandsFor({
    required Baby baby,
    required GrowthMetric metric,
  }) {
    if (baby.gender != 'male' && baby.gender != 'female') return const [];
    final data = _tableFor(metric, baby.gender);
    return data
        .map((row) => GrowthStandardBand(
              ageMonths: row[0].toDouble(),
              low: row[1].toDouble(),
              median: row[2].toDouble(),
              high: row[3].toDouble(),
              sourceLabel: sourceTitle,
            ))
        .toList();
  }

  static GrowthStandardBand? bandAt({
    required Baby baby,
    required DateTime recordDate,
    required GrowthMetric metric,
  }) {
    final month = BabyProfileUtils.ageMonths(baby, recordDate);
    if (month < 0) return null;
    return bandAtAgeMonths(
      baby: baby,
      metric: metric,
      ageMonths: month.toDouble(),
    );
  }

  static GrowthStandardBand? bandAtAgeMonths({
    required Baby baby,
    required GrowthMetric metric,
    required double ageMonths,
  }) {
    final bands = bandsFor(baby: baby, metric: metric);
    if (bands.isEmpty) return null;
    if (ageMonths < bands.first.ageMonths || ageMonths > bands.last.ageMonths) {
      return null;
    }
    for (var i = 0; i < bands.length - 1; i++) {
      final a = bands[i];
      final b = bands[i + 1];
      if (ageMonths >= a.ageMonths && ageMonths <= b.ageMonths) {
        final span = b.ageMonths - a.ageMonths;
        final t = span == 0 ? 0 : (ageMonths - a.ageMonths) / span;
        double lerp(double x, double y) => x + (y - x) * t;
        return GrowthStandardBand(
          ageMonths: ageMonths,
          low: lerp(a.low, b.low),
          median: lerp(a.median, b.median),
          high: lerp(a.high, b.high),
          sourceLabel: sourceTitle,
        );
      }
    }
    return bands.last;
  }

  static String unavailableReason(GrowthMetric metric, int ageMonths) {
    if (ageMonths < 0) return '请先设置生日和性别后查看国家标准曲线';
    switch (metric) {
      case GrowthMetric.height:
      case GrowthMetric.weight:
        if (ageMonths > 72) return '国家标准暂未覆盖 6 岁以上曲线';
        break;
      case GrowthMetric.headCircumference:
        if (ageMonths > 60) return '国家标准头围曲线暂未覆盖 5 岁以上';
        break;
    }
    return '请先设置生日和性别后查看国家标准曲线';
  }

  static List<List<num>> _tableFor(GrowthMetric metric, String gender) {
    final male = gender == 'male';
    switch (metric) {
      case GrowthMetric.height:
        return male ? _heightMale : _heightFemale;
      case GrowthMetric.weight:
        return male ? _weightMale : _weightFemale;
      case GrowthMetric.headCircumference:
        return male ? _headMale : _headFemale;
    }
  }

  // 国家卫健委儿童生长标准常用检查点，列为：月龄、3%、50%、97%。
  // 0-6 月逐月，之后按标准随访常用月龄给出；曲线绘制时做线性插值。
  static const _heightMale = [
    [0, 46.9, 50.4, 54.0],
    [1, 50.7, 54.8, 59.0],
    [2, 54.3, 58.7, 63.3],
    [3, 57.5, 62.0, 66.6],
    [4, 60.1, 64.6, 69.3],
    [5, 62.1, 66.7, 71.5],
    [6, 63.7, 68.4, 73.3],
    [8, 66.3, 71.2, 76.3],
    [10, 68.9, 74.0, 79.3],
    [12, 71.2, 76.5, 82.1],
    [15, 74.0, 79.8, 85.8],
    [18, 76.6, 82.7, 89.1],
    [21, 79.1, 85.6, 92.4],
    [24, 81.6, 88.5, 95.8],
    [30, 86.9, 94.3, 102.1],
    [36, 92.4, 100.2, 108.3],
    [42, 97.2, 105.4, 113.8],
    [48, 101.8, 110.3, 119.0],
    [54, 106.2, 115.0, 123.9],
    [60, 109.8, 118.9, 128.2],
    [66, 113.3, 122.7, 132.4],
    [72, 116.0, 125.8, 135.8],
  ];

  static const _heightFemale = [
    [0, 46.4, 49.7, 53.2],
    [1, 49.8, 53.7, 57.8],
    [2, 53.2, 57.4, 61.8],
    [3, 56.3, 60.6, 65.1],
    [4, 58.8, 63.1, 67.7],
    [5, 60.8, 65.2, 69.8],
    [6, 62.3, 66.8, 71.5],
    [8, 64.7, 69.4, 74.3],
    [10, 67.2, 72.1, 77.3],
    [12, 69.7, 75.0, 80.5],
    [15, 72.9, 78.5, 84.3],
    [18, 75.6, 81.5, 87.7],
    [21, 78.1, 84.4, 91.1],
    [24, 80.5, 87.2, 94.3],
    [30, 85.7, 92.9, 100.3],
    [36, 91.0, 98.7, 106.7],
    [42, 95.6, 103.7, 112.0],
    [48, 100.2, 108.6, 117.2],
    [54, 104.4, 113.2, 122.2],
    [60, 108.5, 117.7, 127.2],
    [66, 112.2, 121.7, 131.7],
    [72, 115.7, 125.7, 136.1],
  ];

  static const _weightMale = [
    [0, 2.58, 3.32, 4.18],
    [1, 3.52, 4.51, 5.67],
    [2, 4.47, 5.68, 7.14],
    [3, 5.29, 6.70, 8.40],
    [4, 5.91, 7.45, 9.32],
    [5, 6.36, 8.00, 9.99],
    [6, 6.70, 8.41, 10.50],
    [8, 7.23, 9.05, 11.29],
    [10, 7.67, 9.58, 11.95],
    [12, 8.06, 10.05, 12.54],
    [15, 8.57, 10.68, 13.32],
    [18, 9.07, 11.29, 14.09],
    [21, 9.59, 11.93, 14.90],
    [24, 10.09, 12.54, 15.67],
    [30, 10.97, 13.64, 17.06],
    [36, 11.79, 14.65, 18.37],
    [42, 12.55, 15.63, 19.68],
    [48, 13.24, 16.64, 21.01],
    [54, 13.93, 17.46, 22.21],
    [60, 14.66, 18.37, 23.50],
    [66, 15.30, 19.27, 24.74],
    [72, 15.87, 20.26, 26.15],
  ];

  static const _weightFemale = [
    [0, 2.54, 3.21, 4.10],
    [1, 3.33, 4.20, 5.35],
    [2, 4.15, 5.21, 6.60],
    [3, 4.90, 6.13, 7.73],
    [4, 5.48, 6.83, 8.59],
    [5, 5.92, 7.36, 9.23],
    [6, 6.26, 7.77, 9.73],
    [8, 6.79, 8.41, 10.51],
    [10, 7.23, 8.94, 11.16],
    [12, 7.61, 9.40, 11.73],
    [15, 8.12, 10.02, 12.50],
    [18, 8.63, 10.65, 13.30],
    [21, 9.15, 11.30, 14.12],
    [24, 9.64, 11.92, 14.92],
    [30, 10.52, 13.05, 16.46],
    [36, 11.34, 14.13, 17.92],
    [42, 12.10, 15.16, 19.34],
    [48, 12.80, 16.17, 20.80],
    [54, 13.47, 17.18, 22.18],
    [60, 14.11, 18.26, 23.73],
    [66, 14.74, 19.33, 25.29],
    [72, 15.31, 20.37, 26.87],
  ];

  static const _headMale = [
    [0, 32.1, 34.5, 36.8],
    [1, 34.5, 36.9, 39.4],
    [2, 36.4, 38.9, 41.5],
    [3, 37.9, 40.5, 43.2],
    [4, 39.2, 41.7, 44.5],
    [5, 40.2, 42.7, 45.5],
    [6, 41.0, 43.6, 46.3],
    [8, 42.2, 44.8, 47.5],
    [10, 43.1, 45.7, 48.4],
    [12, 43.8, 46.4, 49.1],
    [15, 44.5, 47.1, 49.8],
    [18, 45.0, 47.6, 50.2],
    [21, 45.5, 48.0, 50.7],
    [24, 45.9, 48.4, 51.1],
    [30, 46.6, 49.2, 51.9],
    [36, 47.0, 49.7, 52.3],
    [42, 47.5, 50.1, 52.7],
    [48, 47.8, 50.4, 53.1],
    [54, 48.2, 50.8, 53.4],
    [60, 48.5, 51.1, 53.7],
  ];

  static const _headFemale = [
    [0, 31.6, 33.9, 36.2],
    [1, 33.8, 36.2, 38.6],
    [2, 35.6, 38.0, 40.5],
    [3, 37.1, 39.5, 42.1],
    [4, 38.3, 40.7, 43.3],
    [5, 39.3, 41.6, 44.3],
    [6, 40.1, 42.4, 45.1],
    [8, 41.2, 43.6, 46.3],
    [10, 42.1, 44.5, 47.2],
    [12, 42.7, 45.1, 47.8],
    [15, 43.4, 45.8, 48.5],
    [18, 43.9, 46.4, 49.1],
    [21, 44.4, 46.9, 49.6],
    [24, 44.8, 47.3, 50.0],
    [30, 45.5, 48.0, 50.7],
    [36, 46.0, 48.5, 51.2],
    [42, 46.5, 49.0, 51.6],
    [48, 46.9, 49.4, 52.0],
    [54, 47.2, 49.7, 52.3],
    [60, 47.5, 50.0, 52.6],
  ];
}
