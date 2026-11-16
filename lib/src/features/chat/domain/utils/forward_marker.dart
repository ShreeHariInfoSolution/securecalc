/// Invisible prefix stored INSIDE the encrypted message text.
/// The server never sees it, so no backend change is needed.
const String kFwdMarker = '\u2063\u2064\u2063';

String addFwdMarker(String t) => t.startsWith(kFwdMarker) ? t : '$kFwdMarker$t';
bool hasFwdMarker(String t) => t.startsWith(kFwdMarker);
String stripFwdMarker(String t) =>
    hasFwdMarker(t) ? t.substring(kFwdMarker.length) : t;
