import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/plant.dart';
import '../services/api_service.dart';
import '../services/report_service.dart';
import 'chat_screen.dart';
import 'wishlist_screen.dart';

// ─── Display Mode ─────────────────────────────────────────────────────────────
/// Controls which sections are shown or hidden in the result screen.
enum PlantDisplayMode {
  /// Recommended / Highly Recommended — show full gardening report.
  recommended,
  /// Consider Carefully / Challenging — full report + warning banner.
  challenging,
  /// Not Recommended + malaysia_suitable==false — educational content only.
  notRecommended,
  /// cultivation_category=='botanical_only' — botanical/research info only.
  botanicalOnly,
}

class ResultScreen extends StatefulWidget {
  final Plant plant;
  final Map<String, dynamic> plantRaw;
  final String? imagePath;

  const ResultScreen({super.key, required this.plant, required this.plantRaw, this.imagePath});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _addedToGarden = false;
  bool _isAdding = false;
  bool _wishlisted = false;
  bool _isWishlisting = false;
  bool _isExporting = false;
  bool _isRefreshing = false;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _scaffoldMessenger?.clearSnackBars();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshReport() async {
    if (widget.imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No image available to re-scan.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.refresh, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text('Refresh Plant Report'),
        ]),
        content: const Text(
          'This will re-scan the image with AI and update all plant information including advantages, challenges, and pet safety.\n\nThis uses one AI credit.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRefreshing = true);
    try {
      final imageFile = File(widget.imagePath!);
      final (plant, raw) = await ApiService.identifyPlant(
        imageFile,
        imagePath: widget.imagePath!,
        forceRescan: true,
      );
      if (!mounted) return;
      // Replace current screen with fresh result
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(plant: plant, plantRaw: raw, imagePath: widget.imagePath),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Refresh failed: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _exportReport() async {
    setState(() => _isExporting = true);
    try {
      final path = await ReportService.exportPlantReport(widget.plantRaw, widget.imagePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Report saved to:\n$path'),
        backgroundColor: const Color(0xFF1B5E20),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Color _recommendationColor(String rec) {
    switch (rec.toLowerCase()) {
      case 'highly recommended': return const Color(0xFF1B5E20);
      case 'recommended':        return const Color(0xFF1565C0);
      case 'consider carefully': return const Color(0xFFE65100);
      case 'not recommended':    return const Color(0xFFB71C1C);
      default:                   return Colors.grey;
    }
  }

  Future<void> _addToGarden() async {
    DateTime? purchaseDate;
    String gardenName = '';
    String location = '';
    String plantingType = 'pot';   // 'pot' | 'ground'

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        final locationCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.local_florist, color: Color(0xFF388E3C)),
              SizedBox(width: 8),
              Text('Add to My Garden'),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Garden Name (optional)',
                    hintText: 'e.g. Red Rose, Pot #1',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // ── Planting type toggle ──────────────────────────────────
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Planting Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDlgState(() => plantingType = 'pot'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: plantingType == 'pot' ? const Color(0xFF388E3C) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: plantingType == 'pot' ? const Color(0xFF388E3C) : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.local_florist_outlined, size: 16,
                              color: plantingType == 'pot' ? Colors.white : Colors.grey),
                          const SizedBox(width: 6),
                          Text('Pot', style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: plantingType == 'pot' ? Colors.white : Colors.grey)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDlgState(() => plantingType = 'ground'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: plantingType == 'ground' ? const Color(0xFF388E3C) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: plantingType == 'ground' ? const Color(0xFF388E3C) : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.park_outlined, size: 16,
                              color: plantingType == 'ground' ? Colors.white : Colors.grey),
                          const SizedBox(width: 6),
                          Text('Ground', style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: plantingType == 'ground' ? Colors.white : Colors.grey)),
                        ]),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    hintText: 'e.g. Front Yard, Balcony',
                    prefixIcon: Icon(Icons.place_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: purchaseDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      helpText: 'When did you buy / get this plant?',
                    );
                    if (picked != null) setDlgState(() => purchaseDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Purchase / Acquired Date (optional)',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      purchaseDate != null
                          ? '${purchaseDate!.day} ${_monthName(purchaseDate!.month)} ${purchaseDate!.year}'
                          : 'Today (default)',
                      style: TextStyle(
                        fontSize: 14,
                        color: purchaseDate != null ? null : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF388E3C)),
                onPressed: () {
                  gardenName = nameCtrl.text.trim();
                  location = locationCtrl.text.trim();
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isAdding = true);
    final id = widget.plant.identification;
    final pd = widget.plant.purchaseDecision;
    final payload = <String, dynamic>{
      'plant_name': id.plantName,
      'scientific_name': id.scientificName,
      'plant_type': id.plantType,
      'recommendation': pd.recommendation,
      'suitability_score': widget.plant.gardenabilityScore,
      'image_path': widget.imagePath,
      'cultivation_category': widget.plant.cultivationCategory,
      if (gardenName.isNotEmpty) 'garden_name': gardenName,
      if (location.isNotEmpty) 'location': location,
      'planting_type': plantingType,
      if (purchaseDate != null)
        'purchase_date': purchaseDate!.toIso8601String().substring(0, 10),
    };
    // Auto-set health_status from scan result
    final rawHealth = widget.plant.health.healthStatus.toLowerCase();
    if (rawHealth.contains('healthy') || rawHealth.contains('good') || rawHealth.contains('excellent')) {
      payload['health_status'] = 'healthy';
    } else if (rawHealth.contains('recover')) {
      payload['health_status'] = 'recovering';
    } else if (rawHealth.contains('sick') || rawHealth.contains('disease') ||
               rawHealth.contains('poor') || rawHealth.contains('infect')) {
      payload['health_status'] = 'sick';
    }
    final error = await ApiService.addToMyGarden(payload);
    if (!mounted) return;
    setState(() => _isAdding = false);
    if (error == null) {
      setState(() => _addedToGarden = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${gardenName.isNotEmpty ? gardenName : id.plantName} added to your garden! 🌱'),
        backgroundColor: const Color(0xFF2E7D32),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.orange[700]),
      );
    }
  }

  static String _monthName(int m) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[m];
  }

  Future<void> _addToWishlist() async {
    setState(() => _isWishlisting = true);
    final id = widget.plant.identification;
    final pd = widget.plant.purchaseDecision;
    final error = await ApiService.addToWishlist({
      'plant_name': id.plantName,
      'scientific_name': id.scientificName,
      'plant_type': id.plantType,
      'recommendation': pd.recommendation,
      'suitability_score': widget.plant.gardenabilityScore,
      'image_path': widget.imagePath,
      'cultivation_category': widget.plant.cultivationCategory,
    });
    if (!mounted) return;
    setState(() => _isWishlisting = false);
    if (error == null) {
      setState(() => _wishlisted = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${id.plantName} saved to wishlist ❤️'),
            backgroundColor: const Color(0xFFAD1457),
            duration: const Duration(seconds: 3),
          ),
        );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.orange[700]),
      );
    }
  }

  void _showSpecialPlantAddWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔬 Conservation / Research Plant'),
        content: const Text(
          'This plant is a rare, endangered, or protected species that requires specialised institutional care. '
          'It cannot be added to your garden or wishlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Determines the display mode based on plant data and Malaysia suitability.
  ///
  /// Decision tree (first match wins):
  ///   1. botanical_only  — cultivation_category or isSpecialPlant or score == 0
  ///   2. not_recommended — score <= 20 OR rec == 'Not Recommended'
  ///   3. not_recommended — malaysia_suitable==false AND score < 40
  ///   4. challenging     — cultivation_category == 'advanced_collector'
  ///   5. challenging     — rec == 'Consider Carefully' OR score <= 60
  ///   6. recommended     — default
  static PlantDisplayMode _resolveDisplayMode(Plant plant, bool? malaysiaSuitable) {
    final score = plant.gardenabilityScore;
    final rec   = plant.purchaseDecision.recommendation;
    final cat   = plant.cultivationCategory;

    // 1. Botanical / impossible to cultivate
    if (cat == 'botanical_only' || plant.isSpecialPlant || score == 0) {
      return PlantDisplayMode.botanicalOnly;
    }

    // 2. Score below meaningful threshold or explicit Not Recommended
    if (score <= 20 || rec == 'Not Recommended') {
      return PlantDisplayMode.notRecommended;
    }

    // 3. Not suitable for Malaysia with a low score
    if (malaysiaSuitable == false && score < 40) {
      return PlantDisplayMode.notRecommended;
    }

    // 4. Advanced collector plants — always show warning
    if (cat == 'advanced_collector') {
      return PlantDisplayMode.challenging;
    }

    // 5. Consider Carefully or borderline score
    if (rec == 'Consider Carefully' || score <= 60) {
      return PlantDisplayMode.challenging;
    }

    return PlantDisplayMode.recommended;
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.plant.purchaseDecision.recommendation;
    final recColor = _recommendationColor(rec);
    final score = widget.plant.gardenabilityScore;
    final meta = widget.plantRaw['_meta'] as Map<String, dynamic>?;
    final alreadyExists = meta?['already_exists'] as bool? ?? false;
    final scanCount = meta?['scan_count'] as int? ?? 1;
    final isCached = meta?['cached'] as bool? ?? false;
    // Determine display mode — drives which sections and banners appear.
    final suitRawBuild = (widget.plantRaw['suitability'] as Map?)?.cast<String, dynamic>() ?? {};
    final malaysiaSuitableBuild = suitRawBuild['malaysia_suitable'] as bool?;
    final displayMode = _resolveDisplayMode(widget.plant, malaysiaSuitableBuild);

    return Scaffold(
        backgroundColor: const Color(0xFFF1F8F1),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              backgroundColor: const Color(0xFF2E7D32),
              iconTheme: const IconThemeData(color: Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.imagePath != null
                        ? GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _FullScreenImageViewer(imagePath: widget.imagePath!),
                              ),
                            ),
                            child: Image.file(
                              File(widget.imagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Text('🌿', style: TextStyle(fontSize: 80)),
                            ),
                          ),
                    Container(color: Colors.black.withOpacity(0.35)),
                    Positioned.fill(
                      bottom: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 80),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.plant.identification.plantName,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                widget.plant.identification.scientificName,
                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              // Plant type badge
                              if (widget.plant.identification.plantType.isNotEmpty)
                                _PlantTypePill(plantType: widget.plant.identification.plantType),
                              if (alreadyExists) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(isCached ? Icons.bolt : Icons.check_circle_outline, size: 12, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(
                                      isCached
                                          ? '⚡ From database · Scan #$scanCount'
                                          : '✓ Already scanned · Scan #$scanCount',
                                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                                    ),
                                  ]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 10),
                tabs: const [
                  Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Overview'),
                  Tab(icon: Icon(Icons.eco, size: 16), text: 'Garden'),
                  Tab(icon: Icon(Icons.straighten, size: 16), text: 'Care'),
                  Tab(icon: Icon(Icons.local_florist, size: 16), text: 'Varieties'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(plant: widget.plant, plantRaw: widget.plantRaw, recColor: recColor, score: score, gardenabilityScore: widget.plant.gardenabilityScore, displayMode: displayMode),
              _GardenFitTab(plant: widget.plant, plantRaw: widget.plantRaw, displayMode: displayMode),
              _SpaceCareTab(plant: widget.plant, plantRaw: widget.plantRaw, displayMode: displayMode),
              _FlowersTab(plant: widget.plant, displayMode: displayMode),
            ],
          ),
        ),
        bottomNavigationBar: _ActionBar(
          displayMode: displayMode,
          plant: widget.plant,
          plantRaw: widget.plantRaw,
          imagePath: widget.imagePath,
          addedToGarden: _addedToGarden,
          isAdding: _isAdding,
          wishlisted: _wishlisted,
          isWishlisting: _isWishlisting,
          isExporting: _isExporting,
          isRefreshing: _isRefreshing,
          onScan: () => Navigator.pop(context),
          onGarden: _addToGarden,
          onWishlist: _addToWishlist,
          onExport: _exportReport,
          onRefresh: _refreshReport,
          onSpecialWarning: () => _showSpecialPlantAddWarning(context),
        ),
    );
  }
}


