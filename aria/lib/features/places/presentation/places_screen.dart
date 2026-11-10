import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Settings › Places: saved places for "remind me when I get home".
class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Places'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-place',
        key: const Key('add-place'),
        onPressed: () => showAddPlaceSheet(context, ref),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(tr('Save this place')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          AriaTokens.s2,
          AriaTokens.s4,
          120,
        ),
        children: [
          Text(
            tr(
              'Stand at a place and tap “Save this place”. Then say “remind me to buy milk when I leave work”.',
            ),
            style: TextStyle(color: p.muted),
          ),
          const SizedBox(height: AriaTokens.s3),
          if (places.isNotEmpty) const _BackgroundLocationCard(),
          if (places.isEmpty)
            AriaCard(child: Text(tr('🏠  No places yet. Start with Home.'))),
          for (final place in places)
            Padding(
              padding: const EdgeInsets.only(bottom: AriaTokens.s2),
              child: AriaCard(
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        place.emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                    const SizedBox(width: AriaTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            tr('Within {0} m', [place.radiusM]),
                            style: TextStyle(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Remove {0}', [place.name]),
                      onPressed: () => ref
                          .read(appPrefsProvider.notifier)
                          .update(
                            (x) => x.copyWith(
                              places: [
                                ...x.places.where((e) => e.id != place.id),
                              ],
                            ),
                          ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AriaTokens.s3),
          Text(
            tr(
              'Your location is only used on this phone to notice when you arrive or leave. Aria never tracks or stores where you go.',
            ),
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Name + radius, then reads the current location. Returns the new place.
Future<SavedPlace?> showAddPlaceSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<SavedPlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddPlaceSheet(),
    );

class _AddPlaceSheet extends ConsumerStatefulWidget {
  const _AddPlaceSheet();

  @override
  ConsumerState<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends ConsumerState<_AddPlaceSheet> {
  late final _name = TextEditingController(text: tr('Home'));
  String _emoji = '🏠';
  int _radius = 150;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final here = await locateHere(ref.read(locationBridgeProvider));
    if (!mounted) return;
    if (here == null) {
      setState(() {
        _busy = false;
        _error = tr(
          'I couldn’t get your location. Allow location for Aria and try again.',
        );
      });
      return;
    }
    final place = SavedPlace(
      id: const Uuid().v4(),
      name: name,
      emoji: _emoji,
      lat: here.lat,
      lng: here.lng,
      radiusM: _radius,
    );
    ref
        .read(appPrefsProvider.notifier)
        .update(
          (x) => x.copyWith(
            places: [...x.places.where((p) => p.name != name), place],
          ),
        );
    Navigator.pop(context, place);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AriaTokens.s5,
      0,
      AriaTokens.s5,
      AriaTokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Save this place'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AriaTokens.s3),
        Wrap(
          spacing: AriaTokens.s2,
          runSpacing: AriaTokens.s2,
          children: [
            for (final (emoji, name) in SavedPlace.presets)
              ChoiceChip(
                label: Text('$emoji ${tr(name)}'),
                selected: _name.text == tr(name),
                onSelected: (_) => setState(() {
                  _name.text = tr(name);
                  _emoji = emoji;
                }),
              ),
          ],
        ),
        const SizedBox(height: AriaTokens.s3),
        TextField(
          key: const Key('place-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Name')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AriaTokens.s3),
        Text(
          tr('How close counts as “there”'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AriaTokens.s1),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 100, label: Text('100 m')),
            ButtonSegment(value: 150, label: Text('150 m')),
            ButtonSegment(value: 300, label: Text('300 m')),
            ButtonSegment(value: 500, label: Text('500 m')),
          ],
          selected: {_radius},
          onSelectionChanged: (v) => setState(() => _radius = v.first),
        ),
        if (_error != null) ...[
          const SizedBox(height: AriaTokens.s2),
          Text(_error!, style: TextStyle(color: context.palette.danger)),
        ],
        const SizedBox(height: AriaTokens.s4),
        FilledButton.icon(
          key: const Key('save-place'),
          onPressed: _busy ? null : () => unawaited(_save()),
          icon: const Icon(Icons.my_location_rounded),
          label: Text(
            _busy ? tr('Finding you…') : tr('Use my current location'),
          ),
        ),
      ],
    ),
  );
}

/// Android 10+: geofences only fire with Aria closed when location is
/// allowed "all the time". iOS location notifications don't need it.
class _BackgroundLocationCard extends ConsumerStatefulWidget {
  const _BackgroundLocationCard();

  @override
  ConsumerState<_BackgroundLocationCard> createState() =>
      _BackgroundLocationCardState();
}

class _BackgroundLocationCardState
    extends ConsumerState<_BackgroundLocationCard> {
  String? _perm;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(locationBridgeProvider).permission().then((p) {
        if (mounted) setState(() => _perm = p);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final android = Theme.of(context).platform == TargetPlatform.android;
    if (!android || _perm != 'whenInUse') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: AriaCard(
        key: const Key('background-location'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('📍 One more step for location reminders')),
            const SizedBox(height: AriaTokens.s1),
            Text(
              tr(
                'Choose “Allow all the time” so Aria can remind you even when the app is closed.',
              ),
            ),
            TextButton(
              onPressed: () async {
                final p = await ref
                    .read(locationBridgeProvider)
                    .requestPermission(background: true);
                if (mounted) setState(() => _perm = p);
              },
              child: Text(tr('Allow')),
            ),
          ],
        ),
      ),
    );
  }
}
