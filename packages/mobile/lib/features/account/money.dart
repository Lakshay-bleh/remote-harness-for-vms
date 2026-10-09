/// Numbers and money as the app writes them. Pure.
library;

/// Digits grouped the Indian way: 1,00,000 and 24,990.
String groupIndian(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  if (s.length <= 3) return '${neg ? '-' : ''}$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${neg ? '-' : ''}${parts.join(',')},$last3';
}

/// Digits grouped in threes: 1,234,567.
String groupThousands(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// An amount in paise as rupees ("₹2,499", "₹1.5"), for prices and invoices.
String formatMoney(int paise, [String currency = 'INR']) {
  final symbol = currency == 'INR' ? '₹' : (currency == 'USD' ? r'$' : '$currency ');
  final whole = paise ~/ 100;
  final cents = paise.abs() % 100;
  var text = groupIndian(whole);
  if (cents != 0) {
    var frac = cents.toString().padLeft(2, '0');
    if (frac.endsWith('0')) frac = frac.substring(0, 1);
    text = '$text.$frac';
  }
  return '$symbol$text';
}
