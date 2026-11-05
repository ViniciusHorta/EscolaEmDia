import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Último perfil usado neste dispositivo, por conta adulta.
/// Preferência de navegação apenas: nunca guarda PINs nem tokens. O PIN do
/// perfil é sempre pedido de novo ao abrir a app ou quando a sessão termina.
class LastProfile {
  const LastProfile.parent(this.familyId) : childId = null;
  const LastProfile.child(this.familyId, String this.childId);
  final String? familyId;
  final String? childId;
  bool get isParent => childId == null;

  Map<String, dynamic> toJson() => {'familyId': familyId, if (childId != null) 'childId': childId};
  static LastProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final familyId = value['familyId'];
    final childId = value['childId'];
    if (familyId != null && familyId is! String) return null;
    if (childId is String && familyId is String) return LastProfile.child(familyId, childId);
    return childId == null ? LastProfile.parent(familyId as String?) : null;
  }
}

abstract final class LastProfileStore {
  static String key(String adultId) => 'last-profile-$adultId';

  static Future<LastProfile?> read(String adultId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key(adultId));
      return raw == null ? null : LastProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Falhas de gravação são ignoradas: na pior das hipóteses, o dispositivo
  /// volta a perguntar qual o perfil.
  static Future<void> remember(String adultId, LastProfile profile) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key(adultId), jsonEncode(profile.toJson()));
    } catch (_) {}
  }
}
