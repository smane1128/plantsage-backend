import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'result_screen.dart';
import 'disease_result_screen.dart';
import 'compare_screen.dart';
import 'calendar_screen.dart';
import 'disease_history_screen.dart';
import 'garden_profile_screen.dart';
import 'my_garden_screen.dart';
import 'wishlist_screen.dart';
import 'settings_screen.dart';
import '../services/api_service.dart';
import '../models/plant.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  List<dynamic> _history = [];
  bool _selectMode = false;
  Set<int> _selectedIds = {};
  int _dueWateringCount = 0;
  bool _waterBannerDismissed = false;
  bool _isOffline = false;
  String _searchQuery = '';
  String _sortBy = 'date'; // 'date' | 'score_desc' | 'score_asc' | 'name'
  Map<String, dynamic> _stats = {
    'garden_count': 0, 'wishlist_count': 0, 'scan_count': 0,
    'avg_score': 0, 'top_pick': 0, 'good': 0, 'careful': 0, 'risky': 0,
    'healthy_count': 0, 'recovering_count': 0, 'sick_count': 0,
    'needs_water': 0, 'upcoming_water': 0,
    'last_scan': null, 'last_disease': null,
    'garden_health_score': 100,
    'tasks_today': <dynamic>[],
    'top_plant': null,
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadStats();
    _loadDueWatering();
  }

  Future<void> _loadDueWatering() async {
    final due = await ApiService.getDueForWatering();
    if (mounted) setState(() {
      _dueWateringCount = due.length;
      if (due.isNotEmpty) _waterBannerDismissed = false;
    });
  }

  Future<void> _loadStats() async {
    final stats = await ApiService.getDashboardStats();
    if (mounted) setState(() => _stats = {..._stats, ...stats});
  }

  void _enterSelectMode() => setState(() { _selectMode = true; _selectedIds = {}; });
  void _exitSelectMode() => setState(() { _selectMode = false; _selectedIds = {}; });

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allIds = _history.map((s) => s['id'] as int).toSet();
      if (_selectedIds.length == allIds.length) {
        _selectedIds = {};
      } else {
        _selectedIds = allIds;
      }
    });
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('402') || msg.contains('quota') || msg.contains('insufficient_quota')) {
      return 'AI service quota exceeded. Please try again later.';
    }
    if (msg.contains('401') || msg.contains('Unauthorized') || msg.contains('API key') || msg.contains('api_key')) {
      return 'Authentication error. Please check your API key.';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused') ||
        msg.contains('Failed host lookup')) {
      return 'Cannot connect to server. Please ensure the backend is running.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (msg.contains('500') || msg.contains('Server error') || msg.contains('server error')) {
      return 'Server error. Please try again.';
    }
    if (msg.contains('No image') || msg.contains('no plant')) {
      return 'Could not detect a plant in the image. Please try a clearer photo.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Selected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove $count scan${count > 1 ? 's' : ''} from Scan History?'),
            const SizedBox(height: 10),
            const Text(
              '✅ Plants already added to My Garden or Wishlist will not be affected.',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final id in _selectedIds) {
        await ApiService.deleteHistory(id);
      }
      _exitSelectMode();
      await _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final history = await ApiService.getHistory();
    if (mounted) setState(() {
      _history = history;
      _isOffline = ApiService.isOffline;
    });
  }

  List<dynamic> get _filteredHistory {
    var list = _history.toList();
    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) {
        final name = (s['plant_name'] as String? ?? '').toLowerCase();
        final sci  = (s['scientific_name'] as String? ?? '').toLowerCase();
        return name.contains(q) || sci.contains(q);
      }).toList();
    }
    // Sort
    switch (_sortBy) {
      case 'score_desc':
        list.sort((a, b) => ((b['gardenability_score'] ?? b['suitability_score']) as int? ?? 0)
            .compareTo((a['gardenability_score'] ?? a['suitability_score']) as int? ?? 0));
        break;
      case 'score_asc':
        list.sort((a, b) => ((a['gardenability_score'] ?? a['suitability_score']) as int? ?? 0)
            .compareTo((b['gardenability_score'] ?? b['suitability_score']) as int? ?? 0));
        break;
      case 'name':
        list.sort((a, b) => (a['plant_name'] as String? ?? '')
            .compareTo(b['plant_name'] as String? ?? ''));
        break;
      default: // 'date' — keep server order (newest first)
        break;
    }
    return list;
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;

    // Copy image to permanent app storage so history can display it later
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'myplants_images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final ext = p.extension(picked.path).isNotEmpty ? p.extension(picked.path) : '.jpg';
    final savedPath = p.join(imagesDir.path, '${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(picked.path).copy(savedPath);

    if (!mounted) return;

    // Show multi-photo sheet — user can add more photos or identify immediately
    final additionalImages = await _showMultiPhotoSheet(File(picked.path));
    if (!mounted) return;
    if (additionalImages == null) return; // user dismissed

    setState(() => _isLoading = true);

    try {
      final (plant, raw) = await ApiService.identifyPlant(
        File(picked.path),
        imagePath: savedPath,
        additionalImages: additionalImages,
      );
      if (!mounted) return;

      // Show banner if this plant was already in history
      final meta = raw['_meta'] as Map<String, dynamic>?;
      if (meta != null && meta['already_exists'] == true) {
        final count = meta['scan_count'] as int? ?? 2;
        final cached = meta['cached'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cached
                ? '${plant.identification.plantName} already scanned — showing saved report ($count scans)'
                : '${plant.identification.plantName} already in your collection — scanned $count time${count == 1 ? '' : 's'}',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(plant: plant, plantRaw: raw, imagePath: savedPath),
        ),
      );
      _loadHistory();
      _loadStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shows the multi-photo collection sheet after the primary photo is picked.
  /// Returns a list of additional image maps (may be empty), or null if dismissed.
  Future<List<Map<String, String>>?> _showMultiPhotoSheet(File primaryFile) async {
    return showModalBottomSheet<List<Map<String, String>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MultiPhotoSheet(primaryFile: primaryFile, picker: _picker),
    );
  }

  Future<void> _diagnoseImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const Text('Disease Check',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Take a close-up of affected leaves or stems',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.camera_alt, color: Color(0xFFB71C1C))),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.photo_library, color: Color(0xFFB71C1C))),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? picked =
        await _picker.pickImage(source: source, imageQuality: 90, maxWidth: 1024);
    if (picked == null) return;

    setState(() => _isLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(appDir.path, 'myplants_images'));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
      final ext =
          p.extension(picked.path).isNotEmpty ? p.extension(picked.path) : '.jpg';
      final savedPath = p.join(
          imagesDir.path, '${DateTime.now().millisecondsSinceEpoch}_disease$ext');
      await File(picked.path).copy(savedPath);

      final result = await ApiService.diagnoseDisease(File(picked.path));
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DiseaseResultScreen(result: result, imagePath: savedPath),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showComparePicker() {
    final List<int> selected = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Select 2 plants to compare',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${selected.length}/2 selected',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (_, i) {
                  final item = _history[i];
                  final id = item['id'] as int;
                  final isSelected = selected.contains(id);
                  final disabled = !isSelected && selected.length >= 2;
                  final imgPath = item['image_path'] as String?;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imgPath != null
                          ? Image.file(File(imgPath),
                              width: 48, height: 48, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  width: 48, height: 48,
                                  color: const Color(0xFFE8F5E9),
                                  child: const Center(child: Text('🌿'))))
                          : Container(
                              width: 48, height: 48,
                              color: const Color(0xFFE8F5E9),
                              child: const Center(child: Text('🌿'))),
                    ),
                    title: Text(item['plant_name']?.toString() ?? '—',
                        style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: disabled ? Colors.grey : Colors.black87)),
                    subtitle: Text(item['scientific_name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 11)),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                        : Icon(Icons.radio_button_unchecked,
                            color: disabled ? Colors.grey.shade300 : Colors.grey),
                    onTap: disabled
                        ? null
                        : () {
                            setInner(() {
                              if (isSelected) {
                                selected.remove(id);
                              } else {
                                selected.add(id);
                              }
                            });
                            if (selected.length == 2) {
                              Navigator.pop(ctx);
                              _runCompare(
                                _history.firstWhere((h) => h['id'] == selected[0]),
                                _history.firstWhere((h) => h['id'] == selected[1]),
                              );
                            }
                          },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _runCompare(Map<dynamic, dynamic> p1, Map<dynamic, dynamic> p2) {
    try {
      final raw1 = p1['details'];
      final raw2 = p2['details'];
      final d1 = raw1 is String ? (jsonDecode(raw1) as Map<String, dynamic>) : (raw1 as Map<String, dynamic>? ?? <String, dynamic>{});
      final d2 = raw2 is String ? (jsonDecode(raw2) as Map<String, dynamic>) : (raw2 as Map<String, dynamic>? ?? <String, dynamic>{});
      final compareData = <String, dynamic>{
        'plant1': <String, dynamic>{
          'id': p1['id'],
          'plant_name': p1['plant_name'],
          'scientific_name': p1['scientific_name'],
          'recommendation': p1['recommendation'] ?? d1['purchase_decision']?['recommendation'] ?? 'See report',
          'suitability_score': p1['gardenability_score'] ?? p1['suitability_score'] ?? 0,
          'gardenability_score': p1['gardenability_score'] ?? p1['suitability_score'] ?? 0,
          'image_path': p1['image_path'],
          'details': d1,
        },
        'plant2': <String, dynamic>{
          'id': p2['id'],
          'plant_name': p2['plant_name'],
          'scientific_name': p2['scientific_name'],
          'recommendation': p2['recommendation'] ?? d2['purchase_decision']?['recommendation'] ?? 'See report',
          'suitability_score': p2['gardenability_score'] ?? p2['suitability_score'] ?? 0,
          'gardenability_score': p2['gardenability_score'] ?? p2['suitability_score'] ?? 0,
          'image_path': p2['image_path'],
          'details': d2,
        },
      };
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => CompareScreen(preloadedData: compareData)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compare error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌿', style: TextStyle(fontSize: 20)),
            SizedBox(width: 6),
            Text('PlantSage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        leading: null,
        actions: [
          // Always-visible: My Garden (with badge) + refresh
          IconButton(
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.local_florist, color: Colors.white),
              if (_dueWateringCount > 0)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(color: Color(0xFF1565C0), shape: BoxShape.circle),
                    child: Center(
                      child: Text('$_dueWateringCount',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ]),
            tooltip: _dueWateringCount > 0
                ? '$_dueWateringCount plant${_dueWateringCount == 1 ? '' : 's'} need watering!'
                : 'My Garden Collection',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyGardenScreen()),
            ).then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () {
              _loadHistory();
              _loadStats();
              _loadDueWatering();
            },
          ),
          // Overflow menu for the rest
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'calendar':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
                case 'wishlist':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen()))
                      .then((_) { _loadStats(); _loadHistory(); });
                case 'disease':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DiseaseHistoryScreen()));
                case 'profile':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GardenProfileScreen()));
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'calendar', child: Row(children: [Icon(Icons.calendar_month_outlined, color: Color(0xFF2E7D32)), SizedBox(width: 12), Text('Watering Calendar')])),
              PopupMenuItem(value: 'wishlist', child: Row(children: [Icon(Icons.favorite_border, color: Color(0xFFAD1457)), SizedBox(width: 12), Text('Wishlist')])),
              PopupMenuItem(value: 'disease', child: Row(children: [Icon(Icons.bug_report_outlined, color: Color(0xFFE65100)), SizedBox(width: 12), Text('Disease History')])),
              PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.yard_outlined, color: Color(0xFF2E7D32)), SizedBox(width: 12), Text('Garden Profile')])),
              PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined), SizedBox(width: 12), Text('Settings')])),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF2E7D32)),
                  SizedBox(height: 16),
                  Text('Identifying plant...', style: TextStyle(fontSize: 16, color: Color(0xFF2E7D32))),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // ── Offline banner ──
                  if (_isOffline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFB300), width: 1),
                      ),
                      child: Row(children: [
                        const Icon(Icons.wifi_off, color: Color(0xFFFF8F00), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Backend unreachable — showing cached data',
                              style: TextStyle(fontSize: 12, color: Color(0xFFE65100))),
                        ),
                        TextButton(
                          onPressed: () { _loadHistory(); _loadStats(); _loadDueWatering(); },
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE65100),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Retry', style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ),
                  // ── Season reminder banner ──
                  _SeasonBanner(),
                  // ── Watering reminder banner ──
                  if (_dueWateringCount > 0 && !_waterBannerDismissed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1565C0), width: 1),
                      ),
                      child: Row(children: [
                        const Icon(Icons.water_drop, color: Color(0xFF1565C0), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '💧 $_dueWateringCount plant${_dueWateringCount == 1 ? '' : 's'} need watering today!',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MyGardenScreen()))
                              .then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF1565C0),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('View', style: TextStyle(fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                          onPressed: () => setState(() => _waterBannerDismissed = true),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                    ),
                  // ── Welcome header ──
                  _WelcomeHeader(gardenCount: _stats['garden_count'] as int? ?? 0),
                  const SizedBox(height: 16),
                  // ── Quick Actions grid ──
                  _QuickActionsGrid(
                    onCamera: () => _pickImage(ImageSource.camera),
                    onGallery: () => _pickImage(ImageSource.gallery),
                    onDiagnose: _diagnoseImage,
                    onGarden: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MyGardenScreen()))
                        .then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
                    onCalendar: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CalendarScreen())),
                    onWishlist: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const WishlistScreen()))
                        .then((_) { _loadStats(); _loadHistory(); }),
                  ),
                  const SizedBox(height: 16),
                  // ── Today's Tasks ──
                  _TodaysTasksCard(
                    stats: _stats,
                    onViewGarden: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MyGardenScreen()))
                        .then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
                  ),
                  const SizedBox(height: 12),
                  // ── Dashboard stats card ──
                  _DashboardCard(
                    stats: _stats,
                    onGardenTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MyGardenScreen()))
                        .then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
                    onWishlistTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const WishlistScreen()))
                        .then((_) { _loadStats(); _loadHistory(); }),
                    onScansTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const _ScanHistoryScreen()))
                        .then((_) { _loadStats(); _loadHistory(); }),
                  ),
                  const SizedBox(height: 12),
                  // ── Top Plant ──
                  if ((_stats['top_plant'] as Map<String, dynamic>?) != null)
                    _TopPlantCard(
                      plant: Map<String, dynamic>.from(
                          (_stats['top_plant'] as Map).cast<String, dynamic>()),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MyGardenScreen()))
                          .then((_) { _loadStats(); _loadHistory(); _loadDueWatering(); }),
                    ),
                  if ((_stats['top_plant'] as Map<String, dynamic>?) != null)
                    const SizedBox(height: 12),
                  _RecentActivityCard(stats: _stats),
                  const SizedBox(height: 20),
                  if (_history.isNotEmpty) ...[
                    // ── Header row ──
                    if (_selectMode) ...[
                      // Select mode: title + actions on separate rows
                      Row(children: [
                        const Text(
                          'Recent Scans',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _exitSelectMode,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Checkbox(
                          value: _selectedIds.length == _history.length,
                          tristate: true,
                          activeColor: const Color(0xFF2E7D32),
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => _toggleSelectAll(),
                        ),
                        const Text('All', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                          icon: const Icon(Icons.delete, size: 16),
                          label: Text('Delete (${_selectedIds.length})',
                              style: const TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        ),
                      ]),
                    ] else ...[
                      // Normal mode: single row with title + icon buttons
                      Row(children: [
                        const Text(
                          'Recent Scans',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                        const Spacer(),
                        // Compare
                        IconButton(
                          icon: const Icon(Icons.compare_arrows, color: Color(0xFF2E7D32)),
                          tooltip: 'Compare 2 Plants',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _history.length >= 2 ? _showComparePicker : null,
                        ),
                        // Select
                        IconButton(
                          icon: const Icon(Icons.checklist, color: Color(0xFF2E7D32)),
                          tooltip: 'Select',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _enterSelectMode,
                        ),
                        // Clear all
                        IconButton(
                          icon: const Icon(Icons.delete_sweep, color: Colors.red),
                          tooltip: 'Clear All History',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Clear All History'),
                                content: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Remove all scan history?'),
                                    SizedBox(height: 10),
                                    Text(
                                      '✅ Plants in My Garden and Wishlist will not be affected.',
                                      style: TextStyle(fontSize: 12, color: Colors.green),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ApiService.clearAllHistory();
                              await _loadHistory();
                            }
                          },
                        ),
                      ]),
                    ],
                    // ── Search bar ──
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search plants...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF2E7D32)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    // ── Sort chips ──
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _SortChip(label: 'Newest', value: 'date', current: _sortBy, onTap: (v) => setState(() => _sortBy = v)),
                        _SortChip(label: 'Score ▼', value: 'score_desc', current: _sortBy, onTap: (v) => setState(() => _sortBy = v)),
                        _SortChip(label: 'Score ▲', value: 'score_asc', current: _sortBy, onTap: (v) => setState(() => _sortBy = v)),
                        _SortChip(label: 'A–Z', value: 'name', current: _sortBy, onTap: (v) => setState(() => _sortBy = v)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    if (_filteredHistory.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No plants match "$_searchQuery"',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ..._filteredHistory.map((scan) => _HistoryCard(
                        scan: scan,
                        selectMode: _selectMode,
                        isSelected: _selectedIds.contains(scan['id'] as int),
                        onToggleSelect: () => _toggleSelect(scan['id'] as int),
                        onDelete: () async {
                          await ApiService.deleteHistory(scan['id'] as int);
                          await _loadHistory();
                        },
                      )),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback? onGardenTap;
  final VoidCallback? onWishlistTap;
  final VoidCallback? onScansTap;
  const _DashboardCard({required this.stats, this.onGardenTap, this.onWishlistTap, this.onScansTap});

  @override
  Widget build(BuildContext context) {
    final gardenCount    = stats['garden_count'] as int? ?? 0;
    final wishlistCount  = stats['wishlist_count'] as int? ?? 0;
    final scanCount      = stats['scan_count'] as int? ?? 0;
    final avgScore       = stats['avg_score'] as int? ?? 0;
    final topPick        = stats['top_pick'] as int? ?? 0;
    final good           = stats['good'] as int? ?? 0;
    final careful        = stats['careful'] as int? ?? 0;
    final risky          = stats['risky'] as int? ?? 0;
    final healthyCount    = stats['healthy_count'] as int? ?? 0;
    final recoveringCount = stats['recovering_count'] as int? ?? 0;
    final sickCount       = stats['sick_count'] as int? ?? 0;
    final needsWater      = stats['needs_water'] as int? ?? 0;
    final upcomingWater   = stats['upcoming_water'] as int? ?? 0;
    final healthScore     = stats['garden_health_score'] as int? ?? 100;
    final Color hsColor   = healthScore >= 90 ? const Color(0xFF00E676)
        : healthScore >= 70 ? const Color(0xFFFFD54F) : const Color(0xFFFF5252);
    final String hsLabel  = healthScore >= 90 ? 'Excellent'
        : healthScore >= 70 ? 'Good' : 'Needs Attention';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF1B5E20).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌿 Garden Overview', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hsColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: hsColor.withOpacity(0.5), width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: hsColor, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('$healthScore% $hsLabel',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DashStat(value: '$gardenCount', label: 'In Garden', icon: '🌱', onTap: onGardenTap),
              _DashStat(value: '$wishlistCount', label: 'Wishlist', icon: '❤️', onTap: onWishlistTap),
              _DashStat(value: '$scanCount', label: 'Scans', icon: '📷', onTap: onScansTap),
              _DashStat(value: gardenCount > 0 ? '$avgScore' : '—', label: 'Avg Score', icon: '⭐'),
            ],
          ),
          if (gardenCount > 0) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            // Recommendation breakdown bar
            const Text('Suitability Breakdown', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (topPick > 0) Expanded(flex: topPick, child: Container(height: 8, color: const Color(0xFF00E676))),
                  if (good > 0) Expanded(flex: good, child: Container(height: 8, color: const Color(0xFF69F0AE))),
                  if (careful > 0) Expanded(flex: careful, child: Container(height: 8, color: const Color(0xFFFFD54F))),
                  if (risky > 0) Expanded(flex: risky, child: Container(height: 8, color: const Color(0xFFFF5252))),
                  if (topPick + good + careful + risky == 0) Expanded(child: Container(height: 8, color: Colors.white24)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (topPick > 0) _LegendDot(color: const Color(0xFF00E676), label: '$topPick Top'),
                if (good > 0) _LegendDot(color: const Color(0xFF69F0AE), label: '$good Good'),
                if (careful > 0) _LegendDot(color: const Color(0xFFFFD54F), label: '$careful Careful'),
                if (risky > 0) _LegendDot(color: const Color(0xFFFF5252), label: '$risky Risky'),
              ],
            ),
            // Health status row
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 10),
            const Text('Plant Health Status', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _DashStat2(value: '$healthyCount', label: 'Healthy', dot: const Color(0xFF00E676)),
                _DashStat2(value: '$recoveringCount', label: 'Recovering', dot: const Color(0xFFFFD54F)),
                _DashStat2(value: '$sickCount', label: 'Sick', dot: const Color(0xFFFF5252)),
              ],
            ),
            // Watering row
            const SizedBox(height: 10),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 10),
            const Text('💧 Watering', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _DashStat2(value: '$needsWater', label: 'Need Water', dot: const Color(0xFF64B5F6)),
                _DashStat2(value: '$upcomingWater', label: 'This Week', dot: Colors.white60),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DashStat extends StatelessWidget {
  final String value;
  final String label;
  final String icon;
  final VoidCallback? onTap;
  const _DashStat({required this.value, required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10), textAlign: TextAlign.center),
                if (onTap != null)
                  Container(height: 2, margin: const EdgeInsets.only(top: 2, left: 12, right: 12),
                      decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(1))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashStat2 extends StatelessWidget {
  final String value;
  final String label;
  final Color dot;
  const _DashStat2({required this.value, required this.label, required this.dot});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
          ]),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 24),
      label: Text(label, style: const TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _HistoryThumbnail extends StatelessWidget {
  final String? imagePath;
  const _HistoryThumbnail({this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath != null && File(imagePath!).existsSync()) {
      return GestureDetector(
        onTap: () => _openFullScreen(context, imagePath!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(imagePath!),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(child: Text('🌱', style: TextStyle(fontSize: 24))),
          ),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
      child: const Center(child: Text('🌱', style: TextStyle(fontSize: 24))),
    );
  }
}

void _openFullScreen(BuildContext context, String imagePath) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => _FullScreenImageViewer(imagePath: imagePath)),
  );
}

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

