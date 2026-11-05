/// Normaliza texto para pesquisa: minúsculas, sem acentos e com espaços simples.
String normalizeSearch(String value) {
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Verdadeiro se todas as palavras de [query] aparecem em [text] (ordem livre).
/// Uma pesquisa vazia corresponde a tudo.
bool matchesSearch(String text, String query) {
  final normalizedQuery = normalizeSearch(query);
  if (normalizedQuery.isEmpty) return true;
  final normalizedText = normalizeSearch(text);
  return normalizedQuery.split(' ').every(normalizedText.contains);
}
