import 'protocol/protocol.dart';

/// What to tell the person once the computer has answered "may phones use this?". Says where the question is, and what to do.
String describeGroupRequest(GroupRequestStatus status, String label) => switch (status) {
  GroupRequestStatus.asked =>
    'Asked. A question just appeared in Escanor Desktop on your computer: “Let your phones use $label?”. Choose Allow there. This list updates by itself.',
  GroupRequestStatus.unavailable => 'Open Escanor Desktop on your computer first (it needs its window open to ask you), then ask again.',
  GroupRequestStatus.alreadyOn => '“$label” is already allowed for phones.',
  GroupRequestStatus.busy => 'Your computer has already been asked about “$label” and is waiting for your answer there.',
  GroupRequestStatus.unknown => 'Your computer does not recognise that. Update Escanor Desktop on it, then try again.',
};

String _norm(String s) => s.replaceAll(RegExp('[“”"]'), '').trim().toLowerCase();

PermissionGroup? findGroup(List<PermissionGroup> groups, String label) {
  for (final g in groups) {
    if (_norm(g.label) == _norm(label)) return g;
  }
  return null;
}

/// Switched off first (that is what someone opens this to fix), then alphabetical. A new list: the input is untouched.
List<PermissionGroup> sortGroups(List<PermissionGroup> groups) {
  final out = [...groups];
  out.sort((a, b) {
    final e = (a.enabled ? 1 : 0) - (b.enabled ? 1 : 0);
    return e != 0 ? e : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}
