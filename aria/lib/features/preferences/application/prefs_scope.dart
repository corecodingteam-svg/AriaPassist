import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:flutter/widgets.dart';

/// Makes [AppPrefs] available to plain formatting helpers that only have a
/// BuildContext (date style etc.). Installed by AriaApp's builder.
class PrefsScope extends InheritedWidget {
  const PrefsScope({required this.prefs, required super.child, super.key});
  final AppPrefs prefs;

  static AppPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrefsScope>()?.prefs ??
      const AppPrefs();

  @override
  bool updateShouldNotify(PrefsScope old) => old.prefs != prefs;
}
