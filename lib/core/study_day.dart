/// A study day starts at the configured local hour, including across DST.
DateTime studyDay(DateTime time, {int resetHour = 4}) {
  final local = time.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return local.hour < resetHour
      ? DateTime(local.year, local.month, local.day - 1)
      : day;
}

String studyDayKey(DateTime time, {int resetHour = 4}) {
  final day = studyDay(time, resetHour: resetHour);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime nextStudyDayBoundary(DateTime time, {int resetHour = 4}) {
  final local = time.toLocal();
  final boundary = DateTime(local.year, local.month, local.day, resetHour);
  return boundary.isAfter(local)
      ? boundary
      : DateTime(local.year, local.month, local.day + 1, resetHour);
}
