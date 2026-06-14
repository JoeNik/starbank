import '../models/baby.dart';

class BabyProfileUtils {
  const BabyProfileUtils._();

  static String ageText(Baby baby, {DateTime? now}) {
    final birthDate = baby.birthDate;
    if (birthDate == null) return '未设置生日';
    final today = now ?? DateTime.now();
    if (birthDate.isAfter(today)) return '生日在未来';

    var years = today.year - birthDate.year;
    var months = today.month - birthDate.month;
    var days = today.day - birthDate.day;

    if (days < 0) {
      months -= 1;
      final previousMonth = DateTime(today.year, today.month, 0);
      days += previousMonth.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    final parts = <String>[];
    if (years > 0) parts.add('$years岁');
    if (months > 0) parts.add('$months个月');
    parts.add('$days天');
    return parts.join('');
  }

  static int ageMonths(Baby baby, DateTime atDate) {
    final birthDate = baby.birthDate;
    if (birthDate == null || birthDate.isAfter(atDate)) return -1;
    var months =
        (atDate.year - birthDate.year) * 12 + atDate.month - birthDate.month;
    if (atDate.day < birthDate.day) months -= 1;
    return months;
  }

  static String genderText(String gender) {
    switch (gender) {
      case 'male':
        return '男孩';
      case 'female':
        return '女孩';
      default:
        return '未设置';
    }
  }
}
