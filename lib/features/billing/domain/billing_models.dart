/// Plano e utilização do dia de uma criança (resposta de child_daily_access).
/// Os limites vêm do servidor; null significa "sem limite" (Premium).
class ChildDailyAccess {
  const ChildDailyAccess({required this.plan, required this.assignmentsToday, required this.attemptsToday,
    this.assignmentLimit, this.attemptLimit, this.freeMaxQuestions});
  final String plan; // premium | free | locked
  final int assignmentsToday, attemptsToday;
  final int? assignmentLimit, attemptLimit, freeMaxQuestions;

  bool get isPremium => plan == 'premium';
  bool get isFree => plan == 'free';
  bool get isLocked => plan == 'locked';
  bool get assignmentQuotaReached => isLocked || (assignmentLimit != null && assignmentsToday >= assignmentLimit!);
  bool get attemptQuotaReached => attemptLimit != null && attemptsToday >= attemptLimit!;

  /// Conta localmente uma tentativa nova começada agora (até a próxima leitura do servidor).
  ChildDailyAccess withNewAttempt() => ChildDailyAccess(plan: plan, assignmentsToday: assignmentsToday,
    attemptsToday: attemptsToday + 1, assignmentLimit: assignmentLimit, attemptLimit: attemptLimit, freeMaxQuestions: freeMaxQuestions);

  static ChildDailyAccess? tryParse(Object? value) {
    if (value is! Map || value['plan'] is! String) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    return ChildDailyAccess(plan: value['plan'] as String,
      assignmentsToday: n(value['assignmentsToday']) ?? 0, attemptsToday: n(value['attemptsToday']) ?? 0,
      assignmentLimit: n(value['assignmentLimit']), attemptLimit: n(value['attemptLimit']),
      freeMaxQuestions: n(value['freeMaxQuestions']));
  }
}

/// Porque é que a oferta Premium está a ser mostrada ao responsável.
enum PaywallReason { dailyLimit, premiumWorksheet, locked, general, learning }

PaywallReason? paywallReasonForCode(String? code) => switch (code) {
  'DAILY_ASSIGNMENT_LIMIT_REACHED' => PaywallReason.dailyLimit,
  'PREMIUM_WORKSHEET_REQUIRED' => PaywallReason.premiumWorksheet,
  'CHILD_PLAN_LOCKED' => PaywallReason.locked,
  _ => null,
};
