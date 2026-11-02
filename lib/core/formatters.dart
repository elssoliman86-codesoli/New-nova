const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Limits [value] to the range [min]..[max].
double clampTo(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Stable key such as `2026-11-01`, used to group activity by day.
String dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$m-$day';
}

String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];

/// `mm:ss` for a countdown. Negative values are shown as zero.
String formatTimerSeconds(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String formatTimer(Duration d) => formatTimerSeconds(d.inSeconds);

/// `25m`, `1h`, `1h 30m`.
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  if (h < 22) return 'Good evening';
  return 'Good night';
}

bool isOverdue(DateTime due, DateTime now) =>
    startOfDay(due).isBefore(startOfDay(now));

/// `Today`, `Tomorrow`, `Yesterday`, otherwise `Mon, 3 Nov`.
String formatDue(DateTime? due, {DateTime? now}) {
  if (due == null) return 'No date';
  final today = startOfDay(now ?? DateTime.now());
  final day = startOfDay(due);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${weekdayShort(day)}, ${day.day} ${_months[day.month - 1]}';
}

String formatDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

String timeAgo(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(time);
}