// ─── Horizontal Scrollable Action Bar ────────────────────────────────────────
class _ActionBar extends StatelessWidget {
  final PlantDisplayMode displayMode;
  final Plant plant;
  final Map<String, dynamic> plantRaw;
  final String? imagePath;
  final bool addedToGarden, isAdding, wishlisted, isWishlisting, isExporting, isRefreshing;
  final VoidCallback onScan, onGarden, onWishlist, onExport, onRefresh, onSpecialWarning;

  const _ActionBar({
    required this.displayMode, required this.plant, required this.plantRaw,
    required this.imagePath,
    required this.addedToGarden, required this.isAdding,
    required this.wishlisted, required this.isWishlisting,
    required this.isExporting, required this.isRefreshing,
    required this.onScan, required this.onGarden, required this.onWishlist,
    required this.onExport, required this.onRefresh, required this.onSpecialWarning,
  });

  Widget _btn(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool busy = false,
    bool active = false,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: color, strokeWidth: 2))
                : Icon(icon, color: onTap == null ? Colors.grey[400] : (active ? color : color), size: 22),
            const SizedBox(height: 3),
            Text(label,
              style: TextStyle(
                fontSize: 10,
                color: onTap == null ? Colors.grey[400] : (active ? color : Colors.black87),
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGarden = displayMode == PlantDisplayMode.recommended ||
        displayMode == PlantDisplayMode.challenging;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back to scan — always first
              _btn(context,
                icon: Icons.camera_alt,
                label: 'Scan',
                color: const Color(0xFF2E7D32),
                onTap: onScan,
              ),
              _divider(),
              // My Garden — only for recommended/challenging
              if (canGarden) ...[
                _btn(context,
                  icon: addedToGarden ? Icons.check_circle : Icons.add_circle_outline,
                  label: addedToGarden ? 'In Garden' : 'My Garden',
                  color: const Color(0xFF388E3C),
                  active: addedToGarden,
                  busy: isAdding,
                  onTap: addedToGarden || plant.isSpecialPlant
                      ? null
                      : onGarden,
                ),
                _divider(),
              ],
              // Wishlist
              _btn(context,
                icon: wishlisted ? Icons.favorite : Icons.favorite_border,
                label: wishlisted ? 'Saved' : 'Wishlist',
                color: const Color(0xFFAD1457),
                active: wishlisted,
                busy: isWishlisting,
                onTap: wishlisted || plant.isSpecialPlant ? null : onWishlist,
              ),
              _divider(),
              // Chat
              _btn(context,
                icon: Icons.chat_outlined,
                label: 'AI Chat',
                color: const Color(0xFF1565C0),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ChatScreen(plant: plant, plantRaw: plantRaw))),
              ),
              _divider(),
              // Export
              _btn(context,
                icon: Icons.download_outlined,
                label: 'Export',
                color: const Color(0xFF37474F),
                busy: isExporting,
                onTap: isExporting ? null : onExport,
              ),
              // Refresh — only when image available
              if (imagePath != null) ...[
                _divider(),
                _btn(context,
                  icon: Icons.refresh,
                  label: 'Refresh',
                  color: const Color(0xFF1565C0),
                  busy: isRefreshing,
                  onTap: isRefreshing ? null : onRefresh,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1, height: 32,
    color: Colors.grey[200],
    margin: const EdgeInsets.symmetric(vertical: 8),
  );
}

// ─── TAB 1: Overview ──────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final Plant plant;
  final Map<String, dynamic> plantRaw;
  final Color recColor;
  final int score;
  final int gardenabilityScore;
  final PlantDisplayMode displayMode;

  const _OverviewTab({required this.plant, required this.plantRaw, required this.recColor, required this.score, required this.gardenabilityScore, required this.displayMode});

  IconData _recIcon(String rec) {
    switch (rec.toLowerCase()) {
      case 'highly recommended': return Icons.check_circle;
      case 'recommended': return Icons.thumb_up;
      case 'consider carefully': return Icons.warning_amber;
      default: return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pd = plant.purchaseDecision;
    final id = plant.identification;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Buy Decision header ──
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(
              plant.isSpecialPlant ? Icons.science_outlined : Icons.shopping_bag_outlined,
              color: const Color(0xFF1B5E20), size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              displayMode == PlantDisplayMode.botanicalOnly
                  ? (plant.isSpecialPlant ? '🔬 Research / Conservation Plant' : '🏛️ Botanical Reference Only')
                  : displayMode == PlantDisplayMode.notRecommended
                      ? '📚 Not Suitable for Malaysian Gardens'
                      : 'Should I Buy This Plant?',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
            ),
          ]),
        ),
        // ── AI Summary Card (always shown — summarises why plant was analysed / rejected) ──
        _AISummaryCard(plant: plant),
        const SizedBox(height: 10),
        // ── Mode Banner + Recommendation Banner ────────────────────────────────────────
        // Mode 3: red "not suitable for Malaysia" banner, no score badge
        if (displayMode == PlantDisplayMode.notRecommended) ...[          
          _EducationalModeBanner(),
          const SizedBox(height: 10),
        ],
        // Mode 1 + 2: recommendation banner with score badge
        if (displayMode == PlantDisplayMode.recommended || displayMode == PlantDisplayMode.challenging) ...[          
          Builder(builder: (_) {
          return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: recColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_recIcon(pd.recommendation), color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pd.recommendation,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$score/100',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          plant.scoreBandShort,
                          style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              if (pd.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(pd.summary, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ],
          ),
        );
          }),
          const SizedBox(height: 10),
        ],
        // Mode 2: additional challenging warning banner below score card
        if (displayMode == PlantDisplayMode.challenging) ...[
          _ChallengingBanner(),
          const SizedBox(height: 10),
        ],

        // 2. Cultivation Category Badge (shown for non-common plants)
        if (plant.cultivationCategory != 'common_garden')
          _CultivationBadge(category: plant.cultivationCategory),
        if (plant.cultivationCategory != 'common_garden') const SizedBox(height: 10),

        // 2b. Special Plant educational card
        if (plant.isSpecialPlant) ...[
          _SpecialPlantInfoCard(
            plantName: id.plantName,
            info: plant.specialPlantInfo,
          ),
          const SizedBox(height: 10),
        ],

        // 3. Confidence badge
        _ConfidenceBadge(confidence: id.confidenceLevel, plantRaw: plantRaw),
        const SizedBox(height: 8),

        // 3b. Evidence used (multi-photo) + Improve Accuracy CTA
        _EvidenceAndImproveBanner(
          plantRaw: plantRaw,
          confidence: id.confidenceLevel,
        ),

        const SizedBox(height: 12),

        // 3. Advantages — hidden for Mode 3 (not relevant); 'Interesting Facts' label for Mode 4
        if (displayMode != PlantDisplayMode.notRecommended)
        Builder(builder: (_) {
          final src = pd.advantages.isEmpty ? 'Fallback' : 'AI';
          debugPrint('Advantages source: $src (${pd.advantages.length} items for ${id.plantName})');
          if (pd.advantages.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _BulletCard(
              title: displayMode == PlantDisplayMode.botanicalOnly ? '🌿 Interesting Facts' : '✅ Advantages',
              items: pd.advantages,
              color: const Color(0xFF1B5E20),
              bgColor: const Color(0xFFE8F5E9),
            ),
            const SizedBox(height: 12),
          ]);
        }),

        // 4. Challenges — hidden for Mode 4; labeled 'Why Not Recommended' for Mode 3
        if (displayMode != PlantDisplayMode.botanicalOnly)
        Builder(builder: (_) {
          final src = pd.challenges.isEmpty ? 'Fallback' : 'AI';
          debugPrint('Challenges source: $src (${pd.challenges.length} items for ${id.plantName})');
          if (pd.challenges.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _BulletCard(
              title: displayMode == PlantDisplayMode.notRecommended ? '🚫 Why Not Recommended' : '⚠️ Potential Challenges',
              items: pd.challenges,
              color: const Color(0xFFE65100),
              bgColor: const Color(0xFFFFF3E0),
            ),
            const SizedBox(height: 12),
          ]);
        }),

        // 5. Pet Safety — always shown (important for educational + garden mode)
        Builder(builder: (_) {
            final src = plant.health.petSafetySource == 'database'
                ? 'Database'
                : plant.health.petSafetySource == 'ai'
                    ? 'AI'
                    : 'Fallback';
            debugPrint('--- Pet Safety Debug ---');
            debugPrint('Plant Name: ${plant.identification.plantName}');
            debugPrint('Scientific Name: ${plant.identification.scientificName}');
            debugPrint('Pet Safety Source: $src');
            debugPrint('Pet Safety Value: ${plant.health.petSafetyStatus}');
            return _PetSafetyBadge(health: plant.health);
          }),
        const SizedBox(height: 12),

        // 6. Plant Health — only shown for Mode 1 (Recommended) and Mode 2 (Challenging)
        if (displayMode == PlantDisplayMode.recommended || displayMode == PlantDisplayMode.challenging) ...[          
          _SectionCard(title: '❤️ Plant Health', children: [
            _InfoRow(
              icon: '🩺',
              label: 'Condition',
              value: plant.health.healthStatus,
              valueColor: plant.health.healthStatus.toLowerCase() == 'healthy' ? Colors.green : Colors.red,
            ),
            if (plant.health.disease != 'None' && plant.health.disease.isNotEmpty)
              _InfoRow(icon: '🔬', label: 'Disease', value: plant.health.disease, valueColor: Colors.red),
          ]),
          const SizedBox(height: 12),
        ],

        // 7. About This Plant
        if (id.description.isNotEmpty) ...[
          _TextCard(title: '📖 About This Plant', text: id.description),
          const SizedBox(height: 12),
        ],

        // 8. Plant Info (least urgent)
        _SectionCard(title: '🏷️ Plant Info', children: [
          _InfoRow(icon: '🌿', label: 'Family', value: id.plantFamily),
          _InfoRow(icon: '🏷️', label: 'Type', value: id.plantType),
          _InfoRow(icon: '🌍', label: 'Origin', value: id.origin),
        ]),

        const SizedBox(height: 80),
      ],
    );
  }
}

