/// What a spoken sentence means. Pure text in, a decision out: no Android, no network, so every rule here is tested.
///
/// Where a command goes is the whole point:
///  - things on THIS phone (open an app, call, set an alarm, torch, volume, search, a settings screen) are done by the phone;
///  - "on my computer …" goes to the paired computer, which runs it with its own permissions and asks before anything risky;
///  - moving around this app is done here;
///  - everything else is a question or a task for the Escanor assistant.
library;

/// The app's tabs, by the names voice uses for them.
enum VoiceTab { assistant, computers, connections, machines, automations, settings }

enum SettingsScreen { wifi, bluetooth, display, sound, battery, apps, location }

/// The buttons and gestures of the phone itself, done through Android's Accessibility permission.
enum ControlOp { home, back, recents, notifications, quickSettings, lock, screenshot, scrollUp, scrollDown }

/// The wire name of a control op (what the native side and the tests call it).
String controlOpName(ControlOp op) => switch (op) {
      ControlOp.quickSettings => 'quick_settings',
      ControlOp.scrollUp => 'scroll_up',
      ControlOp.scrollDown => 'scroll_down',
      _ => op.name,
    };

enum VolumeChange { up, down, mute, unmute }

/// One thing to do on this phone.
sealed class PhoneAction {
  const PhoneAction();
}

class OpenApp extends PhoneAction {
  const OpenApp(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is OpenApp && other.name == name;
  @override
  int get hashCode => Object.hash('open_app', name);
  @override
  String toString() => 'OpenApp($name)';
}

class Control extends PhoneAction {
  const Control(this.op);
  final ControlOp op;
  @override
  bool operator ==(Object other) => other is Control && other.op == op;
  @override
  int get hashCode => Object.hash('control', op);
  @override
  String toString() => 'Control($op)';
}

class TapText extends PhoneAction {
  const TapText(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is TapText && other.text == text;
  @override
  int get hashCode => Object.hash('tap_text', text);
  @override
  String toString() => 'TapText($text)';
}

class TypeText extends PhoneAction {
  const TypeText(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is TypeText && other.text == text;
  @override
  int get hashCode => Object.hash('type_text', text);
  @override
  String toString() => 'TypeText($text)';
}

class ReadScreen extends PhoneAction {
  const ReadScreen();
  @override
  bool operator ==(Object other) => other is ReadScreen;
  @override
  int get hashCode => 'read_screen'.hashCode;
  @override
  String toString() => 'ReadScreen()';
}

/// An app the server already chose, by its package: nothing left to match.
class OpenPackage extends PhoneAction {
  const OpenPackage(this.package, this.label);
  final String package;
  final String label;
  @override
  bool operator ==(Object other) => other is OpenPackage && other.package == package && other.label == label;
  @override
  int get hashCode => Object.hash('open_package', package, label);
  @override
  String toString() => 'OpenPackage($package, $label)';
}

class OpenUrl extends PhoneAction {
  const OpenUrl(this.url);
  final String url;
  @override
  bool operator ==(Object other) => other is OpenUrl && other.url == url;
  @override
  int get hashCode => Object.hash('open_url', url);
  @override
  String toString() => 'OpenUrl($url)';
}

class Call extends PhoneAction {
  const Call(this.who);
  final String who;
  @override
  bool operator ==(Object other) => other is Call && other.who == who;
  @override
  int get hashCode => Object.hash('call', who);
  @override
  String toString() => 'Call($who)';
}

class SetAlarm extends PhoneAction {
  const SetAlarm(this.hour, this.minute);
  final int hour;
  final int minute;
  @override
  bool operator ==(Object other) => other is SetAlarm && other.hour == hour && other.minute == minute;
  @override
  int get hashCode => Object.hash('alarm', hour, minute);
  @override
  String toString() => 'SetAlarm($hour:$minute)';
}

class SetTimer extends PhoneAction {
  const SetTimer(this.seconds);
  final int seconds;
  @override
  bool operator ==(Object other) => other is SetTimer && other.seconds == seconds;
  @override
  int get hashCode => Object.hash('timer', seconds);
  @override
  String toString() => 'SetTimer($seconds)';
}

class Torch extends PhoneAction {
  const Torch(this.on);
  final bool on;
  @override
  bool operator ==(Object other) => other is Torch && other.on == on;
  @override
  int get hashCode => Object.hash('torch', on);
  @override
  String toString() => 'Torch($on)';
}

class Volume extends PhoneAction {
  const Volume(this.change);
  final VolumeChange change;
  @override
  bool operator ==(Object other) => other is Volume && other.change == change;
  @override
  int get hashCode => Object.hash('volume', change);
  @override
  String toString() => 'Volume($change)';
}

class WebSearch extends PhoneAction {
  const WebSearch(this.query);
  final String query;
  @override
  bool operator ==(Object other) => other is WebSearch && other.query == query;
  @override
  int get hashCode => Object.hash('web_search', query);
  @override
  String toString() => 'WebSearch($query)';
}

class OpenSettings extends PhoneAction {
  const OpenSettings(this.screen);
  final SettingsScreen screen;
  @override
  bool operator ==(Object other) => other is OpenSettings && other.screen == screen;
  @override
  int get hashCode => Object.hash('settings', screen);
  @override
  String toString() => 'OpenSettings($screen)';
}

/// What a sentence asks for.
sealed class VoiceCommand {
  const VoiceCommand();
}

class PhoneCommand extends VoiceCommand {
  const PhoneCommand(this.action);
  final PhoneAction action;
  @override
  bool operator ==(Object other) => other is PhoneCommand && other.action == action;
  @override
  int get hashCode => Object.hash('phone', action);
  @override
  String toString() => 'PhoneCommand($action)';
}

class ComputerCommand extends VoiceCommand {
  const ComputerCommand(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is ComputerCommand && other.text == text;
  @override
  int get hashCode => Object.hash('computer', text);
  @override
  String toString() => 'ComputerCommand($text)';
}

class NoComputerCommand extends VoiceCommand {
  const NoComputerCommand(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is NoComputerCommand && other.text == text;
  @override
  int get hashCode => Object.hash('no_computer', text);
  @override
  String toString() => 'NoComputerCommand($text)';
}

class AssistantCommand extends VoiceCommand {
  const AssistantCommand(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is AssistantCommand && other.text == text;
  @override
  int get hashCode => Object.hash('assistant', text);
  @override
  String toString() => 'AssistantCommand($text)';
}

class GoCommand extends VoiceCommand {
  const GoCommand(this.tab);
  final VoiceTab tab;
  @override
  bool operator ==(Object other) => other is GoCommand && other.tab == tab;
  @override
  int get hashCode => Object.hash('go', tab);
  @override
  String toString() => 'GoCommand($tab)';
}

class StopCommand extends VoiceCommand {
  const StopCommand();
  @override
  bool operator ==(Object other) => other is StopCommand;
  @override
  int get hashCode => 'stop'.hashCode;
  @override
  String toString() => 'StopCommand()';
}

class EmptyCommand extends VoiceCommand {
  const EmptyCommand();
  @override
  bool operator ==(Object other) => other is EmptyCommand;
  @override
  int get hashCode => 'empty'.hashCode;
  @override
  String toString() => 'EmptyCommand()';
}

class VoiceContext {
  const VoiceContext({required this.hasComputer});

