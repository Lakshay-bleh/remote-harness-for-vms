/// Join what was already typed with what has been heard, with one space between.
String joinSpoken(String base, String heard) => [base.trimRight(), heard.trim()].where((s) => s.isNotEmpty).join(' ');

/// The sentence to show when the microphone cannot be used.
String micProblem({required bool denied, required bool ios}) => denied
    ? (ios
        ? 'Allow the microphone and speech recognition in Settings, under Escanor.'
        : 'Allow the microphone in Android Settings, under Apps, Escanor, Permissions.')
    : 'Speaking is not available on this phone.';