class _HistoryCard extends StatelessWidget {
  final dynamic scan;
  final VoidCallback onDelete;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onToggleSelect;
  const _HistoryCard({
    required this.scan,
    required this.onDelete,
    this.selectMode = false,
    this.isSelected = false,
    required this.onToggleSelect,
  });

  Color _recColor(String? rec) {
    switch ((rec ?? '').toLowerCase()) {
      case 'highly recommended': return const Color(0xFF1B5E20);
      case 'recommended': return const Color(0xFF1565C0);
      case 'consider carefully': return const Color(0xFFE65100);
      case 'not recommended': return const Color(0xFFB71C1C);
      default: return Colors.grey;
    }
  }

  /// Client-side fallback band label matching backend _SCORE_BANDS.
  static String _scoreBandShort(int score) {
    if (score >= 81) return 'Highly Recommended';
    if (score >= 61) return 'Recommended';
    if (score >= 41) return 'Moderate';
    if (score >= 21) return 'Challenging';
    if (score >= 10) return 'Not Recommended';
    return 'Botanical Only';
  }

  @override
  Widget build(BuildContext context) {
    final rec = scan['recommendation'] as String?;
    // Prefer gardenability_score (enforced JSON value) over suitability_score (DB column).
    // Both are identical when the backend is fresh; gardenability_score wins on stale cache.
    final score = scan['gardenability_score'] ?? scan['suitability_score'];

    final card = Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isSelected ? const Color(0xFFE8F5E9) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected ? const BorderSide(color: Color(0xFF2E7D32), width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: selectMode
            ? onToggleSelect
            : () {
                final details = scan['details'];
                if (details == null || details.toString().isEmpty) return;
                try {
                  final raw = jsonDecode(details as String) as Map<String, dynamic>;
                  final plant = Plant.fromJson(raw);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultScreen(
                        plant: plant,
                        plantRaw: raw,
                        imagePath: scan['image_path'] as String?,
                      ),
                    ),
                  );
                } catch (_) {}
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading: checkbox or thumbnail
              if (selectMode)
                Checkbox(
                  value: isSelected,
                  activeColor: const Color(0xFF2E7D32),
                  onChanged: (_) => onToggleSelect(),
                )
              else
                _HistoryThumbnail(imagePath: scan['image_path'] as String?),
              const SizedBox(width: 10),
              // Text area — Expanded so it always fills available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scan['plant_name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scan['scientific_name'] ?? '',
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!selectMode) ...[
                const SizedBox(width: 8),
                // Score badge — constrained so it never squeezes the text
                if (rec != null)
                  Builder(builder: (_) {
                    final bandMap = scan['score_band'];
                    final shortLabel = bandMap is Map
                        ? bandMap['short_label'] as String? ?? ''
                        : (score != null ? _scoreBandShort(score as int) : '');
                    final isBotanical = shortLabel == 'Botanical Only';
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 88),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBotanical ? const Color(0xFF3949AB) : _recColor(rec),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: isBotanical
                            ? const Text(
                                '🔬 Research',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (score != null)
                                    Text(
                                      '$score/100',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  Text(
                                    shortLabel.isNotEmpty ? shortLabel : rec.split(' ').first,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                      ),
                    );
                  }),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF2E7D32)),
                    onSelected: (value) async {
                      final plantName = scan['plant_name'] as String? ?? '';
                      final data = {
                        'plant_name': plantName,
                        'scientific_name': scan['scientific_name'],
                        'recommendation': scan['recommendation'],
                        'suitability_score': scan['gardenability_score'] ?? scan['suitability_score'],
                        'image_path': scan['image_path'],
                      };
                      if (value == 'wishlist') {
                        final err = await ApiService.addToWishlist(data);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(err == null ? '$plantName added to Wishlist ❤️' : err),
                            backgroundColor: err == null ? const Color(0xFFAD1457) : Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } else if (value == 'garden') {
                        DateTime? purchaseDate;
                        String capturedName = '';
                        String capturedLocation = '';
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
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
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
                                    if (picked != null) {
                                      setDlgState(() => purchaseDate = picked);
                                    }
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
                                          ? '${purchaseDate!.day} ${_dlgMonth(purchaseDate!.month)} ${purchaseDate!.year}'
                                          : 'Today (default)',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: purchaseDate != null ? null : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
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
                                    capturedName = nameCtrl.text.trim();
                                    capturedLocation = locationCtrl.text.trim();
                                    Navigator.pop(ctx, true);
                                  },
                                ),
                              ],
                            ),
                          );
                          },
                        );
                        if (confirmed != true || !context.mounted) return;
                        final gardenName = capturedName;
                        final location = capturedLocation;
                        final payload = <String, dynamic>{...data};
                        if (gardenName.isNotEmpty) payload['garden_name'] = gardenName;
                        if (location.isNotEmpty) payload['location'] = location;
                        if (purchaseDate != null) {
                          payload['purchase_date'] =
                              purchaseDate!.toIso8601String().substring(0, 10);
                        }
                        final err = await ApiService.addToMyGarden(payload);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(err == null
                                ? '${gardenName.isNotEmpty ? gardenName : plantName} added to My Garden 🌿'
                                : err),
                            backgroundColor: err == null ? const Color(0xFF2E7D32) : Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'wishlist',
                        child: Row(children: [
                          Icon(Icons.favorite_border, color: Color(0xFFAD1457)),
                          SizedBox(width: 8),
                          Text('Add to Wishlist'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'garden',
                        child: Row(children: [
                          Icon(Icons.local_florist, color: Color(0xFF2E7D32)),
                          SizedBox(width: 8),
                          Text('Add to Garden'),
                        ]),
                      ),
                    ],
                  ),
                ],  // closes if (!selectMode) ...[]
              ],    // closes Row children
            ),      // closes Row
          ),        // closes Padding
        ),          // closes InkWell
    );

    if (selectMode) return card;

    return Dismissible(
      key: ValueKey(scan['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove Scan'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remove "${scan['plant_name']}" from Scan History?'),
                const SizedBox(height: 10),
                const Text(
                  '✅ If this plant is in My Garden or Wishlist, it will remain there.',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        return confirm == true;
      },
      onDismissed: (_) => onDelete(),
      child: card,
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final void Function(String) onTap;
  const _SortChip({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : const Color(0xFF2E7D32))),
        selected: selected,
        onSelected: (_) => onTap(value),
        selectedColor: const Color(0xFF2E7D32),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF2E7D32), width: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Shows a Malaysian season tip banner based on the current month.
class _SeasonBanner extends StatelessWidget {
  static bool _dismissed = false;  // session-level dismiss

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final month = DateTime.now().month;
    final bool isRainy = month == 10 || month == 11 || month == 12 ||
                         month == 1  || month == 2;

    final String seasonName = isRainy ? '🌧 Rainy / Monsoon Season' : '☀️ Hot / Dry Season';
    final List<String> tips = isRainy
        ? [
            'Reduce watering frequency — let rain do the work.',
            'Check for fungal diseases on leaves after wet spells.',
            'Ensure good soil drainage to prevent root rot.',
            'Shelter tender plants from heavy downpours.',
          ]
        : [
            'Water early morning before the heat sets in.',
            'Provide afternoon shade for sensitive plants.',
            'Monitor soil moisture daily — dry soil heats fast.',
            'Mulch around roots to retain moisture.',
          ];
    final Color bg    = isRainy ? const Color(0xFFE3F2FD) : const Color(0xFFFFF8E1);
    final Color border = isRainy ? const Color(0xFF1565C0) : const Color(0xFFFF8F00);
    final Color text   = isRainy ? const Color(0xFF1565C0) : const Color(0xFFE65100);

    return StatefulBuilder(builder: (ctx, refresh) {
      if (_dismissed) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(seasonName,
                    style: TextStyle(fontSize: 12, color: text, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                onPressed: () { _SeasonBanner._dismissed = true; refresh(() {}); },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 6),
            ...tips.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('• ', style: TextStyle(fontSize: 12, color: border)),
                Expanded(child: Text(t, style: TextStyle(fontSize: 11, color: text))),
              ]),
            )),
          ],
        ),
      );
    });
  }
}