  /// At least one computer is paired, so "on my computer" has somewhere to go.
  final bool hasComputer;
}

// ---- the name

/// Speech recognisers have never heard "Escanor" and spell it as they like ("escaner", "es canor", "ex canor"). Rewrite the likely
/// spellings to the name. Ordinary words (scanner, escalator, canon) are not touched.
final _nameHeardAs = RegExp(r'\be[sx]\s?c?\s?a\s?n{1,2}\s?[eo]r?\b', caseSensitive: false);
String canonicalizeName(String t) => t.replaceAll(_nameHeardAs, 'escanor');

final _wake = RegExp(r'^\s*(?:hey|ok|okay|hi|yo)\s+escanor\b[\s,.:;!?-]*', caseSensitive: false);

/// Drop a leading "hey escanor" (or ok/hi/yo), whatever punctuation follows.
String stripWake(String raw) => canonicalizeName(raw).replaceFirst(_wake, '').trim();

String _clean(String t) => t
    .toLowerCase()
    .replaceAll(RegExp('[’\']'), "'")
    .replaceAll(RegExp(r'[.!?,]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ---- numbers people say
const _wordNumbers = <String, int>{
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, //
  'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
};

int? _numberOf(String w) => RegExp(r'^\d+$').hasMatch(w) ? int.parse(w) : _wordNumbers[w];

/// "5 minutes", "1 hour 30 minutes", "half an hour", "two minutes" -> seconds. Null for nonsense or longer than a day.
int? parseDuration(String text) {
  final t = _clean(text);
  if (RegExp(r'^half an hour$').hasMatch(t)) return 1800;
  if (RegExp(r'^(?:a )?quarter of an hour$').hasMatch(t)) return 900;
  var total = 0;
  var found = false;
  for (final m in RegExp(r'(\d+|[a-z]+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b').allMatches(t)) {
    final n = _numberOf(m[1]!);
    if (n == null) return null;
    final unit = m[2]![0];
    total += n * (unit == 'h' ? 3600 : unit == 'm' ? 60 : 1);
    found = true;
  }
  return found && total > 0 && total <= 86400 ? total : null;
}

/// "7 am", "7:30 pm", "18:45", "quarter past 6", "half past 9 am" -> 24-hour time. Null for nonsense.
({int hour, int minute})? parseClock(String text) {
  final m = RegExp(r'^(?:(quarter|half) past )?(\d{1,2})(?::(\d{2}))?\s?(a\.?m\.?|p\.?m\.?)?$').firstMatch(_clean(text));
  if (m == null) return null;
  var hour = int.parse(m[2]!);
  final minute = m[1] == 'quarter' ? 15 : m[1] == 'half' ? 30 : m[3] != null ? int.parse(m[3]!) : 0;
  final ampm = m[4]?[0];
  if (minute > 59) return null;
  if (ampm != null) {
    if (hour < 1 || hour > 12) return null;
    hour = (hour % 12) + (ampm == 'p' ? 12 : 0);
  } else if (hour > 23) {
    return null;
  }
  return (hour: hour, minute: minute);
}

// ---- the sentence
final _tabWords = <(RegExp, VoiceTab)>[
  (RegExp(r'^(?:chat|assistant|the assistant|escanor)$'), VoiceTab.assistant),
  (RegExp(r'^computers?$'), VoiceTab.computers),
  (RegExp(r'^connections?$'), VoiceTab.connections),
  (RegExp(r'^machines?$'), VoiceTab.machines),
  (RegExp(r'^(?:automations?|autopilot)$'), VoiceTab.automations),
  (RegExp(r'^settings?$'), VoiceTab.settings),
];
const _computerNoun = '(?:computer|laptop|pc|desktop|mac|machine)';
const _settingsScreens = <String, SettingsScreen>{
  'wifi': SettingsScreen.wifi,
  'wi-fi': SettingsScreen.wifi,
  'wi fi': SettingsScreen.wifi,
  'bluetooth': SettingsScreen.bluetooth,
  'display': SettingsScreen.display,
  'screen': SettingsScreen.display,
  'sound': SettingsScreen.sound,
  'battery': SettingsScreen.battery,
  'apps': SettingsScreen.apps,
  'location': SettingsScreen.location,
};

VoiceTab? _tabOf(String name) {
  final n = name.replaceFirst(RegExp(r'^(?:my|the)\s+'), '');
  for (final (re, tab) in _tabWords) {
    if (re.hasMatch(n)) return tab;
  }
  return null;
}

/// "google dot com" -> "google.com": a speech recogniser writes the word, not the dot.
String _spokenDots(String t) => t.replaceAll(RegExp(r'\s+dot\s+'), '.');

final _controlWords = <(RegExp, ControlOp)>[
  (RegExp(r'^(?:go|take me|press|return|bring me)(?: back)?(?: to)?(?: the)? home(?: screen)?$|^home(?: screen)?$'), ControlOp.home),
  (RegExp(r'^(?:go|press) back$|^back$|^navigate back$'), ControlOp.back),
  (RegExp(r'^(?:show |open |press )?(?:the )?(?:recent apps|recents|app switcher|multitasking)$'), ControlOp.recents),
  (RegExp(r'^(?:show |open |pull down |check )?(?:the |my )?notifications?(?: shade| panel| drawer)?$'), ControlOp.notifications),
  (RegExp(r'^(?:show |open |pull down )?(?:the )?quick settings$'), ControlOp.quickSettings),
  (RegExp(r'^lock(?: the| my)?(?: phone| screen)?$|^turn off the screen$'), ControlOp.lock),
  (RegExp(r'^(?:take |grab )?(?:a )?screenshot$|^capture the screen$'), ControlOp.screenshot),
  (RegExp(r'^scroll down(?: a bit| more)?$|^page down$'), ControlOp.scrollDown),
  (RegExp(r'^scroll up(?: a bit| more)?$|^page up$'), ControlOp.scrollUp),
];

PhoneAction? parseControl(String t) {
  for (final (re, op) in _controlWords) {
    if (re.hasMatch(t)) return Control(op);
  }
  return null;
}

String? _group1(String pattern, String t) => RegExp(pattern).firstMatch(t)?[1];

VoiceCommand parseVoiceCommand(String raw, VoiceContext ctx) {
  final heard = stripWake(raw);
  final t = _clean(heard);
  if (t.isEmpty) return const EmptyCommand();
  if (RegExp(r"^(?:cancel|never ?mind|stop|stop listening|forget it|that'?s all|be quiet)$").hasMatch(t)) return const StopCommand();

  // The computer, when asked for by name.
  final toComputer = _group1('^(?:on|in|at) my $_computerNoun[, ]+(.+)\$', t) ??
      _group1('^(?:tell|ask|have|get) my $_computerNoun(?: to)? (.+)\$', t) ??
      _group1('^(.+?) on my $_computerNoun\$', t);
  if (toComputer != null) return ctx.hasComputer ? ComputerCommand(toComputer) : NoComputerCommand(toComputer);

  // Things the phone itself does.
  final timer = _group1(r'^(?:set (?:a |the )?)?timer(?: for)? (.+)$', t);
  if (timer != null) {
    final seconds = parseDuration(timer);
    if (seconds != null) return PhoneCommand(SetTimer(seconds));
  }
  final alarm = _group1(r'^(?:set (?:an |the |my )?alarm (?:for|at)|wake me(?: up)? at) (.+)$', t);
  if (alarm != null) {
    final clock = parseClock(alarm);
    if (clock != null) return PhoneCommand(SetAlarm(clock.hour, clock.minute));
  }
  final torch = RegExp(r'^(?:turn |switch )?(on|off)? ?(?:the )?(?:flashlight|torch)(?: (on|off))?$').firstMatch(t);
  if (torch != null && (torch[1] != null || torch[2] != null)) return PhoneCommand(Torch((torch[1] ?? torch[2]) == 'on'));
  final volume = RegExp(r'^(?:turn )?(?:the )?volume (up|down)$|^turn (?:it )?(up|down)$').firstMatch(t);
  if (volume != null) return PhoneCommand(Volume((volume[1] ?? volume[2]) == 'up' ? VolumeChange.up : VolumeChange.down));
  if (t == 'mute') return const PhoneCommand(Volume(VolumeChange.mute));
  if (t == 'unmute') return const PhoneCommand(Volume(VolumeChange.unmute));
  final call = _group1(r'^(?:call|dial|phone|ring) (.+)$', t);
  if (call != null && call.isNotEmpty) {
    final digits = call.replaceAll(RegExp(r'[\s-]'), '');
    return PhoneCommand(Call(RegExp(r'^\+?\d{3,}$').hasMatch(digits) ? digits : call));
  }
  // Using the phone itself: its buttons and what is on its screen (needs the Accessibility permission, which the action explains).
  final control = parseControl(t);
  if (control != null) return PhoneCommand(control);
  final tap = _group1(r'^(?:tap|click|press|select|hit)(?: on)?(?: the)? (.+?)(?: button)?$', t);
  if (tap != null && tap.isNotEmpty) return PhoneCommand(TapText(tap));
  final typed = _group1(r'^(?:type|write|enter)(?: in)? (.+)$', heard.trim().replaceFirst(RegExp(r'[.!?]+$'), ''));
  if (typed != null && typed.isNotEmpty) return PhoneCommand(TypeText(typed));
  if (RegExp(r"^(?:read|what(?:'s| is) on)(?: out)?(?: the| my)? screen(?: to me)?$|^what(?:'s| is) on my screen$").hasMatch(t)) {
    return const PhoneCommand(ReadScreen());
  }
  final site = RegExp(r'^(?:open|go to|visit|take me to)(?: the)? ((?:[a-z0-9-]+\.)+[a-z]{2,})(?:/\S*)?$').firstMatch(_spokenDots(t));
  if (site != null) return PhoneCommand(OpenUrl('https://${site[1]}'));

  final search = _group1(r'^(?:search(?: the web)?(?: for)?|google|look up) (.+)$', t);
  if (search != null && search.isNotEmpty) {
    final q = search.replaceFirst(RegExp(r'^(?:google|the web) (?:for )?'), '');
    return PhoneCommand(WebSearch(q.isEmpty ? search : q));
  }
  final settings = _group1(r'^open (wi-?fi|wi fi|bluetooth|display|screen|sound|battery|apps|location) settings$', t);
  if (settings != null) return PhoneCommand(OpenSettings(_settingsScreens[settings]!));

  // Moving around this app, or opening another app.
  final verb = RegExp(r'^(?:go to|show|open|take me to|switch to|launch|start|run)(?: the| my)? (.+?)(?: app)?$').firstMatch(t);
  if (verb != null) {
    final navVerb = RegExp(r'^(?:go to|show|take me to|switch to)').hasMatch(t);
    final tab = navVerb || t.startsWith('open') ? _tabOf(verb[1]!) : null;
    if (tab != null) return GoCommand(tab);
    if (RegExp(r'^(?:go to|show|take me to|switch to)\b').hasMatch(t)) return AssistantCommand(heard);
    return PhoneCommand(OpenApp(verb[1]!));
  }

  return AssistantCommand(heard);
}
