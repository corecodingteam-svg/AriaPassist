import 'package:aria/data/providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// WhatsApp opt-in (server decides eligibility: plan + verified phone).
abstract interface class WhatsAppApi {
  /// The number messages go to, or null when off.
  Future<String?> status();

  /// Returns the number on success; throws with a hint on failure.
  Future<String?> setEnabled({required bool enabled});
}

class SupabaseWhatsAppApi implements WhatsAppApi {
  SupabaseWhatsAppApi(this._db);
  final SupabaseClient _db;

  @override
  Future<String?> status() async {
    final row = await _db
        .from('whatsapp_optins')
        .select('phone_e164, enabled')
        .maybeSingle();
    return row != null && row['enabled'] == true
        ? row['phone_e164'] as String
        : null;
  }

  @override
  Future<String?> setEnabled({required bool enabled}) =>
      _db.rpc<String?>('set_whatsapp', params: {'p_enabled': enabled});
}

final whatsAppApiProvider = Provider<WhatsAppApi?>((ref) {
  try {
    return SupabaseWhatsAppApi(ref.watch(supabaseClientProvider));
  } on Object {
    return null;
  }
});

final whatsAppStatusProvider = FutureProvider<String?>(
  (ref) async => await ref.watch(whatsAppApiProvider)?.status(),
);

String whatsAppErrorMessage(Object e) {
  final s = e.toString();
  if (s.contains('upgrade_required') || s.contains('Family or Team')) {
    return tr('WhatsApp reminders come with the Family and Team plans.');
  }
  if (s.contains('no_phone') || s.contains('phone number')) {
    return tr('Sign in with your phone number to get reminders on WhatsApp.');
  }
  return tr('Couldn’t change that. Check your connection and try again.');
}
