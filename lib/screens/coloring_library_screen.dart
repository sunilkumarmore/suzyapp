import 'package:flutter/material.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/coloring_page.dart';
import '../repositories/coloring_repository.dart';
import '../utils/asset_path.dart';
import 'coloring_canvas_screen.dart';

class ColoringLibraryScreen extends StatefulWidget {
  final ColoringRepository coloringRepository;

  const ColoringLibraryScreen({
    super.key,
    required this.coloringRepository,
  });

  @override
  State<ColoringLibraryScreen> createState() => _ColoringLibraryScreenState();
}

class _ColoringLibraryScreenState extends State<ColoringLibraryScreen> {
  String _search = '';
  late Future<List<ColoringPage>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ColoringPage>> _load() {
    return widget.coloringRepository.listPages(
      searchText: _search,
    );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  int _columnsForWidth(double w) {
    if (w < 520) return 2;
    if (w < 900) return 3;
    if (w < 1200) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = _columnsForWidth(w);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Coloring'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          children: [
            _SearchBar(
              initial: _search,
              onChanged: (v) {
                _search = v;
                _refresh();
              },
            ),
            const SizedBox(height: AppSpacing.medium),
            _FiltersRow(
              onClear: () {
                setState(() {
                  _search = '';
                  _future = _load();
                });
              },
            ),
            const SizedBox(height: AppSpacing.large),
            Expanded(
              child: FutureBuilder<List<ColoringPage>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  final pages = snap.data ?? [];
                  if (pages.isEmpty) {
                    return const Center(child: Text('No coloring pages found.'));
                  }

                  return GridView.builder(
                    itemCount: pages.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: AppSpacing.medium,
                      mainAxisSpacing: AppSpacing.medium,
                      childAspectRatio: 0.74,
                    ),
                    itemBuilder: (context, i) {
                      final p = pages[i];
                      return _ColoringCard(
                        page: p,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/coloring-canvas',
                            arguments: ColoringCanvasArgs(pages, initialIndex: i),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.initial, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: 'Search coloring pages…',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _FiltersRow extends StatelessWidget {
  final VoidCallback onClear;

  const _FiltersRow({
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.small,
      runSpacing: AppSpacing.small,
      children: [
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
        )
      ],
    );
  }
}

class _ColoringCard extends StatelessWidget {
  final ColoringPage page;
  final VoidCallback onTap;

  const _ColoringCard({
    required this.page,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final asset = AssetPath.normalize(page.imageAsset);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.large),
                  topRight: Radius.circular(AppRadius.large),
                ),
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.background,
                    child: const Center(child: Icon(Icons.brush, size: 42)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  _AgeBadge(text: page.ageBand),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeBadge extends StatelessWidget {
  final String text;
  const _AgeBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
