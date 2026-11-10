import 'package:aria_admin/core/neon_theme.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cards in a row are the same height, with or without a hint', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: neonTheme(Brightness.light),
        home: Scaffold(
          body: Wrap(
            children: [
              KpiCard(tile: Neon.tiles[0], label: 'No hint', value: '₹0'),
              KpiCard(tile: Neon.tiles[1], label: 'Short hint', value: '0', hint: '0 in 30 days'),
              const KpiCard(label: 'Long hint', value: '0', hint: 'monthly equivalent of paid plans, which wraps'),
            ],
          ),
        ),
      ),
    );
    final heights = {for (final c in t.widgetList<KpiCard>(find.byType(KpiCard))) t.getSize(find.byWidget(c)).height};
    expect(heights, hasLength(1));
  });
}
