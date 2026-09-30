import 'package:intl/intl.dart';

/// WhatsApp-style relative timestamp: time today, "Yesterday", weekday for
/// the past week, then a short date. Used by conversation tiles and bubbles.
String formatChatTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(time.year, time.month, time.day);
  final diffDays = today.difference(day).inDays;

  if (diffDays <= 0) return DateFormat('HH:mm').format(time);
  if (diffDays == 1) return 'Yesterday';
  if (diffDays < 7) return DateFormat('EEE').format(time);
  if (time.year == n.year) return DateFormat('MMM d').format(time);
  return DateFormat('dd/MM/yyyy').format(time);
}
