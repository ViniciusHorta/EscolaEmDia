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
  const ChildProfile({required this.id, required this.familyId, required this.displayName, required this.schoolYear, required this.avatarId});
  final String id;
  final String familyId;
  final String displayName;
  final int schoolYear;
  final String avatarId;
  factory ChildProfile.fromJson(Map value) => ChildProfile(
    id: value['id'] as String, familyId: value['familyId'] as String,
    displayName: value['displayName'] as String, schoolYear: value['schoolYear'] as int,
    avatarId: value['avatarId'] as String,
  );
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