// ─── Welcome Header ──────────────────────────────────────────────────────────
class _WelcomeHeader extends StatelessWidget {
  final int gardenCount;
  const _WelcomeHeader({required this.gardenCount});

  String _todayLabel() {
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final day = days[now.weekday - 1];
    return '$day, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome Back 👋', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
              const Text('Scan. Learn. Grow.', style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_todayLabel(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (gardenCount > 0)
              Text('$gardenCount plant${gardenCount == 1 ? "" : "s"} in garden',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// ─── Quick Actions Grid ───────────────────────────────────────────────────────
class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDiagnose;
  final VoidCallback onGarden;
  final VoidCallback onCalendar;
  final VoidCallback onWishlist;
  const _QuickActionsGrid({
    required this.onCamera, required this.onGallery, required this.onDiagnose,
    required this.onGarden, required this.onCalendar, required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          _QABtn(icon: Icons.camera_alt_outlined, label: 'Camera', color: const Color(0xFF2E7D32), onTap: onCamera),
          const SizedBox(width: 10),
          _QABtn(icon: Icons.photo_library_outlined, label: 'Gallery', color: const Color(0xFF388E3C), onTap: onGallery),
          const SizedBox(width: 10),
          _QABtn(icon: Icons.bug_report_outlined, label: 'Diagnose', color: const Color(0xFFB71C1C), onTap: onDiagnose),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _QABtn(icon: Icons.local_florist_outlined, label: 'My Garden', color: const Color(0xFF1565C0), onTap: onGarden),
          const SizedBox(width: 10),
          _QABtn(icon: Icons.calendar_month_outlined, label: 'Calendar', color: const Color(0xFF6A1B9A), onTap: onCalendar),
          const SizedBox(width: 10),
          _QABtn(icon: Icons.favorite_border, label: 'Wishlist', color: const Color(0xFFAD1457), onTap: onWishlist),
        ]),
      ],
    );
  }
}

class _QABtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QABtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Recent Activity Card ─────────────────────────────────────────────────────
class _RecentActivityCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _RecentActivityCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final lastScan    = stats['last_scan'] as Map<String, dynamic>?;
    final lastDisease = stats['last_disease'] as Map<String, dynamic>?;
    if (lastScan == null && lastDisease == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          const SizedBox(height: 10),
          if (lastScan != null) _ActivityRow(
            icon: Icons.search,
            iconColor: const Color(0xFF2E7D32),
            title: lastScan['name'] as String? ?? 'Unknown Plant',
            subtitle: 'Last scan',
            imagePath: lastScan['image_path'] as String?,
            date: _formatDate(lastScan['date'] as String?),
          ),
          if (lastScan != null && lastDisease != null) const Divider(height: 16),
          if (lastDisease != null) _ActivityRow(
            icon: Icons.bug_report_outlined,
            iconColor: const Color(0xFFB71C1C),
            title: lastDisease['disease_name'] as String? ?? 'Unknown Disease',
            subtitle: lastDisease['plant_name'] as String? ?? '',
            date: _formatDate(lastDisease['date'] as String?),
            statusChip: lastDisease['status'] as String?,
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) { return ''; }
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? imagePath;
  final String date;
  final String? statusChip;
  const _ActivityRow({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    this.imagePath, required this.date, this.statusChip,
  });

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (imagePath != null && File(imagePath!).existsSync()) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(imagePath!), width: 40, height: 40, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconFallback()),
      );
    } else {
      leading = _iconFallback();
    }

    return Row(
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (statusChip != null)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(statusChip!).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(statusChip!, style: TextStyle(fontSize: 10, color: _statusColor(statusChip!), fontWeight: FontWeight.w600)),
            ),
        ]),
      ],
    );
  }

  Widget _iconFallback() => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
    child: Icon(icon, color: iconColor, size: 20),
  );

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'treated': return Colors.green;
      case 'monitoring': return Colors.orange;
      case 'active': return Colors.red;
      default: return Colors.grey;
    }
  }
}