// ─── TAB 2: Garden Fit ────────────────────────────────────────────────────────
class _GardenFitTab extends StatefulWidget {
  final Plant plant;
  final Map<String, dynamic> plantRaw;
  final PlantDisplayMode displayMode;
  const _GardenFitTab({required this.plant, required this.plantRaw, required this.displayMode});

  @override
  State<_GardenFitTab> createState() => _GardenFitTabState();
}

class _GardenFitTabState extends State<_GardenFitTab> {
  late final Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = ApiService.getGardenProfile().then((v) => v ?? <String, dynamic>{});
  }

  static Map<String, int> _computeCompat(Map<String, dynamic> profile, Plant plant, bool? malaysiaSuitable) {
    // 1. Climate
    int climatePct = 75;
    if (malaysiaSuitable == true) climatePct = 92;
    else if (plant.suitability.climate.toLowerCase().contains('tropical')) climatePct = 85;

    // 2. Sunlight
    final gardenSun = (profile['sunlight'] as String? ?? '').toLowerCase();
    final plantSun  = plant.suitability.sunlight.toLowerCase();
    int gs = 3, ps = 3;
    if (gardenSun.contains('full sun'))           gs = 4;
    else if (gardenSun.contains('mostly'))        gs = 3;
    else if (gardenSun.contains('partial shade')) gs = 2;
    else if (gardenSun.contains('shade'))         gs = 1;
    if (plantSun.contains('full sun') && !plantSun.contains('partial'))     ps = 4;
    else if (plantSun.contains('direct') || plantSun.contains('bright'))    ps = 4;
    else if (plantSun.contains('partial') || plantSun.contains('dappled'))  ps = 2;
    else if (plantSun.contains('shade') && !plantSun.contains('partial'))   ps = 1;
    final sunlightPct = (100 - (gs - ps).abs() * 22).clamp(0, 100);

    // 3. Space
    final gs2 = (profile['garden_size'] as String? ?? '').toLowerCase();
    final ph  = plant.space.matureHeight.toLowerCase();
    final isLarge = ph.contains('>') || RegExp(r'[3-9]\s*m').hasMatch(ph);
    final isSmall = ph.contains('< 1') || ph.contains('0.') || RegExp(r'\d+\s*cm').hasMatch(ph);
    int spacePct = 80;
    if (gs2.contains('balcony') || gs2.contains('pot'))  spacePct = isLarge ? 40 : (isSmall ? 95 : 70);
    else if (gs2.contains('large'))                       spacePct = 95;
    else if (gs2.contains('medium'))                      spacePct = isLarge ? 70 : 90;
    else if (gs2.contains('small'))                       spacePct = isLarge ? 55 : 85;

    // 4. Maintenance
    final diff = plant.maintenance.difficulty.toLowerCase();
    final wa   = (profile['water_availability'] as String? ?? '').toLowerCase();
    int mainPct = 80;
    if (diff.contains('easy') || diff.contains('very easy'))        mainPct = 95;
    else if (diff.contains('moderate') || diff.contains('medium'))  mainPct = 78;
    else if (diff.contains('hard') || diff.contains('difficult'))   mainPct = 55;
    if (wa.contains('limited') && plant.growing.watering.toLowerCase().contains('frequent'))
      mainPct = (mainPct * 0.8).round();

    final overall = (climatePct * 0.3 + sunlightPct * 0.3 + spacePct * 0.2 + mainPct * 0.2).round();
    return {'climate': climatePct, 'sunlight': sunlightPct, 'space': spacePct, 'maintenance': mainPct, 'overall': overall};
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.plant.suitability;
    final g = widget.plant.growing;
    final suitRaw = (widget.plantRaw['suitability'] as Map?)?.cast<String, dynamic>() ?? {};
    final malaysiaSuitable = suitRaw['malaysia_suitable'] as bool?;
    final bestLocRaw = suitRaw['best_location'];
    // bestLoc: true = suitable, false = not suitable
    // bestLocConditional: location key → note string for 🟡 conditional entries
    final Map<String, bool> bestLoc;
    final Map<String, String> bestLocConditional;
    if (bestLocRaw is Map) {
      final condRaw = bestLocRaw['conditional'];
      bestLocConditional = condRaw is Map
          ? Map<String, String>.from(condRaw.map((k, v) => MapEntry(k.toString(), v.toString())))
          : <String, String>{};
      bestLoc = Map<String, bool>.from(
          bestLocRaw.entries
              .where((e) => e.key.toString() != 'conditional')
              .map((e) => MapEntry(e.key.toString(), e.value == true))
              .fold<Map<String, bool>>({}, (m, e) { m[e.key] = e.value; return m; }));
    } else {
      bestLoc = <String, bool>{};
      bestLocConditional = <String, String>{};
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Garden Compatibility card (async — future stored in initState to avoid rebuild loops)
        FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Container(
                height: 60,
                alignment: Alignment.center,
                child: const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32))),
              );
            }
            final profile = snap.data ?? {};
            // Garden Compatibility is irrelevant in Educational Mode
            if (profile.isEmpty || profile['garden_size'] == null) return const SizedBox.shrink();
            if (widget.displayMode == PlantDisplayMode.notRecommended || widget.displayMode == PlantDisplayMode.botanicalOnly) {
              return const SizedBox.shrink();
            }
            final compat = _computeCompat(profile, widget.plant, malaysiaSuitable);
            return Column(children: [
              _GardenCompatCard(compat: compat),
              const SizedBox(height: 12),
            ]);
          },
        ),
        _SectionCard(title: '🌍 Climate & Environment', children: [
          _InfoRow(icon: '🌡️', label: 'Climate', value: s.climate),
          if (malaysiaSuitable != null)
            _InfoRow(
              icon: '🇲🇾',
              label: 'Malaysia Suitable',
              value: malaysiaSuitable ? '✓ Yes' : '✗ No',
              valueColor: malaysiaSuitable ? const Color(0xFF2E7D32) : Colors.red,
            ),
          _InfoRow(icon: '🌡️', label: 'Temperature', value: s.temperatureRange),
          _InfoRow(icon: '☀️', label: 'Sunlight', value: s.sunlight),
          _InfoRow(icon: '💧', label: 'Humidity', value: s.humidity),
          _InfoRow(icon: '💨', label: 'Wind Tolerance', value: s.windTolerance),
        ]),
        if (bestLoc.isNotEmpty) ...[
          const SizedBox(height: 12),
          // Garden placement hidden for Mode 3 and Mode 4
          if (widget.displayMode != PlantDisplayMode.notRecommended && widget.displayMode != PlantDisplayMode.botanicalOnly)
            if (widget.plant.cultivationCategory == 'botanical_only')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF6F00)),
                ),
                child: const Row(children: [
                  Text('🏠', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(child: Text(
                    'Not suitable for home cultivation. This species requires institutional or botanical garden care.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6D4C41), fontStyle: FontStyle.italic),
                  )),
                ]),
              )
            else
              _BestLocationCard(locations: bestLoc, conditional: bestLocConditional),
        ],
        const SizedBox(height: 12),
        // Watering schedule — Mode 1 and Mode 2 only
        if (widget.displayMode == PlantDisplayMode.recommended || widget.displayMode == PlantDisplayMode.challenging) _WateringVisual(
          watering: g.watering,
          wateringRec: widget.plantRaw['watering_recommended'] as Map<String, dynamic>?,
        ),
        if (widget.displayMode == PlantDisplayMode.recommended || widget.displayMode == PlantDisplayMode.challenging) const SizedBox(height: 12),
        // Growing Requirements — Mode 1 and Mode 2 only
        if (widget.displayMode == PlantDisplayMode.recommended || widget.displayMode == PlantDisplayMode.challenging)
        _SectionCard(title: '🌱 Growing Requirements', children: [
          _InfoRow(icon: '🪱', label: 'Soil Type', value: g.soilType),
          _InfoRow(icon: '⚗️', label: 'Soil pH', value: g.soilPh),
          _InfoRow(icon: '🧪', label: 'Fertilizer', value: g.fertilizer),
          _InfoRow(icon: '🍂', label: 'Mulching', value: g.mulching),
          _InfoRow(icon: '🪴', label: 'Pot or Ground', value: g.potOrGround),
          _InfoRow(icon: '🌊', label: 'Drainage', value: g.drainage),
        ]),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ─── Garden Compatibility Card ────────────────────────────────────────────────
class _GardenCompatCard extends StatelessWidget {
  final Map<String, int> compat;
  const _GardenCompatCard({required this.compat});

  Color _pctColor(int v) {
    if (v >= 80) return const Color(0xFF2E7D32);
    if (v >= 60) return const Color(0xFFE65100);
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final overall = compat['overall'] ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.analytics_outlined, color: Color(0xFF1B5E20), size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Garden Compatibility Analysis',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _pctColor(overall).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$overall% Match',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _pctColor(overall))),
            ),
          ]),
          const SizedBox(height: 12),
          _CompatRow(emoji: '🌡️', label: 'Climate', pct: compat['climate'] ?? 0, color: _pctColor(compat['climate'] ?? 0),
              explanation: (compat['climate'] ?? 0) < 70 ? 'Climate may not fully match. Consider extra shade or shelter.' : null),
          const SizedBox(height: 8),
          _CompatRow(emoji: '☀️', label: 'Sunlight', pct: compat['sunlight'] ?? 0, color: _pctColor(compat['sunlight'] ?? 0),
              explanation: (compat['sunlight'] ?? 0) < 70 ? "Garden sunlight doesn't match this plant's requirements." : null),
          const SizedBox(height: 8),
          _CompatRow(emoji: '📐', label: 'Space', pct: compat['space'] ?? 0, color: _pctColor(compat['space'] ?? 0),
              explanation: (compat['space'] ?? 0) < 70 ? 'Plant may outgrow your available space at maturity.' : null),
          const SizedBox(height: 8),
          _CompatRow(emoji: '🌱', label: 'Maintenance', pct: compat['maintenance'] ?? 0, color: _pctColor(compat['maintenance'] ?? 0),
              explanation: (compat['maintenance'] ?? 0) < 70 ? 'This plant requires more care than typical easy-care plants.' : null),
        ],
      ),
    );
  }
}

