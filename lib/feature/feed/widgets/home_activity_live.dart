import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../l10n/strings.dart';

/// Mini index.js fmtRemain: a known start at/before now is LIVE. This marker
/// deliberately does not introduce an end-date or ticket-status condition.
bool homeActivityStarted(String? startDate, DateTime now) {
  final start = homeActivityStart(startDate);
  return start != null && !now.isBefore(start);
}

/// Mirrors mini utils/datetime.toTimestamp for the string startDate contract:
/// bare timestamps use China time; explicit offsets keep their instant.
DateTime? homeActivityStart(String? raw) {
  final text = (raw ?? '').trim();
  if (RegExp(r'^(\d{10}|\d{13})$').hasMatch(text)) {
    final value = int.parse(text);
    if (value == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      text.length == 10 ? value * 1000 : value,
      isUtc: true,
    );
  }
  final offset = RegExp(r'[zZ]$|[+-]\d\d:?\d\d$').hasMatch(text);
  final pattern = offset
      ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d\d:?\d\d)$', caseSensitive: false)
      : RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.\d{1,9})?)?)?$');
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  final parts = List.generate(6, (i) => int.parse(match.group(i + 1) ?? '0'));
  final calendar = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  if (calendar.year != parts[0] || calendar.month != parts[1] ||
      calendar.day != parts[2] || calendar.hour != parts[3] ||
      calendar.minute != parts[4] || calendar.second != parts[5]) return null;
  if (!offset) return calendar.subtract(const Duration(hours: 8));
  final zone = match.group(7)!.replaceAll(':', '');
  if (zone.toUpperCase() != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 || int.parse(zone.substring(3)) > 59)) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T').replaceFirst(RegExp(r'z$'), 'Z'));
}

class HomeActivityLive extends StatefulWidget {
  const HomeActivityLive({super.key, required this.startDate});
  final String? startDate;

  @override
  State<HomeActivityLive> createState() => _HomeActivityLiveState();
}

class _HomeActivityLiveState extends State<HomeActivityLive> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(HomeActivityLive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final start = homeActivityStart(widget.startDate);
    final now = DateTime.now();
    if (start != null && start.isAfter(now)) {
      _timer = Timer(start.difference(now), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!homeActivityStarted(widget.startDate, DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Text(
      stringsOf(context).feedLive,
      style: CyType.caption1.copyWith(color: CyPalette.of(context).textPrimary),
    );
  }
}
