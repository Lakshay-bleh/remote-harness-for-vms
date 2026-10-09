/// Matching a spoken app name to an installed app. Pure.
library;

class InstalledApp {
  const InstalledApp({required this.label, required this.package});
  final String label;
  final String package;

  factory InstalledApp.fromJson(Map<Object?, Object?> j) => InstalledApp(label: '${j['label'] ?? ''}', package: '${j['package'] ?? ''}');

  @override
  bool operator ==(Object other) => other is InstalledApp && other.label == label && other.package == package;
  @override
  int get hashCode => Object.hash(label, package);
  @override
  String toString() => 'InstalledApp($label, $package)';
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Other names people use for an app, mapped to a word that appears in its label or package.
const _nicknames = <String, List<String>>{
  'browser': ['chrome', 'browser', 'internet', 'firefox'],
  'maps': ['maps'],
  'googlemaps': ['maps'],
  'mail': ['gmail', 'mail'],
  'email': ['gmail', 'mail'],
  'dialer': ['dialer', 'phone'],
  'phone': ['phone', 'dialer'],
  'messages': ['messages', 'messaging', 'sms'],
  'text': ['messages', 'messaging', 'sms'],
  'photos': ['photos', 'gallery'],
  'gallery': ['gallery', 'photos'],
  'music': ['music', 'spotify'],
  'clock': ['clock'],
  'calculator': ['calculator'],
  'calendar': ['calendar'],
  'files': ['files', 'myfiles'],
};

/// The installed app a spoken name most likely means: an exact name first, then one that starts with it, then one that contains it,
/// then a nickname. Null when nothing fits: it must say so rather than open the wrong app.
InstalledApp? matchApp(String spoken, List<InstalledApp> apps) {
  final want = _norm(spoken);
  if (want.length < 2) return null;
  final labeled = [for (final a in apps) (a: a, l: _norm(a.label), p: a.package.toLowerCase())];
  InstalledApp? shortest(List<({InstalledApp a, String l, String p})> xs) {
    if (xs.isEmpty) return null;
    final sorted = [...xs]..sort((x, y) => x.l.length.compareTo(y.l.length));
    return sorted.first.a;
  }

  final exact = labeled.where((x) => x.l == want).toList();
  if (exact.isNotEmpty) return shortest(exact);
  final starts = labeled.where((x) => x.l.startsWith(want)).toList();
  if (starts.isNotEmpty) return shortest(starts);
  final contains = labeled.where((x) => x.l.contains(want)).toList();
  if (contains.isNotEmpty) return shortest(contains);
  for (final word in _nicknames[want] ?? const <String>[]) {
    final hit = labeled.where((x) => x.l.contains(word) || x.p.contains(word)).toList();
    if (hit.isNotEmpty) return shortest(hit);
  }
  return null;
}
