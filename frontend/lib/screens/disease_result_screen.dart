import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DiseaseResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  final String? imagePath;

  const DiseaseResultScreen({super.key, required this.result, this.imagePath});

  @override
  State<DiseaseResultScreen> createState() => _DiseaseResultScreenState();
}

class _DiseaseResultScreenState extends State<DiseaseResultScreen> {
  bool _tracking = false;   // currently linking
  bool _tracked  = false;   // already linked
  int? _scanId;

  @override
  void initState() {
    super.initState();
    _scanId = widget.result['_scan_id'] as int?;
    // Already healthy scans don't need tracking
    final isHealthy = widget.result['_is_healthy'] as bool? ?? false;
    if (isHealthy) _tracked = true;
  }

  Future<void> _trackInGarden() async {
    final plants = await ApiService.getMyGarden();
    if (!mounted) return;
    if (plants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No plants in My Garden yet.'),
            backgroundColor: Colors.orange));
      return;
    }
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.local_florist, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: 8),
          Text('Which plant is affected?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 300,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: plants.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = plants[i] as Map<String, dynamic>;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.eco, color: Color(0xFF2E7D32), size: 20),
                title: Text(p['plant_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: p['scientific_name'] != null
                    ? Text(p['scientific_name'] as String,
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic))
                    : null,
                onTap: () => Navigator.pop(ctx, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _tracking = true);
    final err = await ApiService.linkDiseaseScan(
      _scanId!,
      picked['id'] as int,
      picked['plant_name'] as String,
    );
    if (!mounted) return;
    setState(() { _tracking = false; _tracked = err == null; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '"${picked['plant_name']}" marked as sick. Tracking started.'),
      backgroundColor: err == null ? const Color(0xFF2E7D32) : Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final plant      = (widget.result['plant']     as Map?)?.cast<String, dynamic>() ?? {};
    final diag       = (widget.result['diagnosis'] as Map?)?.cast<String, dynamic>() ?? {};
    final treatment  = (widget.result['treatment'] as Map?)?.cast<String, dynamic>() ?? {};
    final causes     = List<String>.from(widget.result['causes']     as List? ?? []);
    final prevention = List<String>.from(widget.result['prevention'] as List? ?? []);
    final urgency    = widget.result['urgency'] as String? ?? 'Monitor';

    final status        = diag['status']        as String? ?? 'Unknown';
    final diseaseName   = diag['disease_name']  as String? ?? 'Unknown';
    final diseaseType   = diag['disease_type']  as String? ?? '';
    final severity      = diag['severity']      as String? ?? 'None';
    final confidence    = diag['confidence']    as int?    ?? 0;
    final symptoms      = List<String>.from(diag['symptoms']       as List? ?? []);
    final affectedParts = List<String>.from(diag['affected_parts'] as List? ?? []);
    final description   = diag['description']   as String? ?? '';

    final immediateActions = List<String>.from((treatment['immediate_actions'] as List?) ?? []);
    final products         = List<String>.from((treatment['products']          as List?) ?? []);
    final application      = treatment['application']   as String? ?? '';
    final recoveryTime     = treatment['recovery_time'] as String? ?? '';

    final isHealthy = status.toLowerCase() == 'healthy';

    Color statusColor;
    IconData statusIcon;
    if (isHealthy) {
      statusColor = const Color(0xFF2E7D32);
      statusIcon  = Icons.check_circle_outline;
    } else {
      switch (severity.toLowerCase()) {
        case 'mild':
          statusColor = const Color(0xFFF9A825);
          statusIcon  = Icons.warning_amber_outlined;
          break;
        case 'moderate':
          statusColor = const Color(0xFFE65100);
          statusIcon  = Icons.warning_outlined;
          break;
        case 'severe':
          statusColor = const Color(0xFFC62828);
          statusIcon  = Icons.dangerous_outlined;
          break;
        default:
          statusColor = const Color(0xFFE65100);
          statusIcon  = Icons.bug_report_outlined;
      }
    }

    Color urgencyColor;
    switch (urgency.toLowerCase()) {
      case 'act now':      urgencyColor = Colors.red;             break;
      case 'act soon':     urgencyColor = Colors.deepOrange;      break;
      case 'monitor':      urgencyColor = Colors.amber.shade700;  break;
      case 'low priority': urgencyColor = Colors.green.shade600;  break;
      default:             urgencyColor = const Color(0xFF2E7D32);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      body: CustomScrollView(
        slivers: [
          // ── Collapsing header with plant photo ──
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: statusColor,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              isHealthy ? '✓ Healthy Plant' : '⚠ Disease Detected',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: widget.imagePath != null
                  ? Image.file(File(widget.imagePath!), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _headerPlaceholder(statusColor, isHealthy))
                  : _headerPlaceholder(statusColor, isHealthy),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Status banner card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: statusColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(statusIcon, color: Colors.white, size: 30),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            isHealthy ? 'Plant is Healthy!' : diseaseName,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          )),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          '${plant['name'] ?? 'Unknown Plant'}'
                          '${plant['scientific_name'] != null && plant['scientific_name'] != 'null'
                              ? '  •  ${plant['scientific_name']}' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (!isHealthy) _chip(severity, Colors.white24),
                          if (diseaseType.isNotEmpty && diseaseType != 'None')
                            _chip(diseaseType, Colors.white24),
                          _chip('$confidence% confidence', Colors.white24),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: urgencyColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(urgency,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (isHealthy) ...[
                    _Section(
                      icon: Icons.eco,
                      title: 'Plant Health Summary',
                      iconColor: const Color(0xFF2E7D32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (description.isNotEmpty) ...[
                          Text(description, style: const TextStyle(fontSize: 14, height: 1.5)),
                          const SizedBox(height: 8),
                        ],
                        const Text(
                          'No diseases, pests, or deficiencies detected. Keep up with regular care!',
                          style: TextStyle(fontSize: 14, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500),
                        ),
                      ]),
                    ),
                  ] else ...[

                    // ── Affected Parts ──
                    if (affectedParts.isNotEmpty) ...[
                      const Text('Affected Parts',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF555555))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 6,
                        children: affectedParts.map((part) => Chip(
                          label: Text(part,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C))),
                          backgroundColor: const Color(0xFFFFEBEE),
                          side: const BorderSide(color: Color(0xFFEF9A9A)),
                          padding: EdgeInsets.zero,
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── About ──
                    if (description.isNotEmpty)
                      _Section(
                        icon: Icons.info_outline,
                        title: 'About this Condition',
                        iconColor: Colors.blueGrey,
                        child: Text(description, style: const TextStyle(fontSize: 14, height: 1.5)),
                      ),

                    // ── Symptoms ──
                    if (symptoms.isNotEmpty)
                      _Section(
                        icon: Icons.search,
                        title: 'Symptoms Detected',
                        iconColor: const Color(0xFFE65100),
                        child: _BulletList(items: symptoms, color: const Color(0xFFE65100)),
                      ),

                    // ── Causes ──
                    if (causes.isNotEmpty)
                      _Section(
                        icon: Icons.bolt,
                        title: 'Likely Causes',
                        iconColor: const Color(0xFFF9A825),
                        child: _BulletList(items: causes, color: const Color(0xFFF9A825)),
                      ),

                    // ── Treatment ──
                    _Section(
                      icon: Icons.medical_services_outlined,
                      title: 'Treatment Plan',
                      iconColor: const Color(0xFF1565C0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (immediateActions.isNotEmpty) ...[
                          const Text('Immediate Actions',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20))),
                          const SizedBox(height: 6),
                          _BulletList(items: immediateActions, color: const Color(0xFF2E7D32)),
                          const SizedBox(height: 12),
                        ],
                        if (products.isNotEmpty) ...[
                          const Text('Recommended Products',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20))),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 6,
                            children: products.map((prod) => Chip(
                              label: Text(prod, style: const TextStyle(fontSize: 12)),
                              backgroundColor: const Color(0xFFE8F5E9),
                              side: const BorderSide(color: Color(0xFF81C784)),
                            )).toList(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (application.isNotEmpty && application != 'N/A')
                          _InfoRow(icon: Icons.schedule, label: 'How to Apply', value: application),
                        if (recoveryTime.isNotEmpty && recoveryTime != 'N/A')
                          _InfoRow(icon: Icons.hourglass_bottom, label: 'Recovery Time', value: recoveryTime),
                      ]),
                    ),
                  ],

                  // ── Prevention (always shown) ──
                  if (prevention.isNotEmpty)
                    _Section(
                      icon: Icons.shield_outlined,
                      title: 'Prevention Tips',
                      iconColor: const Color(0xFF1565C0),
                      child: _BulletList(items: prevention, color: const Color(0xFF1565C0)),
                    ),

                  // ── Track in My Garden button ──
                  if (!isHealthy && _scanId != null) ...[                  
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: _tracked
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                              label: const Text('Tracking in My Garden',
                                  style: TextStyle(color: Color(0xFF2E7D32))),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF2E7D32)),
                                  padding: const EdgeInsets.symmetric(vertical: 14)),
                            )
                          : FilledButton.icon(
                              onPressed: _tracking ? null : _trackInGarden,
                              icon: _tracking
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.add_task),
                              label: const Text('Track in My Garden'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB71C1C),
                                  padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPlaceholder(Color color, bool healthy) => Container(
    color: color.withOpacity(0.15),
    child: Center(
      child: Text(healthy ? '🌿' : '🔍', style: const TextStyle(fontSize: 80)),
    ),
  );

  Widget _chip(String label, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
  );
}

// ─── Section Card ─────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Color iconColor;

  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: iconColor)),
            ]),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

// ─── Bullet List ─────────────────────────────────────────────────────────────
class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color color;
  const _BulletList({required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.4))),
        ]),
      )).toList(),
    );
  }
}

// ─── Info Row ────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Expanded(child: RichText(text: TextSpan(
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ))),
      ]),
    );
  }
}
