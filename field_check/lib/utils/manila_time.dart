import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime toManilaTime(DateTime dt) {
  return dt.toLocal();
}

DateTime manilaNow() => toManilaTime(DateTime.now());

String formatManila(DateTime? dt, String pattern) {
  if (dt == null) return '-';
  return DateFormat(pattern).format(toManilaTime(dt));
}

String formatManilaTimeOfDay(BuildContext context, DateTime? dt) {
  if (dt == null) return '-';
  return TimeOfDay.fromDateTime(toManilaTime(dt)).format(context);
}

String greetingManila({DateTime? now}) {
  final dt = toManilaTime(now ?? DateTime.now());
  final hour = dt.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String formatManilaClock({DateTime? now}) {
  final dt = toManilaTime(now ?? DateTime.now());
  return DateFormat('HH:mm').format(dt);
}
