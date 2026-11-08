class Family {
  const Family({required this.id, required this.createdAt});
  final String id;
  final DateTime createdAt;
  factory Family.fromJson(Map value) => Family(
    id: value['id'] as String,
    createdAt: DateTime.parse(value['createdAt'] as String),
  );
}

class ChildProfile {
  const ChildProfile({required this.id, required this.familyId, required this.displayName, required this.schoolYear, required this.avatarId, this.plan, this.subscription});
  final String id;
  final String familyId;
  final String displayName;
  final int schoolYear;
  final String avatarId;
  /// premium | free | locked. Só vem preenchido nas respostas da área da família.
  final String? plan;
  final ChildSubscriptionSummary? subscription;
  bool get isPremium => plan == 'premium';
  ChildProfile withPlanFrom(ChildProfile previous) => plan != null ? this : ChildProfile(
    id: id, familyId: familyId, displayName: displayName, schoolYear: schoolYear, avatarId: avatarId,
    plan: previous.plan, subscription: previous.subscription);
  factory ChildProfile.fromJson(Map value) => ChildProfile(
    id: value['id'] as String, familyId: value['familyId'] as String,
    displayName: value['displayName'] as String, schoolYear: value['schoolYear'] as int,
    avatarId: value['avatarId'] as String, plan: value['plan'] as String?,
    subscription: ChildSubscriptionSummary.tryParse(value['subscription']),
  );
}

/// Assinatura viva da criança (só na área da família).
class ChildSubscriptionSummary {
  const ChildSubscriptionSummary({required this.channel, required this.status, required this.autoRenew, this.currentPeriodEnd});
  final String channel; // manual | stripe | google_play | app_store
  final String status; // active | in_grace
  final bool autoRenew;
  final DateTime? currentPeriodEnd;
  bool get isStripe => channel == 'stripe';
  bool get inGrace => status == 'in_grace';
  static ChildSubscriptionSummary? tryParse(Object? value) {
    if (value is! Map || value['channel'] is! String) return null;
    final end = value['currentPeriodEnd'];
    return ChildSubscriptionSummary(channel: value['channel'] as String, status: '${value['status']}',
      autoRenew: value['autoRenew'] == true, currentPeriodEnd: end is String ? DateTime.tryParse(end)?.toLocal() : null);
  }
}

// Transient form data only. Never serialize this object into local storage or logs.
class ChildProfileDraft {
  const ChildProfileDraft({required this.requestId, required this.displayName, required this.schoolYear, required this.avatarId, required this.pin});
  final String requestId;
  final String displayName;
  final int schoolYear;
  final String avatarId;
  final String pin;
}

// Transient form data only. pin == null keeps the current child PIN.
class ChildProfileUpdate {
  const ChildProfileUpdate({required this.displayName, required this.schoolYear, required this.avatarId, this.pin});
  final String displayName;
  final int schoolYear;
  final String avatarId;
  final String? pin;
}

abstract final class ChildAvatars {
  static const choices = <String, (String, String)>{
    'fox': ('Raposinha', '🦊'), 'owl': ('Mocho', '🦉'),
    'bear': ('Urso', '🐻'), 'lynx': ('Lince', '🐱'),
    'dolphin': ('Golfinho', '🐬'), 'rabbit': ('Coelho', '🐰'),
  };
  static String emoji(String id) => choices[id]?.$2 ?? '🙂';
  static String label(String id) => choices[id]?.$1 ?? 'Amigo';
}