// ─── Today's Tasks Card ───────────────────────────────────────────────────────
class _TodaysTasksCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback onViewGarden;
  const _TodaysTasksCard({required this.stats, required this.onViewGarden});

  @override
  Widget build(BuildContext context) {
    final rawTasks = stats['tasks_today'];
    final tasks = rawTasks is List ? rawTasks.cast<dynamic>() : <dynamic>[];

    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
        ),
        child: const Row(children: [
          Text('✅', style: TextStyle(fontSize: 22)),
          SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("No Tasks Today", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
            Text("Your garden is doing great!", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ]),
      );
    }

    final urgent = tasks.where((t) {
      final type = (t as Map)['type'] as String? ?? '';
      return type == 'overdue' || type == 'sick';
    }).toList();
    final normal = tasks.where((t) {
      final type = (t as Map)['type'] as String? ?? '';
      return type == 'water_due' || type == 'recovery';
    }).toList();
    final displayTasks = [...urgent, ...normal].take(4).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('📋', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            const Expanded(child: Text("Today's Tasks",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: urgent.isNotEmpty ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${tasks.length}', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold,
                color: urgent.isNotEmpty ? Colors.red : const Color(0xFF2E7D32),
              )),
            ),
          ]),
          const SizedBox(height: 10),
          ...displayTasks.map((t) => _TaskItem(task: Map<String, dynamic>.from((t as Map).cast()))),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onViewGarden,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32), padding: EdgeInsets.zero,
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              tasks.length > 4 ? 'View All ${tasks.length} Tasks →' : 'View Garden →',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskItem extends StatelessWidget {
  final Map<String, dynamic> task;
  const _TaskItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final type = task['type'] as String? ?? '';
    final name = task['plant_name'] as String? ?? 'Plant';
    final days = task['days_overdue'] as int? ?? 0;

    final String emoji;
    final String label;
    final Color color;
    switch (type) {
      case 'overdue':
        emoji = '⚠️'; label = '$name – $days day${days == 1 ? '' : 's'} overdue'; color = Colors.red;
        break;
      case 'water_due':
        emoji = '💧'; label = 'Water $name'; color = const Color(0xFF1565C0);
        break;
      case 'sick':
        emoji = '🦠'; label = '$name – Needs Attention'; color = const Color(0xFFB71C1C);
        break;
      case 'recovery':
        emoji = '🌱'; label = '$name – Follow-up Check'; color = Colors.orange;
        break;
      default:
        emoji = '📌'; label = name; color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─── Top Plant Card ───────────────────────────────────────────────────────────
class _TopPlantCard extends StatelessWidget {
  final Map<String, dynamic> plant;
  final VoidCallback onTap;
  const _TopPlantCard({required this.plant, required this.onTap});

  Color _recColor(String? rec) {
    switch ((rec ?? '').toLowerCase()) {
      case 'highly recommended': return const Color(0xFF1B5E20);
      case 'recommended': return const Color(0xFF1565C0);
      case 'consider carefully': return const Color(0xFFE65100);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = plant['plant_name'] as String? ?? 'Top Plant';
    final sciName = plant['scientific_name'] as String? ?? '';
    final score = plant['score'] as int? ?? 0;
    final rec = plant['recommendation'] as String? ?? '';
    final imagePath = plant['image_path'] as String?;

    // Derive a short reason from the recommendation text
    final String reason;
    switch (rec.toLowerCase()) {
      case 'highly recommended':
        reason = 'Excellent match for your garden. Top suitability score.';
        break;
      case 'recommended':
        reason = 'Good fit for your garden conditions.';
        break;
      case 'consider carefully':
        reason = 'Some conditions may not be ideal, but manageable.';
        break;
      default:
        reason = 'Added to your garden.';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          imagePath != null && File(imagePath).existsSync()
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(imagePath), width: 60, height: 60, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconBox()),
                )
              : _iconBox(),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🌟 ', style: TextStyle(fontSize: 12)),
              const Text('Top Garden Plant', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            const SizedBox(height: 2),
            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (sciName.isNotEmpty)
              Text(sciName, style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(reason, style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _recColor(rec), borderRadius: BorderRadius.circular(12)),
            child: Text('$score/100',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _iconBox() => Container(
    width: 60, height: 60,
    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
    child: const Center(child: Text('🌟', style: TextStyle(fontSize: 28))),
  );
}

// ─── Scan History Screen ──────────────────────────────────────────────────────
class _ScanHistoryScreen extends StatefulWidget {
  const _ScanHistoryScreen();

  @override
  State<_ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<_ScanHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getHistory();
    if (mounted) setState(() { _history = data; _isLoading = false; });
  }

  Color _recColor(String? rec) {
    switch ((rec ?? '').toLowerCase()) {
      case 'highly recommended': return const Color(0xFF1B5E20);
      case 'recommended':        return const Color(0xFF1565C0);
      case 'consider carefully': return const Color(0xFFE65100);
      case 'not recommended':    return const Color(0xFFB71C1C);
      default:                   return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(children: [
          Text('📷', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Scan History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _history.isEmpty
              ? _EmptyScanHistory()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF2E7D32),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (ctx, i) {
                      final item = _history[i] as Map<String, dynamic>;
                      final name = item['plant_name'] as String? ?? '';
                      final sci  = item['scientific_name'] as String? ?? '';
                      final rec  = item['recommendation'] as String? ?? '';
                      final score = ((item['gardenability_score'] ?? item['suitability_score']) as int?) ?? 0;
                      final imagePath = item['image_path'] as String?;
                      final scanDate = item['scan_date'] as String?;
                      final scanCount = item['scan_count'] as int? ?? 1;
                      final color = _recColor(rec);

                      String? dateDisplay;
                      if (scanDate != null) {
                        final dt = DateTime.tryParse(scanDate);
                        if (dt != null) {
                          dateDisplay = '${dt.day}/${dt.month}/${dt.year}';
                        }
                      }

                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            // Image / Score circle
                            imagePath != null && File(imagePath).existsSync()
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(imagePath), width: 56, height: 56, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _scoreCircle(score, color)),
                                  )
                                : _scoreCircle(score, color),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                  color: Color(0xFF1B5E20)), maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (sci.isNotEmpty)
                                Text(sci, style: const TextStyle(fontSize: 12, color: Colors.grey,
                                    fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(rec, style: TextStyle(fontSize: 10, color: color,
                                      fontWeight: FontWeight.w600)),
                                ),
                                if (dateDisplay != null) ...[ 
                                  const SizedBox(width: 6),
                                  Text(dateDisplay, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ]),
                            ])),
                            Column(children: [
                              Text('$score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                              Text('/100', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              if (scanCount > 1) ...[ 
                                const SizedBox(height: 2),
                                Text('${scanCount}x', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _scoreCircle(int score, Color color) => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
    child: Center(child: Text('$score', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))),
  );
}

class _EmptyScanHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withOpacity(0.07),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.photo_camera_outlined, size: 44, color: Color(0xFF2E7D32)),
      ),
      const SizedBox(height: 20),
      const Text('No Scans Yet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
      const SizedBox(height: 8),
      const Text('Scan a plant to start identifying!',
          style: TextStyle(color: Colors.grey, fontSize: 14)),
      const SizedBox(height: 20),
      FilledButton.icon(
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Scan a Plant'),
        style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () => Navigator.pop(context),
      ),
    ]),
  );
}

String _dlgMonth(int m) {
  const n = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return n[m];
}

// ── Multi-Photo Collection Sheet ─────────────────────────────────────────────

class _MultiPhotoSheet extends StatefulWidget {
  final File primaryFile;
  final ImagePicker picker;
  const _MultiPhotoSheet({required this.primaryFile, required this.picker});

  @override
  State<_MultiPhotoSheet> createState() => _MultiPhotoSheetState();
}

class _MultiPhotoSheetState extends State<_MultiPhotoSheet> {
  // Additional photos: type → File
  final Map<String, File?> _extras = {'flower': null, 'leaf_stem': null};

  static String _photoSlotLabel(String type) {
    switch (type) {
      case 'flower': return 'Flower/Fruit';
      case 'leaf_stem': return 'Leaf/Stem';
      default: return type[0].toUpperCase() + type.substring(1);
    }
  }

  Future<void> _pickExtra(String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Text(
            'Add ${_photoSlotLabel(type)} Photo',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF1B5E20),
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20)),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF1565C0),
                child: Icon(Icons.photo_library, color: Colors.white, size: 20)),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;

    final XFile? picked = await widget.picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;
    setState(() => _extras[type] = File(picked.path));
  }

  Future<List<Map<String, String>>> _buildAdditionalImages() async {
    final result = <Map<String, String>>[];
    for (final entry in _extras.entries) {
      if (entry.value != null) {
        final bytes = await entry.value!.readAsBytes();
        result.add({
          'image': base64Encode(bytes),
          'type': entry.key,
        });
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasExtras = _extras.values.any((f) => f != null);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('Identify Plant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Add more photos for better accuracy. Flower photos give the highest confidence.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),

          // Photo slots row: Whole Plant (1) | Flower/Fruit (2) | Leaf & Stem (3)
          Row(children: [
            // Slot 1: Whole Plant — the natural scan shot
            _PhotoSlot(
              label: 'Whole Plant',
              icon: Icons.yard,
              color: const Color(0xFF2E7D32),
              file: widget.primaryFile,
              isRequired: true,
              onTap: null,
            ),
            const SizedBox(width: 10),
            // Slot 2: Flower / Fruit — most diagnostic
            _PhotoSlot(
              label: 'Flower/Fruit',
              icon: Icons.local_florist,
              color: const Color(0xFFE91E63),
              file: _extras['flower'],
              isRequired: false,
              onTap: () => _pickExtra('flower'),
            ),
            const SizedBox(width: 10),
            // Slot 3: Leaf & Stem close-up
            _PhotoSlot(
              label: 'Leaf/Stem',
              icon: Icons.eco,
              color: const Color(0xFF00796B),
              file: _extras['leaf_stem'],
              isRequired: false,
              onTap: () => _pickExtra('leaf_stem'),
            ),
          ]),
          const SizedBox(height: 8),

          // Tip
          if (!hasExtras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.tips_and_updates_outlined, size: 14, color: Color(0xFFE65100)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Tip: Add a flower photo to boost confidence from ~65% to 90%+',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                  ),
                ),
              ]),
            ),

          const SizedBox(height: 8),

          // Identify Now button
          FilledButton.icon(
            icon: const Icon(Icons.search),
            label: Text(
              hasExtras
                ? 'Identify with ${1 + _extras.values.where((f) => f != null).length} Photos'
                : 'Identify Now',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final additional = await _buildAdditionalImages();
              if (context.mounted) Navigator.pop(context, additional);
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final File? file;
  final bool isRequired;
  final VoidCallback? onTap;

  const _PhotoSlot({
    required this.label,
    required this.icon,
    required this.color,
    required this.file,
    required this.isRequired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPhoto = file != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 0.9,
          child: Container(
            decoration: BoxDecoration(
              color: hasPhoto ? null : color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasPhoto ? color : color.withOpacity(0.3),
                width: hasPhoto ? 2 : 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? Stack(fit: StackFit.expand, children: [
                    Image.file(file!, fit: BoxFit.cover),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (isRequired)
                      Positioned(
                        top: 4, right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                              color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 10, color: Colors.white),
                        ),
                      ),
                  ])
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isRequired ? Icons.check_circle : Icons.add_circle_outline,
                          color: color, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(color: color, fontSize: 11,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isRequired)
                        Text('Optional', style: TextStyle(
                            color: color.withOpacity(0.6), fontSize: 10)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