class _CompatRow extends StatelessWidget {
  final String emoji;
  final String label;
  final int pct;
  final Color color;
  final String? explanation;
  const _CompatRow({required this.emoji, required this.label, required this.pct, required this.color, this.explanation});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
        Text('$pct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 3),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct / 100,
          minHeight: 6,
          backgroundColor: Colors.grey.shade100,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
      if (explanation != null) ...[
        const SizedBox(height: 4),
        Row(children: [
          const Text('⚠️', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(child: Text(explanation!,
              style: const TextStyle(fontSize: 11, color: Colors.orange))),
        ]),
      ],
    ]);
  }
}

class _BestLocationCard extends StatelessWidget {
  final Map<String, bool> locations;
  final Map<String, String> conditional;
  const _BestLocationCard({required this.locations, this.conditional = const {}});

  // Returns: 1 = suitable, 0 = conditional, -1 = not suitable
  int _status(String key) {
    if (conditional.containsKey(key)) return 0;
    return (locations[key] ?? false) ? 1 : -1;
  }

  Widget _chip(BuildContext context, String key, String emoji, String label) {
    final status = _status(key);
    final Color bg, border, textColor, iconColor;
    final IconData iconData;
    final String? note = conditional[key];

    if (status == 1) {
      bg = const Color(0xFFE8F5E9); border = const Color(0xFF2E7D32);
      textColor = const Color(0xFF2E7D32); iconColor = const Color(0xFF2E7D32);
      iconData = Icons.check;
    } else if (status == 0) {
      bg = const Color(0xFFFFF8E1); border = const Color(0xFFF9A825);
      textColor = const Color(0xFFE65100); iconColor = const Color(0xFFF9A825);
      iconData = Icons.info_outline;
    } else {
      bg = const Color(0xFFFAFAFA); border = Colors.grey.shade300;
      textColor = Colors.grey.shade500; iconColor = Colors.grey.shade400;
      iconData = Icons.close;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: textColor)),
        const SizedBox(width: 4),
        Icon(iconData, size: 12, color: iconColor),
      ]),
    );

    if (status == 0 && note != null) {
      return Tooltip(message: note, preferBelow: true, child: chip);
    }
    return chip;
  }

  @override
  Widget build(BuildContext context) {
    // Collect conditional notes to show below the chips
    final notes = conditional.entries.toList();
    final locationLabels = {'balcony': 'Balcony', 'front_yard': 'Front Yard', 'porch': 'Porch', 'indoor': 'Indoor'};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📍 Best Garden Location',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(context, 'balcony', '🏠', 'Balcony'),
          _chip(context, 'front_yard', '🌳', 'Front Yard'),
          _chip(context, 'porch', '🚪', 'Porch'),
          _chip(context, 'indoor', '🪴', 'Indoor'),
        ]),
        // Conditional notes
        if (notes.isNotEmpty) ...[          const SizedBox(height: 10),
          ...notes.map((e) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🟡 ', style: TextStyle(fontSize: 12)),
              Text(
                '${locationLabels[e.key] ?? e.key}: ${e.value}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF795548), height: 1.4),
              ),
            ]),
          )),
        ],
      ]),
    );
  }
}

// ─── TAB 3: Space & Care ──────────────────────────────────────────────────────
class _SpaceCareTab extends StatelessWidget {
  final Plant plant;
  final Map<String, dynamic> plantRaw;
  final PlantDisplayMode displayMode;
  const _SpaceCareTab({required this.plant, required this.plantRaw, required this.displayMode});

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy': return Colors.green;
      case 'medium': return Colors.orange;
      case 'hard': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = plant.space;
    final m = plant.maintenance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (displayMode == PlantDisplayMode.notRecommended || displayMode == PlantDisplayMode.botanicalOnly)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC62828)),
            ),
            child: const Row(children: [
              Text('📚', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Dimensions shown for reference only — this plant is not suitable for home cultivation in Malaysia.',
                style: TextStyle(fontSize: 12, color: Color(0xFFC62828), fontStyle: FontStyle.italic),
              )),
            ]),
          ),
        _SectionCard(title: '📐 Space Planning', children: [
          _InfoRow(icon: '📏', label: 'Mature Height', value: sp.matureHeight),
          _InfoRow(icon: '📐', label: 'Mature Width', value: sp.matureWidth),
          _InfoRow(icon: '⚡', label: 'Growth Rate', value: sp.growthRate),
          _InfoRow(icon: '🌳', label: 'Root Spread', value: sp.rootSpread),
          _InfoRow(icon: '↔️', label: 'Plant Spacing', value: sp.spacing),
        ]),
        // Maintenance level and seasonal care — Mode 1 and Mode 2 only
        if (displayMode == PlantDisplayMode.recommended || displayMode == PlantDisplayMode.challenging) ...[
          const SizedBox(height: 12),
          _SectionCard(title: '🔧 Maintenance', children: [
            _DifficultyRow(difficulty: m.difficulty),
            _InfoRow(icon: '✂️', label: 'Pruning', value: m.pruning),
            _InfoRow(icon: '🐛', label: 'Pest Risk', value: m.pestSusceptibility),
            _InfoRow(icon: '🦠', label: 'Disease Risk', value: m.diseaseSusceptibility),
          ]),
          const SizedBox(height: 12),
          if (m.seasonalCare.isNotEmpty)
            _TextCard(title: '📅 Seasonal Care', text: m.seasonalCare),
          const SizedBox(height: 12),
          _MalaysiaWateringGuide(
            watering: plant.growing.watering,
            wateringRec: plantRaw['watering_recommended'] as Map<String, dynamic>?,
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

void _showSimilarPlantSheet(BuildContext context, SimilarPlant plant) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('🌿 ${plant.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          if (plant.scientificName.isNotEmpty)
            Text(plant.scientificName, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF558B2F))),
          const SizedBox(height: 8),
          const Text('What would you like to do with this plant?', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final error = await ApiService.addToWishlist({
                      'plant_name': plant.name,
                      'scientific_name': plant.scientificName,
                      'plant_type': 'Unknown',
                      'recommendation': 'Unknown',
                      'suitability_score': 0,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(error ?? '${plant.name} added to wishlist ❤️'),
                        backgroundColor: error != null ? Colors.orange[700] : const Color(0xFF2E7D32),
                      ));
                    }
                  },
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Add to Wishlist'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2E7D32)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ─── TAB 4: Flowers ───────────────────────────────────────────────────────────
class _FlowersTab extends StatelessWidget {
  final Plant plant;
  final PlantDisplayMode displayMode;
  const _FlowersTab({required this.plant, required this.displayMode});

  Color _chipColor(String name) {
    switch (name.toLowerCase().trim()) {
      case 'pink':     return Colors.pink[200]!;
      case 'white':    return Colors.grey[100]!;
      case 'purple':   return Colors.purple[300]!;
      case 'violet':   return Colors.purple[400]!;
      case 'lavender': return Colors.purple[200]!;
      case 'yellow':   return Colors.yellow[600]!;
      case 'red':      return Colors.red[400]!;
      case 'orange':   return Colors.orange[400]!;
      case 'blue':     return Colors.blue[400]!;
      case 'green':    return Colors.green[400]!;
      case 'cream':    return const Color(0xFFFFF8DC);
      case 'salmon':   return Colors.deepOrange[200]!;
      default:         return Colors.grey[300]!;
    }
  }

