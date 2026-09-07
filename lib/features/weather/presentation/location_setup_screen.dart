import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../data/location_resolver.dart';
import '../data/open_meteo_weather_service.dart';
import '../domain/weather_models.dart';
import '../domain/weather_service.dart';

/// A privacy-first location setup flow (NO GPS): the user picks a country
/// (prefilled from their nationality as a *default only*), enters a postal
/// code, and confirms the resolved place. Falls back to a city search when the
/// postal code can't be resolved.
///
/// Returns the confirmed [WeatherLocation] via Navigator.pop, or null if
/// cancelled.
class LocationSetupScreen extends StatefulWidget {
  /// The user's nationality country name (default only — not their location).
  final String? defaultCountryName;

  const LocationSetupScreen({super.key, this.defaultCountryName});

  @override
  State<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

enum _Step { input, results, confirm }

class _LocationSetupScreenState extends State<LocationSetupScreen> {
  static const Color _accent = Color(0xFF3FA9F5);

  late final LocationResolver _resolver;
  final WeatherService _weather = OpenMeteoWeatherService();

  final _postalC = TextEditingController();
  final _cityC = TextEditingController();

  String _countryName = 'United States';
  String _countryCode = 'US';
  String _countryFlag = '🇺🇸';

  _Step _step = _Step.input;
  bool _loading = false;
  bool _cityFallback = false;
  String? _error;
  List<LocationSearchResult> _results = [];
  LocationSearchResult? _selected;

  @override
  void initState() {
    super.initState();
    _resolver = LocationResolver(_weather);
    // Prefill country from nationality (DEFAULT ONLY — user can change).
    final def = widget.defaultCountryName;
    if (def != null && def.trim().isNotEmpty) {
      try {
        final c = Country.tryParse(def.trim());
        if (c != null) {
          _countryName = c.name;
          _countryCode = c.countryCode;
          _countryFlag = c.flagEmoji;
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _postalC.dispose();
    _cityC.dispose();
    super.dispose();
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (c) => setState(() {
        _countryName = c.name;
        _countryCode = c.countryCode;
        _countryFlag = c.flagEmoji;
      }),
    );
  }

  Future<void> _resolvePostal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _resolver.resolvePostalCode(
        _postalC.text,
        countryCode: _countryCode,
      );
      if (results.isEmpty) {
        // Postal code couldn't be resolved → offer city fallback.
        setState(() {
          _cityFallback = true;
          _step = _Step.input;
          _error =
              "We couldn't find that postal code. Please search for your city instead.";
        });
      } else if (results.length == 1) {
        setState(() {
          _selected = results.first;
          _step = _Step.confirm;
        });
      } else {
        setState(() {
          _results = results;
          _step = _Step.results;
        });
      }
    } on WeatherServiceException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchCity() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _resolver.searchCity(
        _cityC.text,
        countryCode: _countryCode,
      );
      if (results.isEmpty) {
        setState(() => _error = 'No matching places found. Try another name.');
      } else {
        setState(() {
          _results = results;
          _step = _Step.results;
        });
      }
    } on WeatherServiceException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    final sel = _selected;
    if (sel == null) return;
    final location = sel.toLocation(
      postalCodeOverride: _cityFallback
          ? sel.postalCode
          : (_postalC.text.trim().isEmpty ? sel.postalCode : _postalC.text.trim()),
      source: _cityFallback ? 'manual_city' : 'postal_code',
    );
    Navigator.of(context).pop(location);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF0F8FE),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Weather Location'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: switch (_step) {
          _Step.input => _buildInput(context),
          _Step.results => _buildResults(context),
          _Step.confirm => _buildConfirm(context),
        },
      ),
    );
  }

  // --- Step 1: country + postal (or city fallback) ---
  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Let's personalize your hydration goal.",
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Where are you currently living?',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        Text('Country', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickCountry,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            child: Row(
              children: [
                Text(_countryFlag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Text(_countryName)),
                const Icon(Icons.arrow_drop_down_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_cityFallback) ...[
          Text("What's your postal code?",
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _postalC,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. 80000',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ] else ...[
          Text('Search for your city / town', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _cityC,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Galle',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Your location is used only to personalize weather-based hydration '
          'recommendations.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorText(context, _error!),
        ],
        const SizedBox(height: 24),
        _primaryButton(
          context,
          _loading ? 'Searching…' : 'Continue',
          _loading
              ? null
              : (_cityFallback ? _searchCity : _resolvePostal),
        ),
        if (_cityFallback) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _cityFallback = false;
                _error = null;
              }),
              child: const Text('Use postal code instead'),
            ),
          ),
        ],
      ],
    );
  }

  // --- Step 2: multiple results ---
  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select your location',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ..._results.map((r) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
              ),
              child: ListTile(
                leading: const Icon(Icons.place_rounded, color: _accent),
                title: Text(r.name),
                subtitle: Text(r.displayLine),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() {
                  _selected = r;
                  _step = _Step.confirm;
                }),
              ),
            )),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _step = _Step.input),
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }

  // --- Step 3: confirmation ---
  Widget _buildConfirm(BuildContext context) {
    final theme = Theme.of(context);
    final r = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(child: Text('📍', style: TextStyle(fontSize: 40))),
        const SizedBox(height: 8),
        Center(
          child: Text('Location Found',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _accent.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              _confirmRow('City', r.name),
              if (r.admin1 != null && r.admin1!.isNotEmpty)
                _confirmRow('Region', r.admin1!),
              _confirmRow('Country', r.country),
              if (!_cityFallback && _postalC.text.trim().isNotEmpty)
                _confirmRow('Postal Code', _postalC.text.trim())
              else if (r.postalCode != null && r.postalCode!.isNotEmpty)
                _confirmRow('Postal Code', r.postalCode!),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton(context, 'Confirm Location', _confirm),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _step = _results.length > 1 ? _Step.results : _Step.input;
            }),
            child: const Text('Change'),
          ),
        ),
      ],
    );
  }

  Widget _confirmRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _errorText(BuildContext context, String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0A020).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFF0A020), size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _primaryButton(
      BuildContext context, String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
