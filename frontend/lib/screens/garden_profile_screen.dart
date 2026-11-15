import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GardenProfileScreen extends StatefulWidget {
  const GardenProfileScreen({super.key});

  @override
  State<GardenProfileScreen> createState() => _GardenProfileScreenState();
}

class _GardenProfileScreenState extends State<GardenProfileScreen> {
  final _locationController = TextEditingController();
  String? _gardenSize;
  String? _sunlight;
  String? _soilType;
  String? _waterAvailability;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<String> _gardenSizes = [
    'Balcony/Pots',
    'Small Yard (<50 sqm)',
    'Medium Yard (50–200 sqm)',
    'Large Yard (>200 sqm)',
  ];
  final List<String> _sunlightOptions = [
    'Full Sun (6+ hrs)',
    'Mostly Sunny (4–6 hrs)',
    'Partial Shade (2–4 hrs)',
    'Full Shade (<2 hrs)',
  ];
  final List<String> _soilTypes = ['Sandy', 'Clay', 'Loam', 'Unknown'];
  final List<String> _waterOptions = [
    'Always Available',
    'Rainwater Mainly',
    'Limited Water',
    'Automatic Irrigation',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ApiService.getGardenProfile();
      if (profile != null) {
        setState(() {
          _locationController.text = profile['location'] ?? '';
          _gardenSize = profile['garden_size'];
          _sunlight = profile['sunlight'];
          _soilType = profile['soil_type'];
          _waterAvailability = profile['water_availability'];
        });
      }
    } catch (_) {
      // No profile yet — that's fine
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ApiService.saveGardenProfile({
        'location': _locationController.text.trim(),
        'garden_size': _gardenSize,
        'sunlight': _sunlight,
        'soil_type': _soilType,
        'water_availability': _waterAvailability,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Garden profile saved! Future scans will be personalised.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        title: const Text('My Garden Profile', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoBanner(),
                  const SizedBox(height: 20),
                  _buildField(
                    label: '📍 Location / City',
                    hint: 'e.g. Kuala Lumpur, Malaysia',
                    child: TextField(
                      controller: _locationController,
                      decoration: _inputDecoration('Enter your city or country'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: '🏡 Garden Size',
                    hint: 'How much space do you have?',
                    child: _Dropdown(
                      value: _gardenSize,
                      items: _gardenSizes,
                      hint: 'Select garden size',
                      onChanged: (v) => setState(() => _gardenSize = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: '☀️ Sunlight Availability',
                    hint: 'How much sun does your garden get?',
                    child: _Dropdown(
                      value: _sunlight,
                      items: _sunlightOptions,
                      hint: 'Select sunlight level',
                      onChanged: (v) => setState(() => _sunlight = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: '🪱 Soil Type',
                    hint: 'What type of soil do you have?',
                    child: _Dropdown(
                      value: _soilType,
                      items: _soilTypes,
                      hint: 'Select soil type',
                      onChanged: (v) => setState(() => _soilType = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: '💧 Water Availability',
                    hint: 'How do you water your plants?',
                    child: _Dropdown(
                      value: _waterAvailability,
                      items: _waterOptions,
                      hint: 'Select water source',
                      onChanged: (v) => setState(() => _waterAvailability = v),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Saving...' : 'Save Garden Profile', style: const TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildField({required String label, required String hint, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B5E20))),
        const SizedBox(height: 4),
        Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: const Row(
        children: [
          Text('🌿', style: TextStyle(fontSize: 24)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tell us about your garden and every plant scan will be personalised — the AI will score each plant based on YOUR specific conditions.',
              style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;

  const _Dropdown({required this.value, required this.items, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: const TextStyle(color: Colors.grey)),
          isExpanded: true,
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
