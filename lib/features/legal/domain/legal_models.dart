enum LegalDocumentKind {
  terms('terms', 'Termos de Utilização'),
  privacy('privacy', 'Política de Privacidade');

  const LegalDocumentKind(this.id, this.label);
  final String id;
  final String label;

  static LegalDocumentKind? fromId(Object? value) {
    for (final kind in values) {
      if (kind.id == value) return kind;
    }
    return null;
  }
}

/// Uma versão publicada e imutável de um documento legal.
class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.kind,
    required this.version,
    required this.title,
    required this.content,
    required this.publishedAt,
    this.changeSummary,
  });

  final String id;
  final LegalDocumentKind kind;
  final int version;
  final String title;
  final String content;
  final DateTime publishedAt;
  final String? changeSummary;

  static LegalDocument? tryParse(Object? value) {
    if (value is! Map) return null;
    final kind = LegalDocumentKind.fromId(value['kind']);
    final id = value['id'], version = value['version'], title = value['title'], content = value['content'];
    final published = value['publishedAt'] is String ? DateTime.tryParse(value['publishedAt'] as String) : null;
    if (kind == null || id is! String || version is! int || title is! String || content is! String || published == null) {
      return null;
    }
    final summary = value['changeSummary'];
    return LegalDocument(id: id, kind: kind, version: version, title: title, content: content,
      publishedAt: published.toLocal(), changeSummary: summary is String && summary.trim().isNotEmpty ? summary : null);
  }
}

class LegalAcceptance {
  const LegalAcceptance({required this.documentId, required this.kind, required this.version, required this.acceptedAt});
  final String documentId;
  final LegalDocumentKind kind;
  final int version;
  final DateTime acceptedAt;

  static LegalAcceptance? tryParse(Object? value) {
    if (value is! Map) return null;
    final kind = LegalDocumentKind.fromId(value['kind']);
    final id = value['documentId'], version = value['version'];
    final at = value['acceptedAt'] is String ? DateTime.tryParse(value['acceptedAt'] as String) : null;
    if (kind == null || id is! String || version is! int || at == null) return null;
    return LegalAcceptance(documentId: id, kind: kind, version: version, acceptedAt: at.toLocal());
  }
}

/// Estado do responsável: versões em vigor, as que ainda tem de aceitar e o histórico de aceites.
class LegalStatus {
  const LegalStatus({required this.current, required this.pending, required this.accepted});
  final List<LegalDocument> current;
  final List<LegalDocument> pending;
  final List<LegalAcceptance> accepted;

  bool get compliant => pending.isEmpty;

  static List<T> _list<T>(Object? value, T? Function(Object?) parse) =>
      value is List ? value.map(parse).whereType<T>().toList() : <T>[];

  static LegalStatus? tryParse(Object? value) {
    if (value is! Map || value['current'] is! List || value['pending'] is! List) return null;
    return LegalStatus(
      current: _list(value['current'], LegalDocument.tryParse),
      pending: _list(value['pending'], LegalDocument.tryParse),
      accepted: _list(value['accepted'], LegalAcceptance.tryParse),
    );
  }
}

String formatLegalDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
