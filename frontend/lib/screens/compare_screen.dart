import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/report_service.dart';

class CompareScreen extends StatefulWidget {
  final int? id1;
  final int? id2;
  final Map<String, dynamic>? preloadedData;
  const CompareScreen({super.key, this.id1, this.id2, this.preloadedData})
      : assert(preloadedData != null || (id1 != null && id2 != null));

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedData != null) {
      _data = widget.preloadedData;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.comparePlants(widget.id1!, widget.id2!);
      if (!mounted) return;
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F8F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2E7D32),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Compare Plants',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Color(0xFF2E7D32)),
            SizedBox(height: 16),
            Text('Loading comparison…', style: TextStyle(color: Color(0xFF2E7D32))),
          ]),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F8F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2E7D32),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Compare Plants',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black87)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white),
              ),
            ]),
          ),
        ),
      );
    }

    return _CompareBody(data: _data!);
  }
}

class _CompareBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CompareBody({required this.data});

  @override
  Widget build(BuildContext context) {
    try {
      return _buildBody(context);
    } catch (e, st) {
      return Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFF2E7D32),
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Compare Plants', style: TextStyle(color: Colors.white))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('Compare error:\n$e\n\n$st',
              style: const TextStyle(fontSize: 12, color: Colors.red)),
        ),
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    final p1 = (data['plant1'] as Map).cast<String, dynamic>();
    final p2 = (data['plant2'] as Map).cast<String, dynamic>();
    // details may be a JSON string (from API) or already-decoded Map (from local build)
    dynamic raw1 = p1['details'];
    dynamic raw2 = p2['details'];
    Map<String, dynamic> d1;
    Map<String, dynamic> d2;
    try {
      d1 = raw1 is String
          ? (jsonDecode(raw1) as Map).cast<String, dynamic>()
          : (raw1 as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) { d1 = {}; }
    try {
      d2 = raw2 is String
          ? (jsonDecode(raw2) as Map).cast<String, dynamic>()
          : (raw2 as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) { d2 = {}; }

    Map<String, dynamic> _sub(Map<String, dynamic> parent, String key) {
      try {
        final v = parent[key];
        if (v == null) return {};
        if (v is Map) return v.cast<String, dynamic>();
        return {};
      } catch (_) { return {}; }
    }

    final id1   = _sub(d1, 'identification');
    final id2   = _sub(d2, 'identification');
    final suit1 = _sub(d1, 'suitability');
    final suit2 = _sub(d2, 'suitability');
    final grow1 = _sub(d1, 'growing');
    final grow2 = _sub(d2, 'growing');
    final sp1   = _sub(d1, 'space');
    final sp2   = _sub(d2, 'space');
    final m1    = _sub(d1, 'maintenance');
    final m2    = _sub(d2, 'maintenance');
    final fl1   = _sub(d1, 'flowering');
    final fl2   = _sub(d2, 'flowering');
    final h1    = _sub(d1, 'health');
    final h2    = _sub(d2, 'health');
    final pu1   = _sub(d1, 'purchase_decision');
    final pu2   = _sub(d2, 'purchase_decision');

    final score1 = (p1['gardenability_score'] ?? p1['suitability_score'] as num?)?.toInt() ?? 0;
    final score2 = (p2['gardenability_score'] ?? p2['suitability_score'] as num?)?.toInt() ?? 0;
    final name1  = p1['plant_name']        as String? ?? 'Plant 1';
    final name2  = p2['plant_name']        as String? ?? 'Plant 2';
    final img1   = p1['image_path']        as String?;
    final img2   = p2['image_path']        as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Compare Plants',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: 'Export report',
            onPressed: () async {
              try {
                final path = await ReportService.exportCompareReport(data);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Saved to:\n$path'),
                    backgroundColor: const Color(0xFF1B5E20),
                    duration: const Duration(seconds: 5),
                  ));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Export failed: $e'), backgroundColor: Colors.red));
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [

          // ── Plant header cards ──
          Container(
            color: const Color(0xFF2E7D32),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _PlantHeaderCard(name: name1, imagePath: img1, score: score1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('VS',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              Expanded(child: _PlantHeaderCard(name: name2, imagePath: img2, score: score2)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [

              // ── Score comparison bars ──
              _ScoreBar(label: name1, score: score1, isWinner: score1 >= score2, color: const Color(0xFF2E7D32)),
              const SizedBox(height: 6),
              _ScoreBar(label: name2, score: score2, isWinner: score2 > score1, color: const Color(0xFF388E3C)),
              const SizedBox(height: 20),

              // ── Purchase Decision ──
              _SectionHeader('Purchase Decision'),
              _Row('Recommendation', pu1['recommendation'], pu2['recommendation']),
              _Row('Confidence',
                  '${id1['confidence_level'] ?? '—'}%',
                  '${id2['confidence_level'] ?? '—'}%',
                  winner: _cmpInt(id1['confidence_level'], id2['confidence_level'])),

              // ── Growing Conditions ──
              _SectionHeader('Growing Conditions'),
              _Row('Sunlight',     suit1['sunlight'],          suit2['sunlight']),
              _Row('Temperature',  suit1['temperature_range'], suit2['temperature_range']),
              _Row('Humidity',     suit1['humidity'],          suit2['humidity']),
              _Row('Watering',     grow1['watering'],          grow2['watering']),
              _Row('Soil Type',    grow1['soil_type'],         grow2['soil_type']),
              _Row('Soil pH',      grow1['soil_ph'],           grow2['soil_ph']),

              // ── Space & Growth ──
              _SectionHeader('Space & Growth'),
              _Row('Mature Height', sp1['mature_height'], sp2['mature_height']),
              _Row('Mature Width',  sp1['mature_width'],  sp2['mature_width']),
              _Row('Growth Rate',   sp1['growth_rate'],   sp2['growth_rate']),
              _Row('Spacing',       sp1['spacing'],       sp2['spacing']),

              // ── Maintenance ──
              _SectionHeader('Maintenance'),
              _Row('Difficulty',    m1['difficulty'],             m2['difficulty'],
                  winner: _cmpDifficulty(m1['difficulty'], m2['difficulty'])),
              _Row('Pest Risk',     m1['pest_susceptibility'],    m2['pest_susceptibility']),
              _Row('Disease Risk',  m1['disease_susceptibility'], m2['disease_susceptibility']),
              _Row('Pruning',       m1['pruning'],                m2['pruning']),

              // ── Pricing ──
              _SectionHeader('Pricing'),
              _Row('Small Plant',  fl1['price_small'],  fl2['price_small']),
              _Row('Medium Plant', fl1['price_medium'], fl2['price_medium']),
              _Row('Large Plant',  fl1['price_large'],  fl2['price_large']),

              // ── Health & Safety ──
              _SectionHeader('Health & Safety'),
              _Row('Pet Safe',
                  h1['pet_safe'] == true ? '✓ Yes' : '✗ No',
                  h2['pet_safe'] == true ? '✓ Yes' : '✗ No',
                  winner: (h1['pet_safe'] == true && h2['pet_safe'] != true) ? 1
                         : (h2['pet_safe'] == true && h1['pet_safe'] != true) ? 2 : 0),
              _Row('Health Status', h1['health_status'], h2['health_status']),
              _Row('Climate',       suit1['climate'],    suit2['climate']),

              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }

  static int _cmpInt(dynamic a, dynamic b) {
    final ia = a is int ? a : int.tryParse(a?.toString() ?? '') ?? 0;
    final ib = b is int ? b : int.tryParse(b?.toString() ?? '') ?? 0;
    if (ia > ib) return 1;
    if (ib > ia) return 2;
    return 0;
  }

  static int _cmpDifficulty(String? a, String? b) {
    const rank = {'easy': 3, 'medium': 2, 'hard': 1};
    final ra = rank[a?.toLowerCase()] ?? 0;
    final rb = rank[b?.toLowerCase()] ?? 0;
    if (ra > rb) return 1;
    if (rb > ra) return 2;
    return 0;
  }
}

// ─── Plant Header Card ────────────────────────────────────────────────────────
class _PlantHeaderCard extends StatelessWidget {
  final String name;
  final String? imagePath;
  final int score;
  const _PlantHeaderCard({required this.name, required this.imagePath, required this.score});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imagePath != null
            ? Image.file(File(imagePath!),
                width: 120, height: 120, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder(),
      ),
      const SizedBox(height: 8),
      Text(name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Score: $score',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    ]);
  }

  Widget _placeholder() => Container(
    width: 120, height: 120,
    color: Colors.white24,
    child: const Center(child: Text('🌿', style: TextStyle(fontSize: 40))),
  );
}

// ─── Score Bar ────────────────────────────────────────────────────────────────
class _ScoreBar extends StatelessWidget {
  final String label;
  final int score;
  final bool isWinner;
  final Color color;
  const _ScoreBar({required this.label, required this.score, required this.isWinner, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Reserve: score(32) + star(14) + spacing(8) = 54px; label gets 28% of remaining
      final labelW = ((constraints.maxWidth - 54) * 0.28).clamp(60.0, 120.0);
      return Row(children: [
      SizedBox(
        width: labelW,
        child: Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                color: isWinner ? color : Colors.grey)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 14,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
                isWinner ? color : Colors.grey.shade400),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 32,
        child: Text('$score',
            style: TextStyle(
                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
                color: isWinner ? color : Colors.grey)),
      ),
      if (isWinner) const Icon(Icons.star, size: 14, color: Color(0xFFFFC107))
      else const SizedBox(width: 14),
    ]);
    });
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

// ─── Comparison Row ───────────────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final String label;
  final dynamic val1;
  final dynamic val2;
  final int winner; // 0 = neutral, 1 = plant1 wins, 2 = plant2 wins

  const _Row(this.label, this.val1, this.val2, {this.winner = 0});

  @override
  Widget build(BuildContext context) {
    final v1 = val1?.toString() ?? '—';
    final v2 = val2?.toString() ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      child: IntrinsicHeight(
        child: Row(children: [
          // Left value (plant 1)
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            color: winner == 1 ? const Color(0xFFE8F5E9) : Colors.white,
            child: Row(children: [
              if (winner == 1) ...[
                const Icon(Icons.check_circle, size: 13, color: Color(0xFF2E7D32)),
                const SizedBox(width: 4),
              ],
              Expanded(child: Text(v1,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: winner == 1 ? FontWeight.bold : FontWeight.normal,
                      color: winner == 1 ? const Color(0xFF2E7D32) : Colors.black87))),
            ]),
          )),
          // Center label — fixed flex ratio, no LayoutBuilder (incompatible with IntrinsicHeight)
          SizedBox(
            width: 88,
            child: Container(
              color: const Color(0xFFF5F5F5),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              alignment: Alignment.center,
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
          ),
          // Right value (plant 2)
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            color: winner == 2 ? const Color(0xFFE8F5E9) : Colors.white,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Expanded(child: Text(v2,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: winner == 2 ? FontWeight.bold : FontWeight.normal,
                      color: winner == 2 ? const Color(0xFF2E7D32) : Colors.black87))),
              if (winner == 2) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle, size: 13, color: Color(0xFF2E7D32)),
              ],
            ]),
          )),
        ]),
      ),
    );
  }
}
