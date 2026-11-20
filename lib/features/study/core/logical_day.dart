/// Logical day helpers. A logical day starts at 4:00; 0:00–3:59 belongs to the
/// previous day. Times are mapped to minute offsets in [0, 1440) from 4:00, so a
/// block like 23:00–01:00 needs no special handling.
abstract final class LogicalDay {
  static const originMinutes = 4 * 60;
  static const minutesPerDay = 24 * 60;

  /// Clock time → offset in [0, 1440).
  static int toOffset(int hour, int minute) =>
      ((hour * 60 + minute - originMinutes) % minutesPerDay + minutesPerDay) %
      minutesPerDay;

  /// Clock time used as a block *end* → offset in (0, 1440]. 4:00 means the end
  /// of the logical day (1440), never 0.
  static int toEndOffset(int hour, int minute) {
    final o = toOffset(hour, minute);
    return o == 0 ? minutesPerDay : o;
  }

  static int offsetOf(DateTime t) => toOffset(t.hour, t.minute);

  /// The logical date (local midnight) that [t] belongs to.
  static DateTime dateOf(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return t.hour < 4 ? DateTime(d.year, d.month, d.day - 1) : d;
  }

  /// Offset on [logicalDate] → real local time.
  static DateTime toDateTime(DateTime logicalDate, int offset) => DateTime(
    logicalDate.year,
    logicalDate.month,
    logicalDate.day,
    4,
    offset,
  );

  /// Offset → "H:MM" clock label.
  static String clock(int offset) {
    final m = (offset + originMinutes) % minutesPerDay;
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Offset → (hour, minute) on the clock.
  static (int, int) clockParts(int offset) {
    final m = (offset + originMinutes) % minutesPerDay;
    return (m ~/ 60, m % 60);
  }

  /// 0 = Sunday … 6 = Saturday (same as the Android app).
  static int weekdayOf(DateTime logicalDate) => logicalDate.weekday % 7;

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDateKey(String key) {
    final p = key.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);
}
