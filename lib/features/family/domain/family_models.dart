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
  const ChildSubscriptionSummary({required this.channel, required this.status, required this.autoRenew, this.currentPeriodEnd, this.productId});
  final String channel; // manual | stripe | google_play | app_store
  final String status; // active | in_grace
  final bool autoRenew;
  final DateTime? currentPeriodEnd;
  /// Produto da loja (premium_crianca_N) — para abrir a gestão na Google Play / App Store.
  final String? productId;
  bool get isStripe => channel == 'stripe';
  bool get inGrace => status == 'in_grace';
  static ChildSubscriptionSummary? tryParse(Object? value) {
    if (value is! Map || value['channel'] is! String) return null;
    final end = value['currentPeriodEnd'];
    return ChildSubscriptionSummary(channel: value['channel'] as String, status: '${value['status']}',
      autoRenew: value['autoRenew'] == true, currentPeriodEnd: end is String ? DateTime.tryParse(end)?.toLocal() : null,
      productId: value['productId'] as String?);
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

/// Responsável ativo da família.
class FamilyMember {
  const FamilyMember({required this.adultUserId, required this.email, required this.joinedAt, required this.isMe});
  final String adultUserId;
  final String email;
  final DateTime joinedAt;
  final bool isMe;
  factory FamilyMember.fromJson(Map value) => FamilyMember(
    adultUserId: value['adultUserId'] as String, email: (value['email'] as String?) ?? '',
    joinedAt: DateTime.parse(value['joinedAt'] as String), isMe: value['isMe'] == true,
  );
}

/// Convite pendente (enviado por e-mail, válido 7 dias).
class FamilyInvitation {
  const FamilyInvitation({required this.id, required this.email, required this.expiresAt, required this.expired});
  final String id;
  final String email;
  final DateTime expiresAt;
  final bool expired;
  factory FamilyInvitation.fromJson(Map value) => FamilyInvitation(
    id: value['id'] as String, email: value['email'] as String,
    expiresAt: DateTime.parse(value['expiresAt'] as String), expired: value['expired'] == true,
  );
}

class FamilyMembers {
  const FamilyMembers({required this.members, required this.invitations});
  final List<FamilyMember> members;
  final List<FamilyInvitation> invitations;
  /// Limite do servidor: 4 responsáveis, contando os convites pendentes válidos.
  static const limit = 4;
  bool get canInvite => members.length + invitations.where((i) => !i.expired).length < limit;
  factory FamilyMembers.fromJson(Map value) => FamilyMembers(
    members: [for (final m in (value['members'] as List? ?? const [])) FamilyMember.fromJson(m as Map)],
    invitations: [for (final i in (value['invitations'] as List? ?? const [])) FamilyInvitation.fromJson(i as Map)],
  );
}

/// Dados públicos de um convite, para o ecrã «Aceitar convite».
class InvitationPreview {
  const InvitationPreview({required this.status, required this.email, this.invitedBy, this.expiresAt, this.accountExists = true});
  /// pending | accepted | expired | invalid
  final String status;
  final String email;
  final String? invitedBy;
  final DateTime? expiresAt;
  /// O e-mail convidado já tem conta: a app abre em «Entrar»; senão em «Criar conta».
  final bool accountExists;
  bool get pending => status == 'pending';
  factory InvitationPreview.fromJson(Map value) => InvitationPreview(
    status: value['status'] as String? ?? 'invalid', email: value['email'] as String? ?? '',
    invitedBy: value['invitedBy'] as String?,
    expiresAt: value['expiresAt'] is String ? DateTime.tryParse(value['expiresAt'] as String) : null,
    accountExists: value['accountExists'] != false,
  );
  static const invalid = InvitationPreview(status: 'invalid', email: '');
}
