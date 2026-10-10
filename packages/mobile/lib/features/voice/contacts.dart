/// Finding the contact a person meant from what a speech recogniser heard. "tanishq usic 2027" must find "Tanishq USICT 2027": the
/// recogniser drops letters, splits numbers ("20 27"), writes words as they sound. Matching is done on the phone, on the contacts the
/// phone already has: nothing about them is sent anywhere. Pure.
library;

class Contact {
  const Contact({required this.name, required this.numbers});
  final String name;
  final List<String> numbers;

  factory Contact.fromJson(Map<Object?, Object?> j) => Contact(
        name: '${j['name'] ?? ''}',
        numbers: [for (final n in (j['numbers'] as List?) ?? const []) '$n'],
      );

  @override
  String toString() => 'Contact($name)';
}

class ContactMatch {
  const ContactMatch(this.contact, this.score);
  final Contact contact;
  final double score;
}

const _numberWords = <String, int>{
  'zero': 0, 'oh': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, //
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17, //
  'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, //
  'eighty': 80, 'ninety': 90,
};

final _digits = RegExp(r'^\d+$');
final _twoDigits = RegExp(r'^\d{1,2}$');

String? _at(List<String> xs, int i) => i >= 0 && i < xs.length ? xs[i] : null;

/// "twenty twenty seven" -> "2027", "two thousand and twenty seven" -> "2027", "20 27" -> "2027". Other words are left alone.
List<String> _joinNumbers(List<String> tokens) {
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'two' && _at(tokens, i + 1) == 'thousand') {
      var j = i + 2;
      if (_at(tokens, j) == 'and') j++;
      var rest = 0;
      final tj = _at(tokens, j);
      final first = tj == null ? null : (_numberWords[tj] ?? (_digits.hasMatch(tj) ? int.parse(tj) : null));
      if (first != null && first <= 99) {
        rest = first;
        j++;
        final tn = _at(tokens, j);
        final second = tn == null ? null : _numberWords[tn];
        if (second != null && second < 10 && first >= 20 && first % 10 == 0) {
          rest += second;
          j++;
        }
      }
      out.add('${2000 + rest}');
      i = j - 1;
      continue;
    }
    // a run of 2-digit/number-word tokens that reads as a year or a number: "twenty twenty seven", "20 27"
    final n = _twoDigits.hasMatch(t) ? int.parse(t) : _numberWords[t];
    if (n != null && n >= 10 && n % 10 == 0 && n <= 90) {
      final next = _at(tokens, i + 1);
      final nn = next == null ? null : (_twoDigits.hasMatch(next) ? int.parse(next) : _numberWords[next]);
      if (nn != null && nn >= 10) {
        // "twenty twenty": 20 20; maybe followed by a units word ("seven")
        var tail = nn;
        var consumed = 2;
        final u = _at(tokens, i + 2);
        final unit = u == null ? null : _numberWords[u];
        if (nn % 10 == 0 && unit != null && unit < 10) {
          tail = nn + unit;
          consumed = 3;
        }
        out.add('$n${'$tail'.padLeft(2, '0')}');
        i += consumed - 1;
        continue;
      }
    }
    final next = _at(tokens, i + 1) ?? '';
    if (_twoDigits.hasMatch(t) && _twoDigits.hasMatch(next) && RegExp(r'^(?:19|20)$').hasMatch(t)) {
      out.add(t + next);
      i += 1;
      continue;
    }
    final w = _numberWords[t];
    out.add(w != null && !RegExp(r'^\d').hasMatch(t) && w < 10 ? '$w' : t);
  }
  return out;
}

