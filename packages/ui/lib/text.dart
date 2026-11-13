const _from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _to = 'aaaaaeeeeiiiiooooouuuunc';
final _accentMap = <String, String>{
  for (var i = 0; i < _from.length; i++) _from[i]: _to[i],
};

/// Minúsculas y sin tildes, para búsquedas tolerantes.
String normalizeText(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accentMap[ch] ?? ch);
  }
  return b.toString();
}
