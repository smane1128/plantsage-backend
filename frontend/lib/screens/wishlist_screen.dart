import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _isLoading = true;
  List<dynamic> _plants = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final plants = await ApiService.getWishlist();
    if (mounted) setState(() { _plants = plants; _isLoading = false; });
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

  Future<void> _moveToGarden(dynamic plant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move to Garden'),
        content: Text('Move "${plant['plant_name']}" from wishlist to My Garden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move', style: TextStyle(color: Color(0xFF2E7D32))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await ApiService.moveWishlistToGarden(plant['id'] as int);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? '${plant['plant_name']} moved to your garden! 🌱'),
      backgroundColor: error != null ? Colors.orange[700] : const Color(0xFF2E7D32),
    ));
    _load();
  }

  Future<void> _remove(dynamic plant) async {
    final error = await ApiService.removeFromWishlist(plant['id'] as int);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    } else {
      _load();
    }
  }

  Future<void> _editNotes(dynamic plant) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: plant['notes'] as String? ?? '');
        return StatefulBuilder(
          builder: (ctx, _) => AlertDialog(
            title: Text('Notes for ${plant['plant_name']}'),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. Saw at nursery, price \$12...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFAD1457)),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    if (saved == null || !mounted) return;
    await ApiService.updateWishlistNotes(plant['id'] as int, saved);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Row(
          children: [
            Text('❤️', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('Wishlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _plants.isEmpty
              ? _EmptyWishlist()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF2E7D32),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plants.length,
                    itemBuilder: (context, i) {
                      final p = _plants[i];
                      final color = _recColor(p['recommendation'] as String?);
                      return Dismissible(
                        key: Key('wish-${p['id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white, size: 28),
                        ),
                        confirmDismiss: (_) async {
                          await _remove(p);
                          return false;
                        },
                        child: Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                // Plant photo or score circle
                                _PlantThumb(
                                  imagePath: p['image_path'] as String?,
                                  score: p['suitability_score'] as int? ?? 0,
                                  color: color,
                                ),
                                const SizedBox(width: 14),
                                // Plant info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['plant_name'] as String? ?? '',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                                      ),
                                      if ((p['scientific_name'] as String?)?.isNotEmpty == true)
                                        Text(
                                          p['scientific_name'] as String,
                                          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey),
                                        ),
                                      if ((p['plant_type'] as String?)?.isNotEmpty == true)
                                        _PlantTypeBadge(plantType: p['plant_type'] as String),
                                      if ((p['notes'] as String?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          const Icon(Icons.sticky_note_2_outlined, size: 12, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(child: Text(
                                            p['notes'] as String,
                                            style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          )),
                                        ]),
                                      ],
                                      const SizedBox(height: 6),
                                      // Move to Garden button
                                      SizedBox(
                                        height: 30,
                                        child: TextButton.icon(
                                          onPressed: () => _moveToGarden(p),
                                          icon: const Icon(Icons.local_florist, size: 14, color: Color(0xFF2E7D32)),
                                          label: const Text(
                                            'Move to Garden',
                                            style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            backgroundColor: const Color(0xFFE8F5E9),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Notes edit button
                                IconButton(
                                  icon: Icon(
                                    (p['notes'] as String?)?.isNotEmpty == true
                                        ? Icons.edit_note
                                        : Icons.note_add_outlined,
                                    color: const Color(0xFFAD1457),
                                    size: 22,
                                  ),
                                  tooltip: 'Edit notes',
                                  onPressed: () => _editNotes(p),
                                ),
                                const Icon(Icons.swipe_left, color: Colors.grey, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmptyWishlist extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('❤️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'Your wishlist is empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan a plant and tap ❤️ to save it\nfor later consideration.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Scan a Plant'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAD1457),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantThumb extends StatelessWidget {
  final String? imagePath;
  final int score;
  final Color color;

  const _PlantThumb({required this.imagePath, required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    if (imagePath != null && imagePath!.isNotEmpty) {
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _FullScreenImageViewer(imagePath: imagePath!)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(imagePath!),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _scoreCircle(),
          ),
        ),
      );
    }
    return _scoreCircle();
  }

  Widget _scoreCircle() => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(
            '$score',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
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
          child: Image.file(File(imagePath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _PlantTypeBadge extends StatelessWidget {
  final String plantType;
  const _PlantTypeBadge({required this.plantType});

  static String _emoji(String t) {
    final l = t.toLowerCase();
    if (l.contains('flower') || l.contains('bloom') || l.contains('orchid') || l.contains('rose')) return '🌸';
    if (l.contains('fruit') || l.contains('citrus') || l.contains('mango') || l.contains('banana')) return '🍋';
    if (l.contains('palm')) return '🌴';
    if (l.contains('tree')) return '🌳';
    if (l.contains('succulent') || l.contains('cactus')) return '🌵';
    if (l.contains('herb') || l.contains('spice') || l.contains('mint') || l.contains('basil')) return '🌿';
    if (l.contains('aquatic') || l.contains('water')) return '💧';
    if (l.contains('shrub') || l.contains('bush')) return '🌾';
    if (l.contains('vine') || l.contains('climber')) return '🌼';
    return '🌱';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = _emoji(plantType);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(plantType, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}