  Color _chipText(String name) {
    final bg = _chipColor(name);
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final f = plant.flowering;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Color Chips ──────────────────────────────────────────────────────
        if (f.flowerColors.isNotEmpty) ...[
          _SectionCard(title: '🎨 Available Colors', children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: f.flowerColors.map((c) {
                final bg = _chipColor(c);
                final fg = _chipText(c);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: fg.withOpacity(0.4), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(c, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ]),
          const SizedBox(height: 12),
        ],

        // ── Seasonal Info ─────────────────────────────────────────────────────
        if ([f.floweringSeason, f.fruitingSeason, f.harvestInfo].any((s) => s.isNotEmpty && s != 'N/A'))
          _SectionCard(title: '📅 Season & Harvest', children: [
            if (f.floweringSeason.isNotEmpty && f.floweringSeason != 'N/A')
              _InfoRow(icon: '🌼', label: 'Flowers', value: f.floweringSeason),
            if (f.fruitingSeason.isNotEmpty && f.fruitingSeason != 'N/A')
              _InfoRow(icon: '🍎', label: 'Fruits', value: f.fruitingSeason),
            if (f.harvestInfo.isNotEmpty && f.harvestInfo != 'N/A')
              _InfoRow(icon: '🧺', label: 'Harvest', value: f.harvestInfo),
          ]),
        if ([f.floweringSeason, f.fruitingSeason, f.harvestInfo].any((s) => s.isNotEmpty && s != 'N/A'))
          const SizedBox(height: 12),

        // ── Popular Varieties ─────────────────────────────────────────────────
        if (f.popularVarieties.isNotEmpty) ...[
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🌺 Popular Varieties',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                  const Divider(height: 16),
                  ...f.popularVarieties.map((v) {
                    final Color dc;
                    final String di;
                    switch (v.difficulty.toLowerCase()) {
                      case 'easy':   dc = const Color(0xFF2E7D32); di = '⭐ Easy'; break;
                      case 'medium': dc = const Color(0xFFE65100); di = '⭐⭐ Medium'; break;
                      case 'hard':   dc = const Color(0xFFB71C1C); di = '⭐⭐⭐ Hard'; break;
                      default:       dc = Colors.grey; di = v.difficulty;
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Text('🌸', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                if (v.note.isNotEmpty)
                                  Text(v.note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: dc.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(di, style: TextStyle(fontSize: 11, color: dc, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Popular in Region ────────────────────────────────────────────────
        if (plant.gardenabilityScore >= 30 && f.popularInRegion.isNotEmpty) ...[
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📍 Most Popular in Your Region',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                  const Divider(height: 16),
                  ...f.popularInRegion.asMap().entries.map((e) {
                    final medals = ['🥇', '🥈', '🥉'];
                    final medal = e.key < medals.length ? medals[e.key] : '▸';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(medal, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(e.value,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Price Range — Mode 1 and Mode 2 only ───────────────────────────────
        if (displayMode == PlantDisplayMode.recommended || displayMode == PlantDisplayMode.challenging)
        Builder(builder: (context) {
          final np = plant.nurseryPrice;

          // Botanical-only: show a special "not available" card instead of price grid
          if (np.isNotCommerciallyAvailable) {
            return Column(children: [
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💰 Nursery Price',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const Divider(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(children: [
                          const Text('🚫', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(
                            np.unavailableMessage,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6D4C41)),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This species is not sold in commercial nurseries and cannot be purchased for home cultivation.',
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ]);
          }

          // Prefer nursery_price from API; fall back to GPT flowering prices.
          final f = plant.flowering;
          final small  = np.small.isNotEmpty  ? np.small  : f.priceSmall;
          final medium = np.medium.isNotEmpty ? np.medium : f.priceMedium;
          final large  = np.large.isNotEmpty  ? np.large  : f.priceLarge;
          if (small.isEmpty && medium.isEmpty && large.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💰 Estimated Malaysia Nursery Price',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const Divider(height: 16),
                      Row(
                        children: [
                          if (small.isNotEmpty)  Expanded(child: _PriceCard(label: 'Small\nPot',     price: small,  color: const Color(0xFF1B5E20))),
                          if (small.isNotEmpty && medium.isNotEmpty) const SizedBox(width: 8),
                          if (medium.isNotEmpty) Expanded(child: _PriceCard(label: 'Medium\nPot',    price: medium, color: const Color(0xFF1565C0))),
                          if (medium.isNotEmpty && large.isNotEmpty) const SizedBox(width: 8),
                          if (large.isNotEmpty)  Expanded(child: _PriceCard(label: 'Large /\nMature', price: large,  color: const Color(0xFF6A1B9A))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '💡 Estimated Malaysia nursery price. Actual prices may vary by nursery, location and plant maturity.',
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          );
        }),

        // ── Section A: Similar Flowers (visual lookalikes) ──────────────────
        // Shown for Mode 1 (Recommended) and Mode 2 (Challenging) only.
        // Hidden for Mode 3 (Not Recommended) and Mode 4 (Botanical Only).
        if ((displayMode == PlantDisplayMode.recommended || displayMode == PlantDisplayMode.challenging) &&
            f.similarFlowers.isNotEmpty) ...[
          _RecommendationSection(
            title: '🌸 Visually Similar Flowers',
            subtitle: 'Flowers that share similar shape, colour and bloom style.',
            plants: f.similarFlowers,
            onWishlist: (p) => _showSimilarPlantSheet(context, p),
            onView: (p) => _showSimilarPlantView(context, p),
            accentColor: const Color(0xFF880E4F),
          ),
          const SizedBox(height: 12),
        ],

        // ── Section B: Malaysian Alternatives ──────────────────────────────
        // Mode 1/2: shown as "You May Also Like" (care + landscape match)
        // Mode 3 (Not Recommended): shown prominently as the primary recommendation
        // Mode 4 (Botanical Only): hidden entirely
        () {
          final altList = f.malaysiaAlternatives.isNotEmpty
              ? f.malaysiaAlternatives
              : f.similarPlants; // backward compat for cached records
          if (displayMode == PlantDisplayMode.botanicalOnly || altList.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              _RecommendationSection(
                title: displayMode == PlantDisplayMode.notRecommended
                    ? '🌿 Recommended Malaysian Alternatives'
                    : '🌿 Malaysian Plants You May Like',
                subtitle: displayMode == PlantDisplayMode.notRecommended
                    ? 'These plants grow well in Malaysia and provide a similar effect in your garden.'
                    : 'Malaysia-suitable plants with similar care requirements.',
                plants: altList,
                onWishlist: (p) => _showSimilarPlantSheet(context, p),
                onView: (p) => _showSimilarPlantView(context, p),
                accentColor: const Color(0xFF1B5E20),
                highlight: displayMode == PlantDisplayMode.notRecommended,
                isAlternative: true,
              ),
              const SizedBox(height: 12),
            ],
          );
        }(),

        // ── Empty state ───────────────────────────────────────────────────────
        if (f.flowerColors.isEmpty && f.popularVarieties.isEmpty && f.floweringSeason.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Text('🌿', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text(
                  'No flowering information available for this plant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),

        const SizedBox(height: 80),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  final String label;
  final String price;
  final Color color;
  const _PriceCard({required this.label, required this.price, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(price, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─── Recommendation Section (reusable for both Similar Flowers + Alternatives) ─
class _RecommendationSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SimilarPlant> plants;
  final void Function(SimilarPlant) onWishlist;
  final void Function(SimilarPlant) onView;
  final Color accentColor;
  final bool highlight;
  final bool isAlternative;

  const _RecommendationSection({
    required this.title,
    required this.subtitle,
    required this.plants,
    required this.onWishlist,
    required this.onView,
    required this.accentColor,
    this.highlight = false,
    this.isAlternative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: highlight ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight ? BorderSide(color: accentColor.withOpacity(0.4), width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accentColor),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: accentColor.withOpacity(0.75), fontStyle: FontStyle.italic),
            ),
            const Divider(height: 14),
            SizedBox(
              height: 162,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: plants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) => _SimilarPlantCard(
                  plant: plants[i],
                  isAlternative: isAlternative,
                  onWishlist: () => onWishlist(plants[i]),
                  onView: () => onView(plants[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared image cache (card + detail sheet both use this) ─────────────────
final Map<String, Uint8List?> _similarPlantImageCache = {};

// ─── Similar Plant Photo Card ─────────────────────────────────────────────────
class _SimilarPlantCard extends StatefulWidget {
  final SimilarPlant plant;
  final bool isAlternative;
  final VoidCallback onWishlist;
  final VoidCallback onView;
  const _SimilarPlantCard({
    required this.plant,
    required this.onWishlist,
    required this.onView,
    this.isAlternative = false,
  });

  @override
  State<_SimilarPlantCard> createState() => _SimilarPlantCardState();
}

class _SimilarPlantCardState extends State<_SimilarPlantCard> {
  Uint8List? _imageBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  String get _cacheKey =>
      widget.plant.scientificName.isNotEmpty ? widget.plant.scientificName : widget.plant.name;

  Future<Uint8List?> _tryFetch(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final url = '${ApiService.baseUrl}/plant-image?name=$encoded';
      final client = ApiService.directClient();
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 35));
      client.close();
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('[SimilarPlant] "${widget.plant.name}" image error: $e');
    }
    return null;
  }

  Future<void> _fetchImage() async {
    if (!mounted) return;
    setState(() { _loading = true; });

    final key = _cacheKey;
    // Only serve from cache if the stored value is non-null (a real image).
    // Null entries are NOT cached so temporary failures (503 rate-limit, network)
    // are retried on the next attempt.
    if (_similarPlantImageCache.containsKey(key) && _similarPlantImageCache[key] != null) {
      if (mounted) setState(() { _imageBytes = _similarPlantImageCache[key]; _loading = false; });
      return;
    }

    Uint8List? bytes;

    // Attempt 1: image_query — best search term, already normalized by backend.
    // Always try this first; do NOT skip when imageQuery == name, because the
    // backend _normalize_image_query() may still improve the raw name (strips
    // parentheticals, genus-only forms, etc.).
    final iq = widget.plant.imageQuery;
    if (iq.isNotEmpty) {
      bytes = await _tryFetch(iq);
    }

    // Attempt 2: scientific name (only if it differs from imageQuery)
    if (bytes == null && widget.plant.scientificName.isNotEmpty &&
        widget.plant.scientificName != iq) {
      bytes = await _tryFetch(widget.plant.scientificName);
    }

    // Attempt 3: common name (only if it differs from both previous attempts)
    if (bytes == null && widget.plant.name.isNotEmpty &&
        widget.plant.name != iq && widget.plant.name != widget.plant.scientificName) {
      bytes = await _tryFetch(widget.plant.name);
    }

    // Only cache success — never cache null so rate-limit failures can be retried
    if (bytes != null) {
      _similarPlantImageCache[key] = bytes;
    }
    if (mounted) setState(() { _imageBytes = bytes; _loading = false; });
  }

  Color _scoreColor(int s) {
    if (s >= 95) return const Color(0xFF1B5E20);  // Excellent
    if (s >= 90) return const Color(0xFF2E7D32);  // Strong
    if (s >= 85) return const Color(0xFF00695C);  // Moderate / Good
    if (s >= 70) return const Color(0xFFE65100);  // Below threshold fallback
    return Colors.grey[600]!;
  }

  String _qualityBadge(int score) {
    if (widget.isAlternative) {
      if (score >= 92) return '🌟 Excellent ($score%)';
      if (score >= 88) return '👍 Good ($score%)';
      return '$score%';
    } else {
      if (score >= 95) return '🌟 Excellent ($score%)';
      if (score >= 90) return '✅ Strong ($score%)';
      if (score >= 85) return '👍 Good ($score%)';
      return '$score%';
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.plant.score;
    final sc = _scoreColor(score);
    return SizedBox(
      width: 150,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image (fixed 70px) ──
            SizedBox(
              height: 70,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _loading
                      ? Container(
                          color: const Color(0xFFE8F5E9),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32))),
                        )
                      : _imageBytes != null
                          ? Image.memory(_imageBytes!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _plantPlaceholder())
                          : GestureDetector(
                              onTap: _fetchImage,  // tap placeholder to retry
                              child: _plantPlaceholder(),
                            ),
                  // Score badge — top-right corner
                  if (score > 0)
                    Positioned(
                      top: 5, right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sc, width: 0.8),
                        ),
                        child: Text(
                          _qualityBadge(score),
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: sc),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Text body ──
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.plant.name,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.plant.scientificName.isNotEmpty)
                      Text(
                        widget.plant.scientificName,
                        style: const TextStyle(fontSize: 7.5, fontStyle: FontStyle.italic, color: Color(0xFF558B2F)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (widget.plant.reason.isNotEmpty) ...
                      [
                        const SizedBox(height: 2),
                        Text(
                          widget.plant.reason,
                          style: const TextStyle(fontSize: 8, color: Color(0xFF616161)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    const Spacer(),
                    // ── Action row ──
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onWishlist,
                              behavior: HitTestBehavior.opaque,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.favorite_border, size: 10, color: Color(0xFF2E7D32)),
                                  SizedBox(width: 2),
                                  Text('Wishlist', style: TextStyle(fontSize: 8, color: Color(0xFF2E7D32))),
                                ],
                              ),
                            ),
                          ),
                          Container(width: 0.5, height: 14, color: const Color(0xFFBDBDBD)),
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onView,
                              behavior: HitTestBehavior.opaque,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.visibility_outlined, size: 10, color: Color(0xFF1565C0)),
                                  SizedBox(width: 2),
                                  Text('View', style: TextStyle(fontSize: 8, color: Color(0xFF1565C0))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plantPlaceholder() => Container(
    color: const Color(0xFFE8F5E9),
    child: const Center(child: Text('🌿', style: TextStyle(fontSize: 28))),
  );
}

// ─── Similar Plant Detail Sheet ───────────────────────────────────────────────
void _showSimilarPlantView(BuildContext context, SimilarPlant plant) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _SimilarPlantDetailSheet(plant: plant),
  );
}

class _SimilarPlantDetailSheet extends StatefulWidget {
  final SimilarPlant plant;
  const _SimilarPlantDetailSheet({required this.plant});

  @override
  State<_SimilarPlantDetailSheet> createState() => _SimilarPlantDetailSheetState();
}

class _SimilarPlantDetailSheetState extends State<_SimilarPlantDetailSheet> {
  Uint8List? _imageBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  String get _cacheKey =>
      widget.plant.scientificName.isNotEmpty ? widget.plant.scientificName : widget.plant.name;

  Future<void> _loadImage() async {
    final key = _cacheKey;
    // Use the shared card cache first
    if (_similarPlantImageCache.containsKey(key)) {
      final cached = _similarPlantImageCache[key];
      if (mounted) setState(() { _imageBytes = cached; _loading = false; });
      return;
    }
    // Fetch (scientific name first)
    Uint8List? bytes;
    try {
      for (final name in [
        widget.plant.scientificName,
        widget.plant.name,
      ].where((s) => s.isNotEmpty)) {
        final encoded = Uri.encodeComponent(name);
        final client = ApiService.directClient();
        final response = await client
            .get(Uri.parse('${ApiService.baseUrl}/plant-image?name=$encoded'))
            .timeout(const Duration(seconds: 35));
        client.close();
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          bytes = response.bodyBytes;
          break;
        }
      }
    } catch (_) {}
    _similarPlantImageCache[key] = bytes;
    if (mounted) setState(() { _imageBytes = bytes; _loading = false; });
  }

  Color _scoreColor(int s) {
    if (s >= 85) return const Color(0xFF1B5E20);
    if (s >= 70) return const Color(0xFF2E7D32);
    if (s >= 55) return const Color(0xFFE65100);
    return Colors.grey[700]!;
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final sc = _scoreColor(plant.score);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ),
              // Plant image
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: double.infinity,
                  height: 190,
                  child: _loading
                      ? Container(
                          color: const Color(0xFFE8F5E9),
                          child: const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))),
                        )
                      : _imageBytes != null
                          ? Image.memory(_imageBytes!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFE8F5E9),
                                child: const Center(child: Text('🌿', style: TextStyle(fontSize: 56)))))
                          : Container(
                              color: const Color(0xFFE8F5E9),
                              child: const Center(child: Text('🌿', style: TextStyle(fontSize: 56)))),
                ),
              ),
              const SizedBox(height: 14),
              // Name + score row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plant.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                        if (plant.scientificName.isNotEmpty)
                          Text(
                            plant.scientificName,
                            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF558B2F)),
                          ),
                      ],
                    ),
                  ),
                  if (plant.score > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sc.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sc.withOpacity(0.4)),
                      ),
                      child: Column(
                        children: [
                          Text('${plant.score}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sc)),
                          Text('Match', style: TextStyle(fontSize: 9, color: sc)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // Reason
              if (plant.reason.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(plant.reason, style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32))),
                ),
              // Tags
              if (plant.tags.isNotEmpty) ...
                [
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: plant.tags.map((tag) {
                      const tagEmoji = {
                        'Full Sun': '🌞', 'Partial Shade': '⛅', 'Full Shade': '🌑',
                        'Low Water': '💧', 'Flowering': '🌺', 'Fragrant': '🌸',
                        'Fruit': '🍊', 'Easy Care': '✅', 'Climber': '🌿',
                        'Indoor': '🏠', 'Water Plant': '🌊', 'Tropical': '🌴',
                      };
                      final emoji = tagEmoji[tag] ?? '🌱';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFA5D6A7)),
                        ),
                        child: Text('$emoji $tag', style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
                      );
                    }).toList(),
                  ),
                ],
              const SizedBox(height: 6),
              // Nursery note
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.store_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Commonly available in Malaysian nurseries',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Wishlist button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.favorite_border),
                  label: Text('Add ${plant.name} to Wishlist'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final error = await ApiService.addToWishlist({
                      'plant_name': plant.name,
                      'scientific_name': plant.scientificName,
                      'plant_type': 'Unknown',
                      'recommendation': 'Unknown',
                      'suitability_score': 0,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(error ?? '${plant.name} added to wishlist ❤️'),
                        backgroundColor: error != null ? Colors.orange[700] : const Color(0xFF2E7D32),
                      ));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Full Screen Image Viewer ─────────────────────────────────────────────────
class _FullScreenImageViewer extends StatelessWidget {
  final String imagePath;
  const _FullScreenImageViewer({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Photo', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Special Plant Educational Card ──────────────────────────────────────────
class _SpecialPlantInfoCard extends StatelessWidget {
  final String plantName;
  final SpecialPlantInfo? info;
  const _SpecialPlantInfoCard({required this.plantName, required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),   // deep indigo
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF283593),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(children: [
              const Text('🔬', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Special / Research Plant',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('Not suitable for home gardening',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB3C5F5))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFB71C1C).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('❌ Not for home gardens',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ]),
          ),

          // ── Notice ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('⚠️', style: TextStyle(fontSize: 18)),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'This plant is not suitable for normal home gardening and requires '
                  'specialized natural conditions that cannot be replicated at home.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE8EAF6), height: 1.5),
                )),
              ]),
            ),
          ),

          if (info != null) ...[
            // ── Fact grid ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  if (info!.flowerDiameter.isNotEmpty)
                    _SplInfoChip(label: 'Flower / Inflorescence', value: info!.flowerDiameter),
                  if (info!.flowerLifespan.isNotEmpty)
                    _SplInfoChip(label: 'Bloom lifespan', value: info!.flowerLifespan),
                  if (info!.nativeRegion.isNotEmpty)
                    _SplInfoChip(label: 'Native region', value: info!.nativeRegion),
                  if (info!.conservationStatus.isNotEmpty)
                    _SplInfoChip(
                      label: 'Conservation',
                      value: info!.conservationStatus,
                      valueColor: info!.conservationStatus.toLowerCase().contains('critical')
                          ? const Color(0xFFFF6B6B)
                          : info!.conservationStatus.toLowerCase().contains('endangered')
                              ? const Color(0xFFFFB347)
                              : const Color(0xFF98C379),
                    ),
                  if (info!.isLargestFlower)
                    _SplInfoChip(label: 'Record', value: 'World\'s Largest Flower 🏆',
                        valueColor: const Color(0xFFFFD700)),
                ],
              ),
            ),

            // ── Habitat ───────────────────────────────────────────────────
            if (info!.habitat.isNotEmpty)
              _SplInfoRow(icon: '🌿', label: 'Natural Habitat', value: info!.habitat),

            // ── Host plant ────────────────────────────────────────────────
            if (info!.hostPlantRequired) ...[
              _SplInfoRow(
                icon: '🌱',
                label: 'Host Plant Required',
                value: info!.hostPlant,
                highlight: true,
              ),
            ],

            // ── Cultivation note ──────────────────────────────────────────
            if (info!.cultivationNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF9A9A).withOpacity(0.4)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🚫', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(info!.cultivationNote,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFFCDD2), height: 1.5))),
                  ]),
                ),
              ),

            // ── Interesting facts ─────────────────────────────────────────
            if (info!.interestingFacts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: const Text('💡 Fascinating Facts',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFB3C5F5))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: info!.interestingFacts.map((fact) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('▸ ', style: TextStyle(color: Color(0xFF7986CB), fontSize: 14)),
                      Expanded(child: Text(fact,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFE8EAF6), height: 1.5))),
                    ]),
                  )).toList(),
                ),
              ),
            ],
          ],

          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _SplInfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SplInfoChip({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9FA8DA))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.white)),
      ]),
    );
  }
}

