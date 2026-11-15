import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  final _locationCtrl = TextEditingController();
  String? _gardenSize;
  String? _sunlight;
  String? _soilType;
  String? _waterAvailability;
  bool _isSaving = false;

  final List<String> _gardenSizes = [
    'Balcony/Pots',
    'Small Yard (<50 sqm)',
    'Medium Yard (50-200 sqm)',
    'Large Yard (>200 sqm)',
  ];
  final List<String> _sunlightOptions = [
    'Full Sun (6+ hrs)',
    'Mostly Sunny (4-6 hrs)',
    'Partial Shade (2-4 hrs)',
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
  void dispose() {
    _pageController.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _page = page);
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    try {
      await ApiService.saveGardenProfile({
        'location': _locationCtrl.text.trim(),
        'garden_size': _gardenSize,
        'sunlight': _sunlight,
        'soil_type': _soilType,
        'water_availability': _waterAvailability,
      });
    } catch (_) {
      // Profile save failure is non-fatal — user can update in Settings later
    } finally {
      setState(() => _isSaving = false);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: SafeArea(
        child: Column(children: [
          // Skip button — hidden on last page
          Align(
            alignment: Alignment.topRight,
            child: _page < 2
                ? TextButton(
                    onPressed: _finish,
                    child: const Text('Skip',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  )
                : const SizedBox(height: 40),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _WelcomePage(onNext: () => _goTo(1)),
                _ProfilePage(
                  locationCtrl: _locationCtrl,
                  gardenSize: _gardenSize,
                  sunlight: _sunlight,
                  soilType: _soilType,
                  waterAvailability: _waterAvailability,
                  gardenSizes: _gardenSizes,
                  sunlightOptions: _sunlightOptions,
                  soilTypes: _soilTypes,
                  waterOptions: _waterOptions,
                  onChanged: (key, val) => setState(() {
                    if (key == 'garden_size') _gardenSize = val;
                    if (key == 'sunlight') _sunlight = val;
                    if (key == 'soil_type') _soilType = val;
                    if (key == 'water_availability') _waterAvailability = val;
                  }),
                  onNext: () => _goTo(2),
                  onBack: () => _goTo(0),
                ),
                _ReadyPage(isSaving: _isSaving, onFinish: _finish),
              ],
            ),
          ),
          // Page indicator dots
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 1: Welcome
// ─────────────────────────────────────────────────────────────
class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  Widget _featureRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        const SizedBox(height: 24),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.eco, size: 56, color: Colors.white),
        ),
        const SizedBox(height: 24),
        const Text('Welcome to PlantSage',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 10),
        Text('Your smart Malaysian gardening companion',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.85))),
        const SizedBox(height: 36),
        _featureRow(Icons.camera_alt_outlined, 'Identify any plant instantly'),
        _featureRow(Icons.healing_outlined, 'Diagnose plant diseases with AI'),
        _featureRow(Icons.water_drop_outlined, 'Track watering schedules'),
        _featureRow(
            Icons.local_florist_outlined, 'Manage your garden collection'),
        _featureRow(Icons.chat_bubble_outline, 'Chat with an AI plant expert'),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Get Started',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 2: Garden Profile Setup
// ─────────────────────────────────────────────────────────────
class _ProfilePage extends StatelessWidget {
  final TextEditingController locationCtrl;
  final String? gardenSize, sunlight, soilType, waterAvailability;
  final List<String> gardenSizes, sunlightOptions, soilTypes, waterOptions;
  final void Function(String key, String? val) onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _ProfilePage({
    required this.locationCtrl,
    required this.gardenSize,
    required this.sunlight,
    required this.soilType,
    required this.waterAvailability,
    required this.gardenSizes,
    required this.sunlightOptions,
    required this.soilTypes,
    required this.waterOptions,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        const Text('Set Up Your Garden',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 6),
        Text('Help us personalise recommendations for your garden.',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withOpacity(0.8))),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            TextField(
              controller: locationCtrl,
              decoration: InputDecoration(
                labelText: 'Your Location (e.g. Kuala Lumpur)',
                prefixIcon: const Icon(Icons.location_on_outlined,
                    color: Color(0xFF2E7D32)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),
            _DropdownField(
                label: 'Garden Size',
                icon: Icons.crop_free,
                value: gardenSize,
                items: gardenSizes,
                onChanged: (v) => onChanged('garden_size', v)),
            const SizedBox(height: 12),
            _DropdownField(
                label: 'Sunlight Level',
                icon: Icons.wb_sunny_outlined,
                value: sunlight,
                items: sunlightOptions,
                onChanged: (v) => onChanged('sunlight', v)),
            const SizedBox(height: 12),
            _DropdownField(
                label: 'Soil Type',
                icon: Icons.landscape_outlined,
                value: soilType,
                items: soilTypes,
                onChanged: (v) => onChanged('soil_type', v)),
            const SizedBox(height: 12),
            _DropdownField(
                label: 'Water Availability',
                icon: Icons.water_drop_outlined,
                value: waterAvailability,
                items: waterOptions,
                onChanged: (v) => onChanged('water_availability', v)),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B5E20),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Next',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
      ]),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> items;
  final void Function(String?) onChanged;

  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      items: items
          .map((s) => DropdownMenuItem(
              value: s,
              child: Text(s, style: const TextStyle(fontSize: 13))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Page 3: All Set
// ─────────────────────────────────────────────────────────────
class _ReadyPage extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onFinish;
  const _ReadyPage({required this.isSaving, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        const SizedBox(height: 40),
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline,
              size: 64, color: Colors.white),
        ),
        const SizedBox(height: 28),
        const Text("You're All Set!",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 12),
        Text(
          'PlantSage is now personalised for your garden.\nStart by scanning your first plant.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.85),
              height: 1.5),
        ),
        const SizedBox(height: 36),
        ...[
          '1. Scan a plant photo',
          '2. Get AI-powered advice',
          '3. Add it to your garden',
          '4. Track health and watering',
        ].map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.arrow_right, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(s,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9))),
              ]),
            )),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isSaving ? null : onFinish,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1B5E20)))
                : const Text('Start Scanning',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
