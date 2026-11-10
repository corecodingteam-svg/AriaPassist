import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

enum ListType {
  grocery('🛒', 'Grocery'),
  packing('🧳', 'Packing'),
  work('💼', 'Work'),
  bills('💰', 'Bills'),
  custom('📝', 'List');

  ListType(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => tr(_label);

  static ListType parse(String? s) => values.asNameMap()[s] ?? ListType.custom;

  /// Guess from a spoken name ("grocery", "shopping", "kirana", "packing").
  static ListType guess(String name) {
    final n = name.toLowerCase();
    if (RegExp('grocer|shopping|kirana|sabzi|ration').hasMatch(n)) {
      return grocery;
    }
    if (RegExp('pack|trip|travel').hasMatch(n)) return packing;
    if (RegExp('work|office').hasMatch(n)) return work;
    if (RegExp('bill').hasMatch(n)) return bills;
    return custom;
  }
}

@immutable
class AriaList {
  const AriaList({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.name,
    this.type = ListType.custom,
    this.visibility = 'private',
    this.openCount = 0,
    this.doneCount = 0,
    this.preview = const [],
  });

  final String id;
  final String circleId;
  final String createdBy;
  final String name;
  final ListType type;
  final String visibility;
  final int openCount;
  final int doneCount;

  /// First few open items, for the list card.
  final List<String> preview;

  bool get shared => visibility == 'shared';
}

@immutable
class ListEntry {
  const ListEntry({
    required this.id,
    required this.listId,
    required this.text,
    this.qty,
    this.done = false,
    this.addedBy,
    this.addedByName,
    this.position = 0,
  });

  final String id;
  final String listId;
  final String text;
  final double? qty;
  final bool done;
  final String? addedBy;

  /// Display name of [addedBy] when it's someone else in the Circle.
  final String? addedByName;
  final double position;

  String get qtyLabel => qty == null
      ? ''
      : (qty! == qty!.roundToDouble() ? '×${qty!.toInt()}' : '×$qty');
}
