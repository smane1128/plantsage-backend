import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'disease_result_screen.dart';

// ─── Care task helpers (top-level so widgets can access them) ─────────────────
String _careEmoji(String type) => const {
  'water':      '💧',
  'fertilize':  '🌱',
  'prune':      '✂️',
  'pest_check': '🐛',
}[type] ?? '📋';

String _careLabel(String type) => const {
  'water':      'Water',
  'fertilize':  'Fertilize',
  'prune':      'Prune',
  'pest_check': 'Pest Check',
}[type] ?? type;

class MyGardenScreen extends StatefulWidget {
  const MyGardenScreen({super.key});

  @override
  State<MyGardenScreen> createState() => _MyGardenScreenState();
}

class _MyGardenScreenState extends State<MyGardenScreen> {
  bool _isLoading = true;
  List<dynamic> _plants = [];
  @override
  void initState() {
    super.initState();
    _loadGarden();
  }

  Future<void> _loadGarden() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      ApiService.getMyGarden(),
      ApiService.getCareTasks(),
    ]);
    final plants = results[0] as List<dynamic>;
    final allTasks = results[1] as List<dynamic>;
    // Merge care tasks into each plant (backend may or may not embed them)
    for (final p in plants) {
      if ((p['care_tasks'] as List<dynamic>?)?.isEmpty ?? true) {
        final pid = p['id'] as int?;
        p['care_tasks'] = allTasks.where((t) => t['plant_id'] == pid).toList();
      }
    }
    if (mounted) setState(() { _plants = plants; _isLoading = false; });
  }

  Color _healthColor(String? status) {
    switch (status) {
      case 'healthy':    return const Color(0xFF2E7D32);
      case 'sick':       return const Color(0xFFB71C1C);
      case 'recovering': return const Color(0xFFE65100);
      default:           return Colors.grey.shade400;
    }
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

  Future<void> _removePlant(dynamic plant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Plant'),
        content: Text('Remove "${plant['plant_name']}" from your garden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await ApiService.removeFromMyGarden(plant['id'] as int);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${plant['plant_name']}" removed.'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      _loadGarden();
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
                hintText: 'e.g. Bought from nursery, repotted May 2026...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    if (saved == null || !mounted) return;
    await ApiService.updatePlantNotes(plant['id'] as int, saved);
    _loadGarden();
  }

  Future<void> _markWatered(dynamic plant) async {
    try {
      await ApiService.markWatered(plant['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('💧 "${plant['plant_name']}" marked as watered!'),
        backgroundColor: const Color(0xFF1565C0),
        duration: const Duration(seconds: 3),
      ));
      _loadGarden();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to mark watered: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _diagnoseFromGarden(dynamic plant) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Text('Diagnose Disease',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${plant['plant_name'] ?? 'Plant'}: photograph the affected leaves or stem',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
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
        await picker.pickImage(source: source, imageQuality: 90, maxWidth: 1024);
    if (picked == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final savedPath = '${appDir.path}/myplants_images/${DateTime.now().millisecondsSinceEpoch}_disease.jpg';
      await File(picked.path).copy(savedPath);

      final result = await ApiService.diagnoseDisease(File(picked.path));
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => DiseaseResultScreen(result: result, imagePath: savedPath)));
      _loadGarden();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.contains('quota') ? 'AI quota exceeded — try again later' : 'Diagnosis failed. Please try again.'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showScheduleDialog(dynamic plant) async {
    final current = plant['watering_interval_days'] as int? ?? 0;
    // Read recommendation from backend
    final rec = plant['watering_recommended'] as Map<String, dynamic>?;
    final recDisplay  = rec?['display']   as String?;   // e.g. "Every 1-2 days (pot) · 2-3 days (ground)"
    final recInterval = (rec?['interval'] as num?)?.toInt();
    int selected = current > 0 ? current : (recInterval ?? 2);
    // 'save' | 'remove' | 'reset' | null (cancel)
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.water_drop, color: Color(0xFF1565C0), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Watering Reminder\n${plant['plant_name']}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Recommendation hint ──────────────────────────────────────
            if (recDisplay != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF81C784), width: 0.8),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('💡 ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Recommended for Malaysia:',
                          style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                      Text(recDisplay,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1B5E20))),
                    ]),
                  ),
                ]),
              ),
            // ── Reminder interval picker ──────────────────────────────────
            const Text('Set my reminder to every:',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            if (current > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  'Currently: every $current day${current == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: selected > 1 ? () => setD(() => selected--) : null,
                color: const Color(0xFF2E7D32),
              ),
              Container(
                width: 70,
                alignment: Alignment.center,
                child: Text('$selected day${selected == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: selected < 60 ? () => setD(() => selected++) : null,
                color: const Color(0xFF2E7D32),
              ),
            ]),
            if (current > 0) ...[
              const Divider(height: 20),
              // Mark as watered today (reset)
              _ActionTile(
                icon: Icons.water_drop, color: const Color(0xFF1565C0),
                title: 'Mark as Watered Today', subtitle: 'Restarts the countdown from now',
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
              const SizedBox(height: 6),
              // View history
              _ActionTile(
                icon: Icons.history, color: const Color(0xFF2E7D32),
                title: 'View Watering History', subtitle: 'See past watering dates',
                onTap: () => Navigator.pop(ctx, 'history'),
              ),
              const SizedBox(height: 6),
              // Remove reminder
              _ActionTile(
                icon: Icons.notifications_off_outlined, color: Colors.red,
                title: 'Remove Reminder', subtitle: 'Stop tracking watering for this plant',
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: Text(current > 0 ? 'Update' : 'Set Reminder',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      try {
        await ApiService.setWateringSchedule(plant['id'] as int, selected);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reminder set: every $selected day(s) for "${plant['plant_name']}"'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
        _loadGarden();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'), backgroundColor: Colors.red));
      }
    } else if (action == 'reset') {
      try {
        await ApiService.markWatered(plant['id'] as int);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('💧 Countdown reset — marked as watered today'),
          backgroundColor: Color(0xFF1565C0),
          duration: Duration(seconds: 3),
        ));
        _loadGarden();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset failed: $e'), backgroundColor: Colors.red));
      }
    } else if (action == 'history') {
      _showWateringHistoryDialog(plant);
    } else if (action == 'remove') {
      try {
        await ApiService.setWateringSchedule(plant['id'] as int, 0);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reminder removed for "${plant['plant_name']}"'),
          backgroundColor: Colors.grey.shade700,
        ));
        _loadGarden();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Remove failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showWaterMenu(BuildContext context, dynamic plant, Offset tapPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          tapPos.dx, tapPos.dy, tapPos.dx + 1, tapPos.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        const PopupMenuItem(value: 'water',
            child: Row(children: [
              Icon(Icons.water_drop, color: Color(0xFF1565C0), size: 18),
              SizedBox(width: 10),
              Text('Mark as Watered Today'),
            ])),
        const PopupMenuItem(value: 'history',
            child: Row(children: [
              Icon(Icons.history, color: Color(0xFF2E7D32), size: 18),
              SizedBox(width: 10),
              Text('Watering History'),
            ])),
        const PopupMenuItem(value: 'schedule',
            child: Row(children: [
              Icon(Icons.schedule, color: Color(0xFF2E7D32), size: 18),
              SizedBox(width: 10),
              Text('Change schedule'),
            ])),
        const PopupMenuItem(value: 'remove',
            child: Row(children: [
              Icon(Icons.notifications_off_outlined, color: Colors.red, size: 18),
              SizedBox(width: 10),
              Text('Remove reminder', style: TextStyle(color: Colors.red)),
            ])),
      ],
    );
    if (!mounted) return;
    if (result == 'water') {
      _markWatered(plant);
    } else if (result == 'history') {
      _showWateringHistoryDialog(plant);
    } else if (result == 'schedule') {
      _showScheduleDialog(plant);
    } else if (result == 'remove') {
      await ApiService.setWateringSchedule(plant['id'] as int, 0);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reminder removed for "${plant['plant_name']}"'),
        backgroundColor: Colors.grey.shade700,
      ));
      _loadGarden();
    }
  }

  Future<void> _showHealthDialog(dynamic plant) async {
    final current = plant['health_status'] as String?;
    final options = <Map<String, dynamic>>[
      {'value': 'healthy',    'label': 'Healthy',    'icon': Icons.favorite,        'color': const Color(0xFF2E7D32)},
      {'value': 'recovering', 'label': 'Recovering', 'icon': Icons.healing,         'color': const Color(0xFFE65100)},
      {'value': 'sick',       'label': 'Sick',       'icon': Icons.sick_outlined,   'color': const Color(0xFFB71C1C)},
    ];
    String? selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.monitor_heart_outlined, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Health of ${plant['plant_name']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...options.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: current == o['value']
                    ? (o['color'] as Color).withOpacity(0.12)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(ctx, o['value'] as String),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(children: [
                      Icon(o['icon'] as IconData, color: o['color'] as Color, size: 20),
                      const SizedBox(width: 12),
                      Text(o['label'] as String,
                          style: TextStyle(
                              fontWeight: current == o['value']
                                  ? FontWeight.bold : FontWeight.normal)),
                      if (current == o['value']) ...[
                        const Spacer(),
                        Icon(Icons.check, color: o['color'] as Color, size: 16),
                      ],
                    ]),
                  ),
                ),
              ),
            )),
            if (current != null)
              TextButton.icon(
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear status'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                onPressed: () => Navigator.pop(ctx, '__clear__'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final newStatus = selected == '__clear__' ? null : selected;
    final err = await ApiService.updateHealthStatus(plant['id'] as int, newStatus);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red));
    } else {
      _loadGarden();
    }
  }

  Future<void> _showWateringHistoryDialog(dynamic plant) async {
    final history = await ApiService.getWateringHistory(plant['id'] as int);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.history, color: Color(0xFF1565C0), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Watering History\n${plant['plant_name']}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: 300,
          child: history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No watering history yet.',
                      style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final raw = history[i]['watered_at'] as String;
                    final dt = DateTime.tryParse(raw);
                    final display = dt != null
                        ? '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
                        : raw;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.water_drop, color: Color(0xFF1565C0), size: 18),
                      title: Text(display, style: const TextStyle(fontSize: 13)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ─── Rename plant ──────────────────────────────────────────────────────────
  Future<void> _renamePlant(dynamic plant) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: plant['garden_name'] as String? ?? '');
        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.label_outline, color: Color(0xFF388E3C)),
            SizedBox(width: 8),
            Text('Rename Plant'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Species', style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  plant['scientific_name'] as String? ?? plant['plant_name'] as String? ?? '',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Custom Name',
                hintText: 'e.g. Front Gate Jasmine, Pot #1',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF388E3C)),
              child: const Text('Rename', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (saved == null || !mounted) return;
    final err = await ApiService.renamePlant(plant['id'] as int, saved,
        currentNotes: plant['notes'] as String?);
    if (mounted) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
      } else {
        _loadGarden();
      }
    }
  }

  // ─── More options menu (rename + edit notes) ───────────────────────────────
  void _showMoreMenu(BuildContext context, dynamic plant, Offset tapPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(tapPos.dx, tapPos.dy, tapPos.dx + 1, tapPos.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        const PopupMenuItem(value: 'rename', child: Row(children: [
          Icon(Icons.label_outline, color: Color(0xFF388E3C), size: 18),
          SizedBox(width: 10),
          Text('Rename Plant'),
        ])),
        PopupMenuItem(value: 'notes', child: Row(children: [
          Icon(
            (plant['notes'] as String?)?.isNotEmpty == true ? Icons.edit_note : Icons.note_add_outlined,
            color: const Color(0xFF388E3C), size: 18,
          ),
          const SizedBox(width: 10),
          const Text('Edit Notes'),
        ])),
      ],
    );
    if (!mounted) return;
    if (result == 'rename') _renamePlant(plant);
    else if (result == 'notes') _editNotes(plant);
  }

  // ─── Care task management dialog ───────────────────────────────────────────
  Future<void> _showCareTaskDialog(dynamic plant, Map<String, dynamic> task) async {
    final type = task['task_type'] as String;
    final taskId = task['id'] as int;
    int selectedInterval = task['interval_days'] as int? ?? 7;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            Text(_careEmoji(type), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '${_careLabel(type)}\n${plant['plant_name']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            )),
          ]),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Status banner
            Builder(builder: (_) {
              final d = task['days_until_due'] as int?;
              String label; Color color;
              if (d == null)   { label = 'No schedule';                         color = Colors.grey; }
              else if (d < 0)  { label = 'Overdue by ${-d} day${-d==1?'':'s'}'; color = const Color(0xFFB71C1C); }
              else if (d == 0) { label = 'Due Today';                            color = const Color(0xFFE65100); }
              else if (d == 1) { label = 'Due Tomorrow';                         color = const Color(0xFF1565C0); }
              else             { label = 'Due in $d days';                       color = Colors.grey.shade600; }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.4), width: 0.7),
                ),
                child: Text(label,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              );
            }),
            const SizedBox(height: 12),
            const Text('Repeat every:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: selectedInterval > 1 ? () => setD(() => selectedInterval--) : null,
                color: const Color(0xFF2E7D32),
              ),
              SizedBox(
                width: 90,
                child: Center(child: Text('$selectedInterval days',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: selectedInterval < 365 ? () => setD(() => selectedInterval++) : null,
                color: const Color(0xFF2E7D32),
              ),
            ]),
            const Divider(height: 20),
            _ActionTile(
              icon: Icons.check_circle_outline, color: const Color(0xFF2E7D32),
              title: 'Mark Done Today', subtitle: 'Resets the countdown from now',
              onTap: () => Navigator.pop(ctx, 'done'),
            ),
            const SizedBox(height: 6),
            _ActionTile(
              icon: Icons.history, color: const Color(0xFF1565C0),
              title: 'View History', subtitle: 'See past completion dates',
              onTap: () => Navigator.pop(ctx, 'history'),
            ),
            const SizedBox(height: 6),
            _ActionTile(
              icon: Icons.notifications_off_outlined, color: Colors.red,
              title: 'Remove Reminder', subtitle: 'Stop tracking this task',
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Save Schedule', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      final err = await ApiService.updateCareSchedule(taskId, selectedInterval);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? '${_careLabel(type)} every $selectedInterval days'),
          backgroundColor: err != null ? Colors.red : const Color(0xFF2E7D32),
        ));
        if (err == null) _loadGarden();
      }
    } else if (action == 'done') {
      await ApiService.completeCareTask(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_careEmoji(type)} ${_careLabel(type)} marked done today!'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
        _loadGarden();
      }
    } else if (action == 'history') {
      await _showCareHistoryDialog(taskId, type, plant['plant_name'] as String);
    } else if (action == 'remove') {
      final err = await ApiService.deleteCareTask(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? '${_careLabel(type)} reminder removed'),
          backgroundColor: err != null ? Colors.red : Colors.grey.shade700,
        ));
        if (err == null) _loadGarden();
      }
    }
  }

  // ─── Care task history dialog ──────────────────────────────────────────────
  Future<void> _showCareHistoryDialog(int taskId, String taskType, String plantName) async {
    final history = await ApiService.getCareHistory(taskId);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(_careEmoji(taskType), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text('${_careLabel(taskType)} History\n$plantName',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: 300,
          child: history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No history yet.',
                      style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final dt = DateTime.tryParse(history[i]['done_at'] as String? ?? '');
                    final display = dt != null
                        ? '${dt.day}/${dt.month}/${dt.year}  '
                          '${dt.hour.toString().padLeft(2, '0')}:'
                          '${dt.minute.toString().padLeft(2, '0')}'
                        : (history[i]['done_at'] as String? ?? '');
                    return ListTile(
                      dense: true,
                      leading: Text(_careEmoji(taskType), style: const TextStyle(fontSize: 16)),
                      title: Text(display, style: const TextStyle(fontSize: 13)),
                      subtitle: history[i]['notes'] != null
                          ? Text(history[i]['notes'] as String,
                              style: const TextStyle(fontSize: 11, color: Colors.grey))
                          : null,
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _exportGarden() async {
    final bytes = await ApiService.exportGardenCsv();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed.'), backgroundColor: Colors.red));
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/my_garden_export.csv');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to ${file.path}'),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showDiseaseTrackingDialog(dynamic plant) async {
    final disease = plant['active_disease'] as Map<String, dynamic>;
    final scanId  = disease['id'] as int;
    final diseaseName = disease['disease_name'] as String? ?? 'Unknown disease';
    final status      = disease['status'] as String? ?? 'active';

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.bug_report_outlined, color: Color(0xFFB71C1C), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Disease Tracking\n${plant['plant_name']}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Color(0xFFB71C1C), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(diseaseName,
                    style: const TextStyle(fontWeight: FontWeight.bold,
                        color: Color(0xFFB71C1C))),
                Text('Status: ${status[0].toUpperCase()}${status.substring(1)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
            ]),
          ),
          if ((disease['follow_up_notes'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(disease['follow_up_notes'] as String,
                  style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Update status:', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            if (status != 'recovering') Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.healing, size: 16),
                label: const Text('Recovering', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100))),
                onPressed: () => Navigator.pop(ctx, 'recovering'),
              ),
            ),
            if (status != 'recovering') const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.check_circle, size: 16),
                label: const Text('Resolved!', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => Navigator.pop(ctx, 'resolved'),
              ),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final err = await ApiService.updateDiseaseStatus(scanId, action);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red));
    } else {
      final msg = action == 'resolved'
          ? '${plant['plant_name']} marked as healthy!'
          : 'Status updated to Recovering.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: const Color(0xFF2E7D32)));
      _loadGarden();
    }
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
            Text('🌱', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('My Garden', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: 'Export to CSV',
            onPressed: _exportGarden,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadGarden,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _plants.isEmpty
              ? _EmptyGarden()
              : RefreshIndicator(
                  onRefresh: _loadGarden,
                  color: const Color(0xFF2E7D32),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plants.length + 1, // +1 for stats header
                    itemBuilder: (context, i) {
                      if (i == 0) return _GardenStatsHeader(plants: _plants);
                      final p = _plants[i - 1];
                      final color = _recColor(p['recommendation'] as String?);
                      final score = (p['gardenability_score'] ?? p['suitability_score']) as int? ?? 0;
                      return Dismissible(
                        key: Key('plant-${p['id']}'),
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
                          await _removePlant(p);
                          return false; // We handle reload ourselves
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
                                  scientificName: p['scientific_name'] as String?,
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
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1B5E20),
                                        ),
                                      ),
                                      // Custom garden name label
                                      if ((p['garden_name'] as String?)?.isNotEmpty == true)
                                        Text(
                                          p['garden_name'] as String,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF388E3C),
                                          ),
                                        ),
                                      if ((p['scientific_name'] as String?)?.isNotEmpty == true)
                                        Text(
                                          p['scientific_name'] as String,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      if ((p['plant_type'] as String?)?.isNotEmpty == true)
                                        _PlantTypeBadge(plantType: p['plant_type'] as String),
                                      // Planting type badge
                                      if ((p['planting_type'] as String?) != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Row(children: [
                                            Icon(
                                              p['planting_type'] == 'ground'
                                                  ? Icons.park_outlined
                                                  : Icons.local_florist_outlined,
                                              size: 11, color: const Color(0xFF388E3C)),
                                            const SizedBox(width: 3),
                                            Text(
                                              p['planting_type'] == 'ground' ? 'In Ground' : 'In Pot',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF388E3C))),
                                          ]),
                                        ),
                                      // Location tag
                                      if ((p['location'] as String?)?.isNotEmpty == true)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Row(children: [
                                            const Icon(Icons.place_outlined, size: 11, color: Colors.grey),
                                            const SizedBox(width: 3),
                                            Text(
                                              p['location'] as String,
                                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                                            ),
                                          ]),
                                        ),
                                      // Added date + age
                                      if ((p['date_added'] as String?) != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 3),
                                          child: _DateAgeBadge(
                                            dateAdded: p['date_added'] as String,
                                            purchaseDate: p['purchase_date'] as String?,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          p['recommendation'] as String? ?? 'Unknown',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if ((p['notes'] as String?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.sticky_note_2_outlined, size: 12, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                p['notes'] as String,
                                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      // ── Care section (watering + care tasks) ──
                                      Builder(builder: (_) {
                                        final careTasks = (p['care_tasks'] as List<dynamic>?) ?? [];
                                        final waterInterval = p['watering_interval_days'] as int? ?? 0;
                                        final recMap = p['watering_recommended'] as Map<String, dynamic>?;
                                        final String? rec = p['planting_type'] == 'ground'
                                            ? (recMap?['ground_range'] as String?)
                                            : (recMap?['pot_range'] as String?);
                                        final allTasks = <Map<String, dynamic>>[];
                                        if (waterInterval > 0) {
                                          allTasks.add({
                                            'task_type': 'water',
                                            'interval_days': waterInterval,
                                            'days_until_due': p['days_until_water'],
                                            'last_done_at': p['last_watered_at'],
                                          });
                                        }
                                        allTasks.addAll(
                                          careTasks.map((t) => Map<String, dynamic>.from(t as Map)),
                                        );
                                        if (allTasks.isEmpty) return const SizedBox.shrink();
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 6),
                                            const Divider(height: 6, thickness: 0.4),
                                            _NextDueRow(tasks: allTasks),
                                            const SizedBox(height: 2),
                                            ...allTasks.map((t) => GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                if (t['task_type'] == 'water') _showScheduleDialog(p);
                                                else _showCareTaskDialog(p, t);
                                              },
                                              child: _CareRow(
                                                task: t,
                                                recommended: t['task_type'] == 'water' ? rec : null,
                                              ),
                                            )),
                                          ],
                                        );
                                      }),
                                      // Health status chip — show only when set
                                      if ((p['health_status'] as String?) != null) ...[
                                        const SizedBox(height: 4),
                                        _HealthChip(status: p['health_status'] as String),
                                      ],
                                      // Active disease alert
                                      if (p['active_disease'] != null) ...[
                                        const SizedBox(height: 4),
                                        GestureDetector(
                                          onTap: () => _showDiseaseTrackingDialog(p),
                                          child: _DiseaseAlertChip(
                                            disease: p['active_disease'] as Map<String, dynamic>),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Action column
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // More options (rename + edit notes)
                                    Builder(builder: (btnCtx) => IconButton(
                                      icon: const Icon(Icons.more_vert, color: Color(0xFF2E7D32), size: 22),
                                      tooltip: 'More options',
                                      onPressed: () {
                                        final box = btnCtx.findRenderObject() as RenderBox;
                                        final offset = box.localToGlobal(Offset.zero);
                                        _showMoreMenu(btnCtx, p, offset);
                                      },
                                    )),
                                    // Health status button
                                    IconButton(
                                      icon: Icon(
                                        Icons.monitor_heart_outlined,
                                        color: _healthColor(p['health_status'] as String?),
                                        size: 22,
                                      ),
                                      tooltip: 'Set health status',
                                      onPressed: () => _showHealthDialog(p),
                                    ),
                                    // Diagnose button
                                    IconButton(
                                      icon: const Icon(Icons.biotech_outlined, color: Color(0xFFB71C1C), size: 20),
                                      tooltip: 'Diagnose disease',
                                      onPressed: () => _diagnoseFromGarden(p),
                                    ),
                                    const Icon(Icons.swipe_left, color: Colors.grey, size: 16),
                                  ],
                                ),
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

