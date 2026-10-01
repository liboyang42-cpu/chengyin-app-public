import 'package:intl/intl.dart';

/// Format a server-authoritative amount in its declared currency. A language
/// change never converts the value or substitutes a settlement currency.
String formatMoney({
  required num amount,
  required String currencyCode,
  required String locale,
}) {
  if (!amount.isFinite || !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
    throw ArgumentError('A finite amount and explicit ISO currency are required');
  }
  return NumberFormat.currency(
    locale: locale,
    name: currencyCode,
    symbol: currencyCode,
  ).format(amount);
}

/// Format the supplied calendar fields without converting the timestamp or zone.
/// Keep the existing 24-hour convention while localizing month/day order.
String formatCompactActivityDate(DateTime value, String locale) =>
    DateFormat.MMMd(locale).add_Hm().format(value);
