/// A failure in talking to a computer, carrying the plain words the TypeScript library throws (`new Error('...')`), so the screens
/// and [explainComputerFailure] read the same text.
class ComputerError implements Exception {
  const ComputerError(this.message, {this.delivered = false});
  final String message;

  /// The request had already gone out to the computer when this happened (the link dropped while waiting): it may have run, so it
  /// is not sent again another way.
  final bool delivered;
  @override
  String toString() => message;
}

/// The words of any failure, as the TypeScript `e instanceof Error ? e.message : typeof e === 'string' ? e : ''` reads them.
String failureText(Object? e) {
  if (e == null) return '';
  if (e is String) return e;
  if (e is ComputerError) return e.message;
  final s = e.toString();
  for (final prefix in const ['Exception: ', 'FormatException: ', 'Bad state: ']) {
    if (s.startsWith(prefix)) return s.substring(prefix.length);
  }
  return s;
}
