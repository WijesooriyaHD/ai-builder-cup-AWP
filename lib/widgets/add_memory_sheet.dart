import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/travel_memory.dart';
import 'location_picker_sheet.dart';
import 'package:uuid/uuid.dart';
import '../utils/wellnesspal_snackbar.dart';

class AddMemorySheet extends StatefulWidget {
  final Future<void> Function(String placeName, double lat, double lng, String note, List<String> photos, bool isPublic, {String? id}) onAdd;
  final TravelMemory? memoryToEdit;
  
  const AddMemorySheet({required this.onAdd, this.memoryToEdit, super.key});

  @override
  State<AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<AddMemorySheet> {
  final _detailsController = TextEditingController();
  final _noteController = TextEditingController();
  Country? _selectedCountry;
  final List<String> _selectedPhotos = [];
  final ImagePicker _picker = ImagePicker();
  Point? _pickedLocation;
  String? _validationError;
  bool _isSaving = false;
  bool _isPublic = false;
  String? _pendingId; // Track ID for retries to avoid duplicates

  @override
  void initState() {
    super.initState();
    if (widget.memoryToEdit != null) {
      final mem = widget.memoryToEdit!;
      _noteController.text = mem.note ?? '';
      _selectedPhotos.addAll(mem.photos);
      _isPublic = mem.isPublic;
      
      if (mem.latitude != 0.0 && mem.longitude != 0.0) {
        _pickedLocation = Point(coordinates: Position(mem.longitude, mem.latitude));
      }
      
      // Parse Place to extract Country
      if (mem.place.contains(",")) {
         final parts = mem.place.split(",");
         final countryName = parts.last.trim();
         
         // Try to find country object
         try {
           final countries = CountryService().getAll();
           final matchedCountry = countries.firstWhere(
             (c) => c.name.toLowerCase() == countryName.toLowerCase() || 
                    c.displayName.toLowerCase() == countryName.toLowerCase(),
             orElse: () => countries.first,
           );
           
           // Check if we found a real match (not just the fallback first country)
           if (matchedCountry.name.toLowerCase() == countryName.toLowerCase() || 
               matchedCountry.displayName.toLowerCase() == countryName.toLowerCase()) {
              _selectedCountry = matchedCountry;
              // Extract city/landmark part (everything before the last comma)
              if (parts.length > 1) {
                _detailsController.text = parts.sublist(0, parts.length - 1).join(",").trim();
              }
           } else {
              // Country not found, put entire place in details
              _detailsController.text = mem.place;
           }
         } catch(e) {
           _detailsController.text = mem.place;
         }
      } else {
         // No comma, might be just country name or just city
         _detailsController.text = mem.place;
      }
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      countryListTheme: CountryListThemeData(
        flagSize: 25,
        backgroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, color: Colors.blueGrey),
        bottomSheetHeight: 500,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
        inputDecoration: InputDecoration(
          labelText: 'Search',
          hintText: 'Start typing to search',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: const Color(0xFF8C98A8).withOpacity(0.2)),
          ),
        ),
      ),
      onSelect: (Country country) {
        setState(() {
          _selectedCountry = country;
        });
      },
    );
  }

  Future<void> _pickPhotos() async {
    if (_selectedPhotos.length >= 5) {
      WellnessPalSnackBar.show(
        context,
        message: "Maximum 5 photos allowed",
        icon: Icons.photo_library_rounded,
        isError: true, // Validation limit
      );
      return;
    }
    
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        limit: 5 - _selectedPhotos.length, 
        imageQuality: 80,
      );
      
      if (images.isNotEmpty) {
        setState(() {
          _selectedPhotos.addAll(images.map((x) => x.path));
        });
      }
    } catch (e) {
      debugPrint("Error picking images: $e");
    }
  }
  
  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  Future<void> _pickLocation() async {
    final Point? result = await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => LocationPickerSheet(initialPoint: _pickedLocation),
      ),
    );
    
    if (result != null) {
      setState(() {
        _pickedLocation = result;
      });
    }
  }

  void _submit() async {
    if (_isSaving) return;

    // Clear previous error
    setState(() => _validationError = null);
    
    // Validate all fields
    List<String> errors = [];
    
    if (_selectedCountry == null && widget.memoryToEdit == null) {
      errors.add("Country");
    }
    
    if (_detailsController.text.trim().isEmpty) {
      errors.add("City/Landmark");
    }
    
    if (_pickedLocation == null) {
      errors.add("Location");
    }
    
    if (_noteController.text.trim().isEmpty) {
      errors.add("Note");
    }
    
    if (_selectedPhotos.isEmpty) {
      errors.add("At least 1 photo");
    }
    
    if (errors.isNotEmpty) {
      setState(() {
        _validationError = "Missing: ${errors.join(", ")}";
      });
      return;
    }

    String placeName;
    if (_selectedCountry != null) {
      if (_detailsController.text.trim().isNotEmpty) {
        placeName = "${_detailsController.text.trim()}, ${_selectedCountry!.name}";
      } else {
        placeName = _selectedCountry!.name;
      }
    } else {
      // Editing mode with no new country selected
      placeName = _detailsController.text.trim();
      if (placeName.isEmpty) placeName = widget.memoryToEdit?.place ?? "Unknown Place";
    }

    double lat = 0.0;
    double lng = 0.0;
    
    // Use picked location if available
    if (_pickedLocation != null) {
       lat = _pickedLocation!.coordinates.lat.toDouble();
       lng = _pickedLocation!.coordinates.lng.toDouble();
    }

    // Generate or reuse ID for retries
    _pendingId ??= const Uuid().v4();

    setState(() => _isSaving = true);
    try {
      await widget.onAdd(
        placeName, 
        lat, 
        lng, 
        _noteController.text, 
        _selectedPhotos, 
        _isPublic,
        id: widget.memoryToEdit?.id ?? _pendingId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _validationError = "Error saving memory: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08), 
              blurRadius: 20, 
              offset: const Offset(0, 5)
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 16),
                
                Text(
                  widget.memoryToEdit != null ? "Edit Memory" : "New Memory", 
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 24),
                
                const SizedBox(height: 16),

                // Location Pin Button (Row with Country)
                Row(
                   children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickCountry,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Theme.of(context).scaffoldBackgroundColor 
                                  : Colors.grey[50], 
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white10 
                                    : Colors.grey[200]!
                              )
                            ),
                            child: Row(
                              children: [
                                if (_selectedCountry != null) ...[
                                  Text(_selectedCountry!.flagEmoji, style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_selectedCountry!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                ] else ...[
                                  const Icon(Icons.public, color: Colors.blueGrey),
                                  const SizedBox(width: 8),
                                  const Expanded(child: Text("Country", style: TextStyle(fontSize: 16, color: Colors.blueGrey))),
                                ],
                                const Icon(Icons.arrow_drop_down, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _pickLocation,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _pickedLocation != null 
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.1) 
                                : (Theme.of(context).brightness == Brightness.dark ? Theme.of(context).scaffoldBackgroundColor : Colors.grey[50]),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _pickedLocation != null 
                                  ? Theme.of(context).colorScheme.primary 
                                  : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[200]!)
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded, 
                                color: _pickedLocation != null ? Theme.of(context).colorScheme.primary : Colors.blueGrey
                              ),
                              if (_pickedLocation != null) ...[
                                 const SizedBox(width: 8),
                                 Text(
                                   "${_pickedLocation!.coordinates.lat.toStringAsFixed(2)}, ${_pickedLocation!.coordinates.lng.toStringAsFixed(2)}",
                                   style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                                 )
                              ]
                            ],
                          ),
                        ),
                      ),
                   ],
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _detailsController,
                  decoration: InputDecoration(
                    hintText: "City or Landmark *",
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).scaffoldBackgroundColor
                        : Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Photos Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Photos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      "${_selectedPhotos.length}/5",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Photos
                SizedBox(
                  height: 100,
                  child: Row(
                    children: [
                      // Add Photo Button
                      if (_selectedPhotos.length < 5)
                        InkWell(
                          onTap: _pickPhotos,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).scaffoldBackgroundColor
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[300]!, 
                                style: BorderStyle.solid
                              ),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: Colors.blueGrey),
                                SizedBox(height: 4),
                                Text("Add Photo", style: TextStyle(fontSize: 12, color: Colors.blueGrey))
                              ],
                            ),
                          ),
                        ),
                        
                      // Photo List
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedPhotos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildSafePhoto(_selectedPhotos[index], 100, 100),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removePhoto(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Add a note...",
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).scaffoldBackgroundColor
                        : Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Public Toggle
                InkWell(
                  onTap: () => setState(() => _isPublic = !_isPublic),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _isPublic,
                            onChanged: (val) => setState(() => _isPublic = val ?? false),
                            activeColor: Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text("Make this memory public", style: TextStyle(fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Icon(Icons.public_rounded, size: 18, color: _isPublic ? Theme.of(context).colorScheme.primary : Colors.grey),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                
                // Validation Error Display
                if (_validationError != null) ...[ 
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                
                const SizedBox(height: 8),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).brightness == Brightness.dark 
                          ? Theme.of(context).scaffoldBackgroundColor 
                          : Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSaving 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          )
                        : const Text("Save Memory", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                 const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
      ),
    ).animate().slideY(begin: 0.2, end: 0, duration: 300.ms).fadeIn();
  }

  Widget _buildSafePhoto(String path, double width, double height) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: Colors.grey[200],
          ).animate(onPlay: (controller) => controller.repeat())
           .shimmer(duration: 1500.ms, color: Colors.grey[100]);
        },
        errorBuilder: (context, error, stackTrace) => Container(
          width: width, height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      return Image.file(
        File(path),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: width, height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
  }
}