/// Accented letters as their plain letter (NFKD with the marks dropped), for the letters names are usually written with.
String _stripAccents(String s) {
  const from = 'àáâãäåāăąçćčďèéêëēėęěìíîïīįıñńňòóôõöøōőŕřśšşťùúûüūůűųýÿžźż';
  const to = 'aaaaaaaaacccdeeeeeeeeiiiiiiinnnoooooooorrsssstuuuuuuuuyyzzz';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Titles people say in full and phones save short (or the other way round).
const _titles = <String, String>{'doctor': 'dr', 'professor': 'prof', 'mister': 'mr', 'missus': 'mrs', 'miss': 'ms'};

/// Lowercase words and numbers, letters and digits split apart ("usict2027" -> "usict", "2027"), punctuation gone.
List<String> tokens(String text) {
  final words = _stripAccents(text.toLowerCase())
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  return _joinNumbers(_joinLetters(words)).map((w) => _titles[w] ?? w).toList();
}

/// Letters spelled out one by one ("u s i c t") are one word. A run of two or more single letters is joined.
List<String> _joinLetters(List<String> words) {
  final out = <String>[];
  var run = '';
  void flush() {
    if (run.isNotEmpty) out.add(run);
    run = '';
  }

  for (final w in words) {
    if (RegExp(r'^[a-z]$').hasMatch(w)) {
      run += w;
    } else {
      flush();
      out.add(w);
    }
  }
  flush();
  return out;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = [del, ins, sub].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// How a word sounds, roughly: consonants only, repeats collapsed, a few letters that sound alike merged.
String _skeleton(String w) => w
    .replaceAll('ph', 'f')
    .replaceAll(RegExp(r'[ck]+'), 'k')
    .replaceAll(RegExp(r'[sz]'), 's')
    .replaceAll(RegExp(r'[aeiouyhw]'), '')
    .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

/// Likeness of two single words, 0 to 1. Numbers must be the same number; words may differ by a dropped or added letter or by sound.
double wordScore(String heard, String saved) {
  if (heard == saved) return 1;
  final heardNumber = _digits.hasMatch(heard);
  final savedNumber = _digits.hasMatch(saved);
  if (heardNumber || savedNumber) return heardNumber && savedNumber && heard == saved ? 1 : 0;
  final longest = heard.length > saved.length ? heard.length : saved.length;
  final edit = 1 - _levenshtein(heard, saved) / longest;
  final sk = _skeleton(heard);
  final sound = sk.isNotEmpty && sk == _skeleton(saved) ? 0.88 : 0.0;
  // a word the recogniser cut short ("usic" for "usict"): the start matches
  final prefix = heard.length >= 3 && (saved.startsWith(heard) || heard.startsWith(saved)) ? 0.86 : 0.0;
  return [edit, sound, prefix].reduce((x, y) => x > y ? x : y);
}

/// Likeness of what was heard to one saved name: the heard words are each matched to the best unused word of the name.
double nameScore(List<String> heard, List<String> saved) {
  if (heard.isEmpty || saved.isEmpty) return 0;
  final used = <int>{};
  var total = 0.0;
  for (final h in heard) {
    var best = 0.0;
    var at = -1;
    for (var i = 0; i < saved.length; i++) {
      if (used.contains(i)) continue;
      final sc = wordScore(h, saved[i]);
      if (sc > best) {
        best = sc;
        at = i;
      }
    }
    if (at >= 0 && best >= 0.6) used.add(at);
    total += best >= 0.6 ? best : 0;
  }
  // words of the saved name that were not said count against it a little (a short query should still find a longer name)
  final unsaid = saved.length - used.length;
  final penalty = unsaid * 0.03 < 0.12 ? unsaid * 0.03 : 0.12;
  return total / heard.length - penalty;
}

List<ContactMatch> rankContacts(String spoken, List<Contact> contacts) {
  final heard = tokens(spoken);
  final out = [for (final c in contacts) ContactMatch(c, nameScore(heard, tokens(c.name)))].where((m) => m.score > 0.5).toList();
  // stable sort, best first (as Array.prototype.sort is stable)
  final indexed = out.asMap().entries.toList()
    ..sort((a, b) {
      final d = b.value.score.compareTo(a.value.score);
      return d != 0 ? d : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

sealed class ContactChoice {
  const ContactChoice();
}

class OneContact extends ContactChoice {
  const OneContact(this.contact);
  final Contact contact;
}

class AskContact extends ContactChoice {
  const AskContact(this.options);
  final List<Contact> options;
}

class NoContact extends ContactChoice {
  const NoContact();
}

/// The contact meant, a short list to choose from when two fit about equally, or none.
ContactChoice chooseContact(String spoken, List<Contact> contacts) {
  final ranked = rankContacts(spoken, contacts);
  if (ranked.isEmpty || ranked[0].score < 0.72) {
    return ranked.isNotEmpty && ranked[0].score >= 0.6 ? AskContact([for (final m in ranked.take(3)) m.contact]) : const NoContact();
  }
  final first = ranked[0];
  final second = ranked.length > 1 ? ranked[1] : null;
  if (second != null && first.score - second.score < 0.08 && second.score >= 0.72) {
    return AskContact([for (final m in ranked.where((m) => first.score - m.score < 0.08).take(3)) m.contact]);
  }
  return OneContact(first.contact);
}
