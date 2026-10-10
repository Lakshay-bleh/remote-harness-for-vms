const _known = <String, String>{
  'os.open_url': 'Opened a website',
  'os.open_app': 'Opened an app',
  'os.volume': 'Changed the volume',
  'os.media': 'Controlled media',
  'system.stats': 'Checked how busy it is',
  'system.processes': 'Looked at running programs',
  'shell.exec': 'Ran a command',
  'shell.open': 'Opened a terminal',
  'fs.read': 'Read a file',
  'fs.write': 'Changed a file',
};

String _words(String s) => s.replaceAll(RegExp(r'[_-]+'), ' ').trim();
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The nicest words for a capability id such as `os.open_url`: a plain sentence for the common ones, readable words for the rest.
String activityLabel(String id) {
  final known = _known[id];
  if (known != null) return known;
  final parts = id.split('.');
  final group = parts.isNotEmpty ? parts[0] : '';
  final action = parts.length > 1 ? parts[1] : '';
  if (group.isEmpty) return 'Something';
  return action.isNotEmpty ? '${_cap(_words(group))}: ${_words(action)}' : _cap(_words(group));
}