class _GardenStatsHeader extends StatelessWidget {
  final List<dynamic> plants;
  const _GardenStatsHeader({required this.plants});

  @override
  Widget build(BuildContext context) {
    final total = plants.length;
    final counts = <String, int>{
      'Highly Recommended': 0,
      'Recommended': 0,
      'Consider Carefully': 0,
      'Not Recommended': 0,
    };
    for (final p in plants) {
      final rec = (p['recommendation'] as String? ?? '').toLowerCase();
      if (rec == 'highly recommended') counts['Highly Recommended'] = counts['Highly Recommended']! + 1;
      else if (rec == 'recommended') counts['Recommended'] = counts['Recommended']! + 1;
      else if (rec == 'consider carefully') counts['Consider Carefully'] = counts['Consider Carefully']! + 1;
      else counts['Not Recommended'] = counts['Not Recommended']! + 1;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$total Plant${total == 1 ? '' : 's'} in Your Garden',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBadge(count: counts['Highly Recommended']!, label: 'Top Pick', color: const Color(0xFF1B5E20)),
              _StatBadge(count: counts['Recommended']!, label: 'Good', color: const Color(0xFF1565C0)),
              _StatBadge(count: counts['Consider Carefully']!, label: 'Careful', color: const Color(0xFFE65100)),
              _StatBadge(count: counts['Not Recommended']!, label: 'Risky', color: const Color(0xFFB71C1C)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _StatBadge({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

class _EmptyGarden extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌿', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'Your garden is empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan a plant and tap "Add to My Garden"\nto start your collection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PlantThumb extends StatelessWidget {
  final String? imagePath;
  final String? scientificName;
  final int score;
  final Color color;

  const _PlantThumb({
    required this.imagePath,
    required this.scientificName,
    required this.score,
    required this.color,
  });

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

class _HealthChip extends StatelessWidget {
  final String status;
  const _HealthChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final map = <String, Map<String, dynamic>>{
      'healthy':    {'label': 'Healthy',    'icon': Icons.favorite,      'color': const Color(0xFF2E7D32)},
      'sick':       {'label': 'Sick',       'icon': Icons.sick_outlined,  'color': const Color(0xFFB71C1C)},
      'recovering': {'label': 'Recovering', 'icon': Icons.healing,        'color': const Color(0xFFE65100)},
    };
    final info = map[status] ?? {'label': status, 'icon': Icons.help_outline, 'color': Colors.grey};
    final color = info['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(info['icon'] as IconData, size: 11, color: color),
        const SizedBox(width: 3),
        Text(info['label'] as String,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _DiseaseAlertChip extends StatelessWidget {
  final Map<String, dynamic> disease;
  const _DiseaseAlertChip({required this.disease});

  @override
  Widget build(BuildContext context) {
    final name   = disease['disease_name'] as String? ?? 'Disease';
    final status = disease['status']       as String? ?? 'active';
    final isRecovering = status == 'recovering';
    final color  = isRecovering ? const Color(0xFFE65100) : const Color(0xFFB71C1C);
    final icon   = isRecovering ? Icons.healing : Icons.bug_report_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Flexible(child: Text(
          name.length > 20 ? '${name.substring(0, 18)}…' : name,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        )),
        const SizedBox(width: 3),
        Icon(Icons.touch_app, size: 10, color: color.withOpacity(0.6)),
      ]),
    );
  }
}

// ─── Plant Type Badge ───────────────────────────────────────────────────────
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
    if (l.contains('fern') || l.contains('grass')) return '🌿';
    return '🌱'; // default
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

class _WaterBadge extends StatelessWidget {
  final int intervalDays;
  final int? daysUntil;
  const _WaterBadge({required this.intervalDays, required this.daysUntil});

  @override
  Widget build(BuildContext context) {
    final days = daysUntil ?? 0;
    Color color;
    String label;
    if (days <= 0) {
      color = const Color(0xFF1565C0);
      label = days == 0 ? '💧 Water today!' : '💧 Overdue ${(-days)}d';
    } else if (days <= 2) {
      color = const Color(0xFF64B5F6);
      label = '💧 In $days day${days == 1 ? '' : 's'}';
    } else {
      color = Colors.grey;
      label = '💧 In $days days';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Care Row (tappable — one care task summary) ─────────────────────────────
class _CareRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final String? recommended; // range string e.g. "1-2" (no units)
  const _CareRow({required this.task, this.recommended});

  @override
  Widget build(BuildContext context) {
    final type     = task['task_type'] as String;
    final interval = task['interval_days'] as int? ?? 0;
    final d        = task['days_until_due'] as int?;

    Color statusColor;
    String statusText;
    if (d == null)   { statusColor = Colors.grey;                  statusText = 'Not set'; }
    else if (d < 0)  { statusColor = const Color(0xFFB71C1C);      statusText = 'Overdue'; }
    else if (d == 0) { statusColor = const Color(0xFFE65100);      statusText = 'Today'; }
    else if (d == 1) { statusColor = const Color(0xFF1565C0);      statusText = 'Tomorrow'; }
    else if (d <= 3) { statusColor = const Color(0xFF1565C0);      statusText = 'in ${d}d'; }
    else             { statusColor = Colors.grey.shade600;          statusText = 'in ${d}d'; }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(_careEmoji(type), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 5),
        Expanded(child: Row(children: [
          Text(_careLabel(type),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(width: 4),
          Text('${interval}d', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (recommended != null) ...[
            const SizedBox(width: 4),
            Flexible(child: Text('· rec ${recommended}d',
                style: const TextStyle(fontSize: 10, color: Color(0xFF2E7D32)),
                overflow: TextOverflow.ellipsis)),
          ],
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withOpacity(0.4), width: 0.7),
          ),
          child: Text(statusText,
              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
        ),
        const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
      ]),
    );
  }
}

// ─── Next Due Row (urgent upcoming tasks badge strip) ─────────────────────────
class _NextDueRow extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  const _NextDueRow({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final urgent = tasks
        .where((t) { final d = t['days_until_due'] as int?; return d != null && d <= 3 && t['task_type'] != 'water'; })
        .toList()
      ..sort((a, b) => (a['days_until_due'] as int).compareTo(b['days_until_due'] as int));

    if (urgent.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Wrap(spacing: 5, runSpacing: 3, children: urgent.map((t) {
        final type = t['task_type'] as String;
        final d    = t['days_until_due'] as int;
        Color color;
        String label;
        if (d < 0)      { color = const Color(0xFFB71C1C); label = '${_careEmoji(type)} Overdue'; }
        else if (d == 0){ color = const Color(0xFFE65100); label = '${_careEmoji(type)} Today'; }
        else if (d == 1){ color = const Color(0xFF1565C0); label = '${_careEmoji(type)} Tomorrow'; }
        else            { color = const Color(0xFF1565C0); label = '${_careEmoji(type)} in ${d}d'; }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4), width: 0.7),
          ),
          child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        );
      }).toList()),
    );
  }
}

// ─── Reusable action tile for care dialogs ────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.color,
      required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: color.withOpacity(0.08),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        ]),
      ),
    ),
  );
}

// ─── Date + Age Badge ─────────────────────────────────────────────────────────
class _DateAgeBadge extends StatelessWidget {
  final String dateAdded;
  final String? purchaseDate;
  const _DateAgeBadge({required this.dateAdded, this.purchaseDate});

  static String _fmt(DateTime d) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month]} ${d.year}';
  }

  static String _age(DateTime from) {
    final days = DateTime.now().difference(from).inDays;
    if (days < 1) return 'Today';
    if (days < 31) return '${days}d';
    final months = (days / 30.44).floor();
    if (months < 12) return '$months mo';
    final years = (months / 12).floor();
    final rem = months % 12;
    return rem == 0 ? '$years yr' : '$years yr $rem mo';
  }

  @override
  Widget build(BuildContext context) {
    final added = DateTime.tryParse(dateAdded);
    final purchased = purchaseDate != null ? DateTime.tryParse(purchaseDate!) : null;
    final display = purchased ?? added;
    if (display == null) return const SizedBox.shrink();

    return Row(children: [
      const Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey),
      const SizedBox(width: 3),
      Text(
        'Added ${_fmt(display)}  ·  Age: ${_age(display)}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    ]);
  }
}