class _SplInfoRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final bool highlight;
  const _SplInfoRow({required this.icon, required this.label, required this.value, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9FA8DA))),
          Text(value, style: TextStyle(
              fontSize: 13,
              color: highlight ? const Color(0xFFFF6B6B) : Colors.white,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
        ])),
      ]),
    );
  }
}

// ─── Challenging Banner (Mode 2) ─────────────────────────────────────────────
class _ChallengingBanner extends StatelessWidget {
  const _ChallengingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE65100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Challenging — Extra Care Required',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'This plant can be grown in Malaysia but demands more attention than typical garden plants. '
                  'Review the care requirements carefully before purchasing.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFFCCBC)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Educational Mode Banner (Mode 3 — Not Recommended / Malaysia Unsuitable) ─
class _EducationalModeBanner extends StatelessWidget {
  const _EducationalModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🚫', style: TextStyle(fontSize: 26)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Not Suitable for Cultivation in Malaysia',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'This plant is not recommended for home gardening in Malaysia. '
            'Climate conditions, cultivation requirements, or conservation status '
            'make it unsuitable for residential gardens.',
            style: TextStyle(fontSize: 12, color: Color(0xFFFFCDD2)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Text('📚', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Educational Mode — Scientific and botanical information shown for reference only.',
                style: TextStyle(fontSize: 12, color: Colors.white, fontStyle: FontStyle.italic),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Conservation / Educational Plant Card ────────────────────────────────────
class _ConservationCard extends StatelessWidget {
  final int score;
  const _ConservationCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF37474F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🏛️', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Conservation / Educational Plant',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$score/100',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEF9A9A)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C).withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Text('❌', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Not Recommended For Home Gardening',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              )),
            ]),
          ),
          const SizedBox(height: 10),
          const Text(
            'This species is not suitable for typical residential gardens and requires specialized environmental conditions.',
            style: TextStyle(fontSize: 12, color: Color(0xFFCFD8DC)),
          ),
        ],
      ),
    );
  }
}

// ─── Cultivation Category Badge ──────────────────────────────────────────────
class _CultivationBadge extends StatelessWidget {
  final String category;
  const _CultivationBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final String emoji;
    final String label;
    final String subtitle;
    final Color color;

    switch (category) {
      case 'botanical_only':
        emoji   = '🏛️';
        label   = 'Botanical / Research Only';
        subtitle = 'Cannot be home-cultivated. Found only in botanical gardens, forest reserves or scientific programs.';
        color   = const Color(0xFF4A148C);
        break;
      case 'advanced_collector':
        emoji   = '🧪';
        label   = 'Advanced Collector Plant';
        subtitle = 'Requires specialist knowledge and dedicated conditions. Not recommended for beginners.';
        color   = const Color(0xFFBF360C);
        break;
      case 'specialty_garden':
        emoji   = '🌺';
        label   = 'Specialty Garden Plant';
        subtitle = 'Available at specialist nurseries. Needs more care than typical garden plants.';
        color   = const Color(0xFF1565C0);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: color.withOpacity(0.75))),
        ])),
      ]),
    );
  }
}

// ─── Confidence Badge ─────────────────────────────────────────────────────────
class _ConfidenceBadge extends StatelessWidget {
  final int confidence;
  final Map<String, dynamic> plantRaw;
  const _ConfidenceBadge({required this.confidence, required this.plantRaw});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final String emoji;
    if (confidence >= 85) {
      color = const Color(0xFF1B5E20); label = 'High confidence identification'; emoji = '🎯';
    } else if (confidence >= 60) {
      color = const Color(0xFFE65100); label = 'Moderate confidence — verify with flowers/fruit'; emoji = '⚠️';
    } else {
      color = const Color(0xFFB71C1C); label = 'Low confidence — similar species exist'; emoji = '❓';
    }

    // Extract low_confidence fields from raw JSON
    final identRaw = (plantRaw['identification'] as Map?)?.cast<String, dynamic>() ?? {};
    final notice = (identRaw['low_confidence_notice'] as String? ?? '').trim();
    final possibleMatches = (plantRaw['possible_matches'] as List?)?.cast<dynamic>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 13, color: color)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '$confidence%',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        // Low-confidence notice
        if (notice.isNotEmpty) ...[  
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.5)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(notice,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.4))),
            ]),
          ),
        ],
        // Possible matches
        if (possibleMatches.isNotEmpty && confidence < 85) ...[  
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔍 Possible Matches',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF37474F))),
                const SizedBox(height: 8),
                ...possibleMatches.take(4).map((m) {
                  final match = (m as Map?)?.cast<String, dynamic>() ?? {};
                  final pName = match['plant_name'] as String? ?? '—';
                  final pSci  = match['scientific_name'] as String? ?? '';
                  final pConf = match['confidence'];
                  final pNote = match['distinguishing_note'] as String? ?? '';
                  final confInt = pConf is int ? pConf
                      : int.tryParse(pConf?.toString() ?? '') ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 36, height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text('$confInt%',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32))),
                        ),
                      ),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (pSci.isNotEmpty)
                            Text(pSci, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                          if (pNote.isNotEmpty)
                            Text(pNote, style: const TextStyle(fontSize: 11, color: Color(0xFF5D4037), height: 1.3)),
                        ],
                      )),
                    ]),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Evidence Used + Improve Accuracy Banner ─────────────────────────────────
class _EvidenceAndImproveBanner extends StatelessWidget {
  final Map<String, dynamic> plantRaw;
  final int confidence;
  const _EvidenceAndImproveBanner({required this.plantRaw, required this.confidence});

  static const Map<String, String> _typeLabel = {
    'whole_plant': 'Whole Plant',
    'flower': 'Flower/Fruit',
    'fruit': 'Flower/Fruit',
    'leaf_stem': 'Leaf & Stem',
    'leaf': 'Leaf',
    'stem': 'Stem',
  };
  static const Map<String, IconData> _typeIcon = {
    'whole_plant': Icons.yard,
    'flower': Icons.local_florist,
    'fruit': Icons.local_florist,
    'leaf_stem': Icons.eco,
    'leaf': Icons.eco,
    'stem': Icons.linear_scale,
  };
  static const Map<String, Color> _typeColor = {
    'whole_plant': Color(0xFF2E7D32),
    'flower': Color(0xFFE91E63),
    'fruit': Color(0xFFE91E63),
    'leaf_stem': Color(0xFF00796B),
    'leaf': Color(0xFF2E7D32),
    'stem': Color(0xFF6D4C41),
  };

  @override
  Widget build(BuildContext context) {
    final evidence = plantRaw['_evidence'] as Map<String, dynamic>?;
    final photos = (evidence?['photos'] as List?)?.cast<String>() ?? [];
    final isMulti = photos.length > 1;

    // What types are missing that would improve accuracy?
    final bool hasFlower = photos.any((t) => t == 'flower' || t == 'fruit');
    final bool hasLeafStem = photos.any((t) => t == 'leaf_stem' || t == 'leaf' || t == 'stem');
    final List<String> suggestions = [];
    if (confidence <= 70) {
      if (!hasFlower) suggestions.add('Flower/Fruit close-up');
      if (!hasLeafStem) suggestions.add('Leaf & Stem close-up');
    }

    if (!isMulti && suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Evidence chips (only shown when multi-photo was used)
        if (isMulti) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(children: [
              const Icon(Icons.photo_library, size: 15, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              const Text('Evidence used: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 4, children: photos.map((t) {
                  final label = _typeLabel[t] ?? t;
                  final icon = _typeIcon[t] ?? Icons.image;
                  final color = _typeColor[t] ?? const Color(0xFF2E7D32);
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 12, color: color),
                    const SizedBox(width: 3),
                    Text(label,
                        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                  ]);
                }).toList()),
              ),
            ]),
          ),
          const SizedBox(height: 6),
        ],

        // Improve accuracy CTA (only when low confidence and missing photos)
        if (suggestions.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('📸', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Improve Accuracy',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                          color: Color(0xFF5D4037))),
                  const SizedBox(height: 2),
                  Text(
                    'Re-scan with a ${suggestions.join(' and ')} for higher confidence.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.4),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

// ─── Pet Safety Badge ─────────────────────────────────────────────────────────
class _PetSafetyBadge extends StatelessWidget {
  final PlantHealth health;
  const _PetSafetyBadge({required this.health});

  /// Normalise old source values ("database","ai") to new constants.
  static String _normaliseSource(String src) {
    switch (src) {
      case 'database':         return 'VERIFIED_DATABASE';
      case 'ai':               return 'AI_RESEARCH';
      case 'VERIFIED_DATABASE':
      case 'AI_RESEARCH':
      case 'unknown':          return src;
      default:                 return 'unknown';
    }
  }

  static String _confidenceLabel(int conf) {
    if (conf >= 90) return 'High';
    if (conf >= 70) return 'Medium';
    if (conf > 0)   return 'Low';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final status = health.petSafetyStatus; // safe | caution | toxic | unknown
    final source = _normaliseSource(health.petSafetySource);
    final confidence = health.petSafetyConfidence;

    final String emoji;
    final String title;
    final Color bgColor;
    final Color borderColor;
    final Color textColor;

    final bool isVerified = source == 'VERIFIED_DATABASE';

    switch (status) {
      case 'safe':
        emoji       = '🟢';
        title       = isVerified ? 'Pet Safe · Verified' : 'Likely Pet Safe';
        bgColor     = const Color(0xFFE8F5E9);
        borderColor = const Color(0xFF81C784);
        textColor   = const Color(0xFF1B5E20);
        break;
      case 'caution':
        emoji       = '🟡';
        title       = 'Use Caution Around Pets';
        bgColor     = const Color(0xFFFFFDE7);
        borderColor = const Color(0xFFFFD54F);
        textColor   = const Color(0xFFE65100);
        break;
      case 'toxic':
        emoji       = '🔴';
        title       = isVerified ? 'Toxic to Pets · Verified' : 'Toxic to Pets';
        bgColor     = const Color(0xFFFFEBEE);
        borderColor = const Color(0xFFEF9A9A);
        textColor   = const Color(0xFFB71C1C);
        break;
      default: // unknown
        emoji       = '⚪';
        title       = 'Pet Safety Unknown';
        bgColor     = const Color(0xFFF5F5F5);
        borderColor = const Color(0xFFBDBDBD);
        textColor   = const Color(0xFF616161);
    }

    // Status-aware detail text
    String? affectedLine;
    String? detailText;
    switch (status) {
      case 'unknown':
        detailText   = 'Pet Safety Unknown – research recommended.';
        affectedLine = null;
        break;
      case 'safe':
        detailText   = health.symptoms.isNotEmpty
            ? health.symptoms
            : 'Generally considered safe for pets.';
        affectedLine = null;
        break;
      default: // caution | toxic
        affectedLine = health.affectedAnimals.isNotEmpty ? health.affectedAnimals : null;
        detailText   = health.symptoms.isNotEmpty
            ? health.symptoms
            : (health.toxicityNotes.isNotEmpty ? health.toxicityNotes : null);
    }

    // ── Source badge  ──────────────────────────────────────────────────────
    final Widget sourceBadge;
    switch (source) {
      case 'VERIFIED_DATABASE':
        sourceBadge = _SourceBadge(
          icon: Icons.verified_outlined,
          label: 'Verified Database',
          color: const Color(0xFF1B5E20),
        );
        break;
      case 'AI_RESEARCH':
        final confLabel = _confidenceLabel(confidence);
        sourceBadge = _SourceBadge(
          icon: Icons.auto_awesome_outlined,
          label: 'AI Research${confLabel.isNotEmpty ? " · $confLabel Confidence" : ""}',
          color: const Color(0xFFE65100),
        );
        break;
      default:
        sourceBadge = _SourceBadge(
          icon: Icons.help_outline,
          label: 'Unknown Source',
          color: const Color(0xFF616161),
        );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor),
                ),
                if (affectedLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Affects: $affectedLine',
                      style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      detailText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(status == 'unknown' ? 0.75 : 0.85),
                        fontStyle: status == 'unknown' ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                const SizedBox(height: 7),
                sourceBadge,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill showing the data source with icon.
class _SourceBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SourceBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Difficulty Stars ─────────────────────────────────────────────────────────
class _DifficultyRow extends StatelessWidget {
  final String difficulty;
  const _DifficultyRow({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final d = difficulty.toLowerCase();
    final int stars;
    final Color color;
    final String label;
    if (d == 'easy' || d == 'very easy') {
      stars = 5; color = Colors.green; label = 'Beginner Friendly';
    } else if (d == 'medium' || d == 'moderate') {
      stars = 3; color = Colors.orange; label = 'Some Experience Needed';
    } else if (d == 'hard' || d == 'difficult') {
      stars = 2; color = Colors.red; label = 'Experienced Gardeners';
    } else if (d == 'very hard' || d == 'expert') {
      stars = 1; color = Colors.red; label = 'Expert Only';
    } else {
      stars = 3; color = Colors.grey; label = difficulty;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('🌱', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const SizedBox(
            width: 110,
            child: Text('Difficulty', style: TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Row(
            children: List.generate(5, (i) => Icon(
              i < stars ? Icons.star : Icons.star_border,
              size: 18,
              color: color,
            )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Malaysia Watering Guide (Care Tab) ───────────────────────────────────────
class _MalaysiaWateringGuide extends StatelessWidget {
  final String watering;
  final Map<String, dynamic>? wateringRec;
  const _MalaysiaWateringGuide({required this.watering, this.wateringRec});

  @override
  Widget build(BuildContext context) {
    final rec = wateringRec ?? _WateringVisual._parseAiText(watering);
    final potRange    = rec?['pot_range']     as String?;
    final gndRange    = rec?['ground_range']  as String?;
    final fingerTest  = wateringRec?['finger_test']   as String?;
    final hotSeason   = wateringRec?['hot_season']    as String?;
    final rainySeason = wateringRec?['rainy_season']  as String?;
    final potVsGround = wateringRec?['pot_vs_ground'] as String?;
    final overList    = (wateringRec?['overwatering']  as List<dynamic>?)?.cast<String>() ?? [];
    final underList   = (wateringRec?['underwatering'] as List<dynamic>?)?.cast<String>() ?? [];

    // Generic fallbacks for old cached entries that lack the rich fields
    final fingerFallback = 'Insert finger 2–3 cm into the soil. Water only when the top feels dry.';
    final hotFallback    = 'Water at the more frequent end of the range. Check soil every 1–2 days.';
    final rainyFallback  = 'Reduce frequency. Always check soil moisture before watering.';

    Widget _divider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: Color(0xFFA5D6A7)),
    );

    Widget _sectionTitle(String icon, String title, Color color) => Text(
      '$icon  $title',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    );

    Widget _bodyText(String text) => Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF4E342E), height: 1.5),
    );

    Widget _bulletList(List<String> items, Color dotColor) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 6),
            child: Container(width: 5, height: 5,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ),
          Expanded(child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFF4E342E), height: 1.45))),
        ]),
      )).toList(),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF81C784), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        const Text('🇲🇾  Watering Guide for Malaysia',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B5E20))),

        // ── Schedule ─────────────────────────────────────────────────────────
        if (potRange != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('🪴', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text('Pot:    every $potRange days',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
          ]),
          if (gndRange != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Text('🌳', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text('Ground: every $gndRange days',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
            ]),
          ],
        ],

        _divider(),

        // ── Finger Test ──────────────────────────────────────────────────────
        _sectionTitle('🔍', 'How to Check Soil', const Color(0xFF00695C)),
        const SizedBox(height: 4),
        _bodyText(fingerTest ?? fingerFallback),

        _divider(),

        // ── Seasonal Adjustments ─────────────────────────────────────────────
        _sectionTitle('☀️', 'Hot / Dry Season  (Mar – Sep)', const Color(0xFFE65100)),
        const SizedBox(height: 4),
        _bodyText(hotSeason ?? hotFallback),
        const SizedBox(height: 10),
        _sectionTitle('🌧️', 'Rainy / Monsoon Season  (Oct – Feb)', const Color(0xFF1565C0)),
        const SizedBox(height: 4),
        _bodyText(rainySeason ?? rainyFallback),

        _divider(),

        // ── Warning Signs ─────────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Overwatering
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('💧', 'Too Much Water', const Color(0xFF1565C0)),
            const SizedBox(height: 4),
            if (overList.isNotEmpty)
              _bulletList(overList, const Color(0xFF1565C0))
            else
              _bodyText('• Yellow leaves\n• Wilting despite wet soil\n• Root rot smell'),
          ])),
          const SizedBox(width: 12),
          // Underwatering
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('🏜️', 'Too Little Water', const Color(0xFFE65100)),
            const SizedBox(height: 4),
            if (underList.isNotEmpty)
              _bulletList(underList, const Color(0xFFE65100))
            else
              _bodyText('• Wilting or drooping\n• Brown crispy edges\n• Bone-dry soil'),
          ])),
        ]),

        // ── Pot vs Ground ────────────────────────────────────────────────────
        if (potVsGround != null && potVsGround.isNotEmpty) ...[
          _divider(),
          _sectionTitle('🪴', 'Pot vs In-Ground', const Color(0xFF1B5E20)),
          const SizedBox(height: 4),
          _bodyText(potVsGround),
        ],
      ]),
    );
  }
}

// ─── Watering Visual ──────────────────────────────────────────────────────────
class _WateringVisual extends StatelessWidget {
  final String watering;
  final Map<String, dynamic>? wateringRec; // from watering_recommended field
  const _WateringVisual({required this.watering, this.wateringRec});

  // Build a structured rec from AI text for old history entries that lack watering_recommended.
  static Map<String, dynamic>? _parseAiText(String w) {
    final lw = w.toLowerCase();
    String potRange, gndRange;
    if (lw.contains('daily') || lw.contains('every day') || lw.contains('once a day')) {
      potRange = '1'; gndRange = '1-2';
    } else if (lw.contains('twice') || lw.contains('2-3 day') || lw.contains('every 2')) {
      potRange = '2-3'; gndRange = '3-4';
    } else if (lw.contains('every 3') || lw.contains('3-4 day') || lw.contains('3 day')) {
      potRange = '3-4'; gndRange = '4-5';
    } else if (lw.contains('week') || lw.contains('7 day') || lw.contains('once a week')) {
      potRange = '5-7'; gndRange = '7-10';
    } else if (lw.contains('2 week') || lw.contains('fortnight') || lw.contains('14 day')) {
      potRange = '10-14'; gndRange = '14-21';
    } else if (lw.contains('month') || lw.contains('30 day')) {
      potRange = '21-30'; gndRange = '30-45';
    } else {
      return null; // cannot parse — show raw AI text
    }
    return {
      'pot_range': potRange,
      'ground_range': gndRange,
      'display': 'Every $potRange days (pot) · $gndRange days (ground)',
      'source': 'ai_text_parsed',
    };
  }

  Color _freqColor(String w) {
    final lw = w.toLowerCase();
    if (lw.contains('daily') || lw.contains('every day')) return const Color(0xFF1565C0);
    if (lw.contains('twice') || lw.contains('2-3')) return const Color(0xFF0277BD);
    if (lw.contains('week')) return const Color(0xFF00838F);
    if (lw.contains('fortnight') || lw.contains('2 week')) return const Color(0xFF2E7D32);
    return const Color(0xFF558B2F);
  }

  String _freqEmoji(String rec) {
    final lw = rec.toLowerCase();
    if (lw.contains('1') || lw.contains('daily')) return '💧💧💧';
    if (lw.contains('2') || lw.contains('3')) return '💧💧';
    return '💧';
  }

  @override
  Widget build(BuildContext context) {
    if (watering.isEmpty) return const SizedBox.shrink();
    // Use backend rec if available; otherwise try to parse AI text
    final rec = wateringRec ?? _parseAiText(watering);
    final color = _freqColor(watering);
    final potRange = rec?['pot_range'] as String?;
    final gndRange = rec?['ground_range'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_freqEmoji(potRange ?? watering), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('💧 Watering Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              if (potRange != null) ...[
                Text('🪴 Pot: every $potRange days', style: TextStyle(fontSize: 13, color: color)),
                if (gndRange != null)
                  Text('🌳 Ground: every $gndRange days', style: TextStyle(fontSize: 13, color: color)),
              ] else
                Text(watering, style: TextStyle(fontSize: 13, color: color)),
            ])),
          ]),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;
  final Color bgColor;
  final String emptyMessage;
  const _BulletCard({
    required this.title,
    required this.items,
    required this.color,
    required this.bgColor,
    this.emptyMessage = 'No information available',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              emptyMessage,
              style: TextStyle(color: color.withOpacity(0.6), fontSize: 13, fontStyle: FontStyle.italic),
            )
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(item, style: TextStyle(color: color, fontSize: 13))),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  final String title;
  final String text;
  const _TextCard({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
            const Divider(height: 16),
            Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

// ─── AI Summary Card ──────────────────────────────────────────────────────────
class _AISummaryCard extends StatelessWidget {
  final Plant plant;
  const _AISummaryCard({required this.plant});

  @override
  Widget build(BuildContext context) {
    final m = plant.maintenance;
    final s = plant.suitability;
    final g = plant.growing;
    final pd = plant.purchaseDecision;

    final List<String> bestFor = [];
    final diff = m.difficulty.toLowerCase();
    if (diff.contains('easy') || diff.contains('beginner')) bestFor.add('Beginners');
    if (diff.contains('very easy')) bestFor.add('Low-Effort Garden');
    final climate = s.climate.toLowerCase();
    if (climate.contains('tropical')) bestFor.add('Tropical Gardens');
    if (climate.contains('temperate')) bestFor.add('Temperate Climate');
    if (climate.contains('mediterranean')) bestFor.add('Mediterranean Garden');
    final potOrGround = g.potOrGround.toLowerCase();
    if (potOrGround.contains('pot') || potOrGround.contains('both')) bestFor.add('Container Growing');
    if (potOrGround.contains('ground') || potOrGround.contains('both')) bestFor.add('Garden Beds');
    final sunlight = s.sunlight.toLowerCase();
    if (sunlight.contains('shade') || sunlight.contains('indirect') || sunlight.contains('partial')) {
      bestFor.add('Low-Light Spaces');
    }
    if (sunlight.contains('full sun')) bestFor.add('Sunny Spots');

    final warnings = pd.challenges.take(2).toList();

    if (bestFor.isEmpty && warnings.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🤖', style: TextStyle(fontSize: 14)),
            SizedBox(width: 6),
            Text('AI Quick Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          ]),
          if (bestFor.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Best For', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: bestFor.map((label) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Watch Out For', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            ...warnings.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('⚠️ ', style: TextStyle(fontSize: 12)),
                Expanded(child: Text(w, style: const TextStyle(fontSize: 12, color: Color(0xFF795548)))),
              ]),
            )),
          ],
        ],
      ),
    );
  }
}

// ─── Plant Type Pill (header badge) ──────────────────────────────────────────
class _PlantTypePill extends StatelessWidget {
  final String plantType;
  const _PlantTypePill({required this.plantType});

  static String _emoji(String t) {
    final l = t.toLowerCase();
    if (l.contains('flower') || l.contains('bloom') || l.contains('orchid')) return '🌸';
    if (l.contains('fruit') || l.contains('citrus') || l.contains('mango')) return '🍋';
    if (l.contains('palm')) return '🌴';
    if (l.contains('tree')) return '🌳';
    if (l.contains('succulent') || l.contains('cactus')) return '🌵';
    if (l.contains('herb') || l.contains('spice')) return '🌿';
    if (l.contains('aquatic') || l.contains('water')) return '💧';
    if (l.contains('shrub') || l.contains('bush')) return '🌾';
    if (l.contains('vine') || l.contains('climber')) return '🌼';
    return '🌱';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white38),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_emoji(plantType), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(plantType,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

