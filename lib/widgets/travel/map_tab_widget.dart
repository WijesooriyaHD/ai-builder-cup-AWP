import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'dart:typed_data';
import 'dart:async';
import 'dart:io' as dart;
import '../../models/travel_memory.dart';
import '../../providers/app_state.dart';
import '../../utils/marker_generator.dart';
import '../../utils/wellnesspal_snackbar.dart';
import '../../widgets/add_memory_sheet.dart'; 
import '../../services/auth_service.dart';
import '../../widgets/full_screen_image_viewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/achievement_service.dart';
import '../../services/storage_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MapTabWidget extends StatefulWidget {
  final String accessToken;

  const MapTabWidget({
    super.key,
    required this.accessToken,
  });

  @override
  State<MapTabWidget> createState() => MapTabWidgetState();
}

class MapTabWidgetState extends State<MapTabWidget> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  final Map<String, TravelMemory> _markerMap = {}; 
  final Map<String, Uint8List> _markerImageCache = {}; // Cache for marker images
  bool _isRotationPaused = false;
  bool _showWorldMemories = false;
  final bool _isInteracting = false;
  bool _isProcessing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    // Clean up
    super.dispose();
  }

  // Public method for parent to control map
  Future<void> flyTo(double lat, double lng) async {
    _setStateSafe(() => _isRotationPaused = true);
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 12,
        pitch: 60,
      ),
      MapAnimationOptions(duration: 2000),
    );
  }

  void _setStateSafe(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    
    // Enable 3D Globe Projection
    try {
      await mapboxMap.style.setProjection(StyleProjection(name: StyleProjectionName.globe));
    } catch (e) {
      debugPrint("Error setting style projection: $e");
    }

    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    _pointAnnotationManager?.addOnPointAnnotationClickListener(MyPointClickListener(this));
    
    // Enable Gestures
    try {
      await mapboxMap.gestures.updateSettings(
        GesturesSettings(
          pinchToZoomEnabled: true,
          scrollEnabled: true,
          rotateEnabled: true,
          doubleTapToZoomInEnabled: true,
          doubleTouchToZoomOutEnabled: true,
        ),
      );
    } catch (e) {
      debugPrint("Error enabling gestures: $e");
    }

    // Initial load
    await _refreshPins();

    // Start auto-rotation
    _startRotationLoop();
  }

  Future<void> _refreshPins() async {
    _setStateSafe(() => _isProcessing = true);
    try {
      if (_showWorldMemories) {
        await Provider.of<AppState>(context, listen: false).fetchPublicMemories();
      }
      await _loadPins();
    } finally {
      _setStateSafe(() => _isProcessing = false);
    }
  }

  Future<void> reloadPins() async {
     await _loadPins();
  }


  Future<void> _loadPins() async {
    if (_pointAnnotationManager == null || _mapboxMap == null) return;
    
    final appState = Provider.of<AppState>(context, listen: false);

    // Clear existing
    await _pointAnnotationManager?.deleteAll();
    _markerMap.clear();

    final memoriesToShow = List<TravelMemory>.from(appState.travelMemories);
    if (_showWorldMemories) {
      for (var m in appState.publicMemories) {
         if (!memoriesToShow.any((existing) => existing.id == m.id)) {
            memoriesToShow.add(m);
         }
      }
    }

    // Phase 1: Instant Render with Default Markers
    final List<PointAnnotationOptions> options = [];
    final List<TravelMemory> orderedMemories = [];
    
    // Generate a default marker once to ensure it exists
    final defaultMarkerImage = await MarkerGenerator.createDefaultMarkerBitmap(Colors.redAccent);

    for (var memory in memoriesToShow) {
       orderedMemories.add(memory);
       options.add(PointAnnotationOptions(
          geometry: Point(coordinates: Position(memory.longitude, memory.latitude)),
          iconSize: 0.5, // Standard size for our generated bitmaps
          image: defaultMarkerImage, // Guaranteed to exist
          iconAnchor: IconAnchor.BOTTOM,
       ));
    }

    try {
      final annotations = await _pointAnnotationManager?.createMulti(options);
      
      if (annotations != null) {
        // Map annotations to memories for interaction
        for (var i = 0; i < annotations.length; i++) {
            final annotation = annotations[i];
            if (annotation != null) {
               _markerMap[annotation.id] = orderedMemories[i];
            }
        }
        
        // Phase 2: Background Update with Images
        // We do NOT await this, allowing the UI to remain responsive
        _updateMarkersWithImages(annotations, orderedMemories);
      }
    } catch (e) {
      debugPrint("Error creating markers: $e");
    }
  }

  Future<void> _updateMarkersWithImages(List<PointAnnotation?> annotations, List<TravelMemory> memories) async {
     for (var i = 0; i < annotations.length; i++) {
        final annotation = annotations[i];
        final memory = memories[i];
        
        if (annotation == null) continue;
        if (memory.photos.isEmpty) continue; // Keep default if no photos

        // Check cache first for instant update
        if (_markerImageCache.containsKey(memory.id)) {
           _applyImageToAnnotation(annotation, _markerImageCache[memory.id]!);
        } else {
           // Queue for generation
           _generateAndUpdateMarker(annotation, memory);
        }
     }
  }

  void _generateAndUpdateMarker(PointAnnotation annotation, TravelMemory memory) async {
      try {
        final markerImage = await MarkerGenerator.createCustomMarkerBitmap(memory.photos.first);
        if (markerImage != null) {
           _markerImageCache[memory.id] = markerImage;
           if (mounted) {
              _applyImageToAnnotation(annotation, markerImage);
           }
        }
      } catch (e) {
        // Ignore generation errors, keep default marker
      }
  }

  void _applyImageToAnnotation(PointAnnotation annotation, Uint8List markerImage) async {
      try {
        annotation.image = markerImage;
        annotation.iconImage = null; // Clear default icon name
        annotation.iconSize = 0.5;
        annotation.iconAnchor = IconAnchor.CENTER;
        await _pointAnnotationManager?.update(annotation);
      } catch(e) {
         debugPrint("Error updating annotation: $e");
      }
  }

  void _startRotationLoop() async {
    while (mounted) {
      if (!_isInteracting && !_isRotationPaused && _mapboxMap != null) {
        try {
          final cameraState = await _mapboxMap!.getCameraState();
          final currentCenter = cameraState.center;
          final currentZoom = cameraState.zoom;
          final currentPitch = cameraState.pitch;
          
          double newLng = currentCenter.coordinates.lng - 0.1; // Slow speed
          if (newLng < -180) newLng += 360;
          
          await _mapboxMap!.easeTo(
            CameraOptions(
              center: Point(coordinates: Position(newLng, currentCenter.coordinates.lat)),
              zoom: currentZoom,
              pitch: currentPitch,
            ),
            MapAnimationOptions(duration: 50, startDelay: 0), 
          );
        } catch (e) {
          // Ignore camera errors
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _updateZoom(double delta) async {
    if (_mapboxMap == null) return;
    try {
      final cameraState = await _mapboxMap!.getCameraState();
      _mapboxMap?.flyTo(
        CameraOptions(zoom: cameraState.zoom + delta),
        MapAnimationOptions(duration: 400),
      );
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  Future<void> _resetCamera() async {
    if (_mapboxMap == null) return;
    try {
      // Pause rotation to allow flyTo to complete without interference
      _setStateSafe(() {
        _isRotationPaused = true; 
      });
      
      await _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(0, 20)),
          zoom: 1.5,
          bearing: 0,
          pitch: 0,
          padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        ),
        MapAnimationOptions(duration: 2000),
      );
    } catch (e) {
      debugPrint("Reset camera error: $e");
    }
  }

  void _onMarkerClick(PointAnnotation annotation) {
    final memory = _markerMap[annotation.id];
    if (memory != null) {
      _showMemoryDetails(memory);
    }
  }

  void _showMemoryDetails(TravelMemory memory) {
     // Re-implement or call back? 
     // Ideally self-contained. Using a local copy of _showMemoryDetails since it's UI logic.
     // We will need to import AddMemorySheet and other dependencies.
     showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MemoryDetailsSheet(memory: memory, onRefresh: _refreshPins),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: MapWidget(
              key: const ValueKey("mapWidget"),
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(0, 20)),
                zoom: 1.5,
              ),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.OUTDOORS,
              onCameraChangeListener: (cancel) {
                 // Detect interaction? Mapbox SDK usually handles this but we can use Listener on the widget if needed.
              },
            ),
          ),
        ),
        
        // Controls
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'map_world_toggle_mini',
                mini: true,
                backgroundColor: _showWorldMemories ? Theme.of(context).colorScheme.primary : Colors.white,
                foregroundColor: _showWorldMemories ? Colors.white : Colors.black,
                onPressed: () {
                  setState(() => _showWorldMemories = !_showWorldMemories);
                  _refreshPins();
                },
                child: Icon(_showWorldMemories ? Icons.public : Icons.person),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'map_center_globe',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: _resetCamera,
                child: const Icon(Icons.center_focus_strong),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'map_refresh',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: _refreshPins,
                child: const Icon(Icons.refresh),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'map_pause_rotate',
                mini: true,
                backgroundColor: _isRotationPaused ? Colors.amber : Colors.white,
                foregroundColor: _isRotationPaused ? Colors.white : Colors.black,
                onPressed: () => setState(() => _isRotationPaused = !_isRotationPaused),
                child: Icon(_isRotationPaused ? Icons.play_arrow : Icons.pause),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'map_zoom_in',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: () => _updateZoom(1),
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 4),
              FloatingActionButton(
                heroTag: 'map_zoom_out',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: () => _updateZoom(-1),
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),

        // Loading Indicator
        if (_isProcessing)
           Positioned.fill(
             child: Container(
               color: Colors.black.withOpacity(0.6),
               child: Center(
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     Container(
                       padding: const EdgeInsets.all(32),
                       decoration: BoxDecoration(
                         shape: BoxShape.circle,
                         boxShadow: [
                           BoxShadow(
                             color: Colors.white.withOpacity(0.3),
                             blurRadius: 30,
                             spreadRadius: 10,
                           ),
                           BoxShadow(
                             color: Colors.cyanAccent.withOpacity(0.3),
                             blurRadius: 60,
                             spreadRadius: 20,
                           ),
                         ],
                       ),
                       child: const CircularProgressIndicator(
                         strokeWidth: 8,
                         color: Colors.white,
                       ),
                     ),
                   ],
                 ),
               ),
             ),
           ),

        // Token Warning Overlay
        if (widget.accessToken == "YOUR_MAPBOX_ACCESS_TOKEN_HERE")
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 40),
                  SizedBox(height: 16),
                  Text(
                    "Mapbox Token Required",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Please add your Mapbox Public Access Token in lib/screens/travel_screen.dart",
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
      ],
    );
  }
}

class MyPointClickListener extends OnPointAnnotationClickListener {
  final MapTabWidgetState state;
  MyPointClickListener(this.state);
  
  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    state._onMarkerClick(annotation);
  }
}

class _MemoryDetailsSheet extends StatefulWidget {
  final TravelMemory memory;
  final VoidCallback onRefresh;
  
  const _MemoryDetailsSheet({required this.memory, required this.onRefresh});

  @override
  State<_MemoryDetailsSheet> createState() => _MemoryDetailsSheetState();
}

class _MemoryDetailsSheetState extends State<_MemoryDetailsSheet> {

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Memory?"),
        content: const Text("This action cannot be undone. Are you sure you want to delete this travel memory?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showAddPlaceBottomSheet(BuildContext context, {TravelMemory? existingMemory}) {
     showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddMemorySheet(
          memoryToEdit: existingMemory,
          onAdd: (placeName, lat, lng, note, photos, isPublic, {id}) async {
             WellnessPalSnackBar.show(context, message: existingMemory != null ? "Updating..." : "Adding...", icon: Icons.sync);
             try {
               if (existingMemory != null) {
                  final updated = TravelMemory(
                    id: existingMemory.id,
                    place: placeName,
                    latitude: lat == 0.0 ? existingMemory.latitude : lat,
                    longitude: lng == 0.0 ? existingMemory.longitude : lng,
                    visitedDate: existingMemory.visitedDate,
                    memory: "", 
                    note: note, 
                    photos: photos,
                    isPublic: isPublic
                  );
                  await Provider.of<AppState>(context, listen: false).updateTravelMemory(updated);
                  WellnessPalSnackBar.show(context, message: "Updated successfully", icon: Icons.check);
               } else {
                  // Add logic if we were allowing adds from here, but this is edit mainly
               }
               widget.onRefresh();
             } catch (e) {
               WellnessPalSnackBar.show(context, message: "Error: $e", isError: true);
             }
          },
        );
      },
    );
  }

  Widget _buildRefinedSafeImage(String path, BoxFit fit, {double? width, double? height}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
    final highlightColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5);

    Widget shimmerSkeleton() => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
      ),
    ).animate(onPlay: (controller) => controller.repeat())
     .shimmer(duration: 1200.ms, color: highlightColor);

    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return shimmerSkeleton();
        },
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image),
        ),
      );
    } else {
      return Image.file(
        dart.File(path),
        fit: fit,
        width: width,
        height: height,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return shimmerSkeleton();
        },
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(Icons.place_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(memory.place, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (memory.userDisplayName != null) Text("by ${memory.userDisplayName}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (memory.photos.isNotEmpty) ...[
                        const Text("PHOTOS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: memory.photos.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, i) => GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullScreenImageViewer(imagePath: memory.photos[i]),
                                ),
                              ),
                              child: Hero(
                                tag: memory.photos[i],
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildRefinedSafeImage(memory.photos[i], BoxFit.cover, width: 220),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      if ((memory.note != null && memory.note!.isNotEmpty) || memory.memory.isNotEmpty) ...[
                        const Text("NOTES", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.withOpacity(0.1)),
                          ),
                          child: Text(memory.note ?? memory.memory, style: const TextStyle(fontSize: 16, height: 1.6)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
                ),
                child: Builder(
                  builder: (context) {
                    final currentUser = AuthService().currentUser;
                    // Strict ownership check:
                    // 1. If memory has no userId (legacy local), treat as owner (or maybe not? Assuming local is owner for now)
                    // 2. If memory has userId, it MUST match currentUser.id
                    final isOwner = (memory.userId == null) || (currentUser != null && memory.userId == currentUser.uid);

                    if (isOwner) {
                      return Row(
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 1.5,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showAddPlaceBottomSheet(context, existingMemory: memory);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  foregroundColor: Theme.of(context).colorScheme.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(height: 8),
                                    Text("Edit", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 1.5,
                              child: ElevatedButton(
                                onPressed: () async {
                                   final confirm = await _confirmDelete(context);
                                   if (confirm) {
                                     Navigator.pop(context);
                                     try {
                                       await Provider.of<AppState>(context, listen: false).deleteTravelMemory(memory.id);
                                       widget.onRefresh();
                                     } catch (e) {
                                       // handle error
                                     }
                                   }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.withOpacity(0.1),
                                  foregroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.delete_rounded, size: 32, color: Colors.red),
                                    const SizedBox(height: 8),
                                    const Text("Delete", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return GestureDetector(
                        onTap: () {
                          if (memory.userId != null) {
                            _showPublicProfileSheet(context, memory.userId!, memory.userDisplayName ?? "Traveler", memory.userAvatarUrl);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5), width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: (memory.userAvatarUrl != null && memory.userAvatarUrl!.isNotEmpty) 
                                      ? NetworkImage(memory.userAvatarUrl!) 
                                      : null,
                                  child: (memory.userAvatarUrl == null || memory.userAvatarUrl!.isEmpty)
                                      ? Text(
                                          (memory.userDisplayName ?? "U").substring(0, 1).toUpperCase(),
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          "Shared by",
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Theme.of(context).colorScheme.primary),
                                      ],
                                    ),
                                    Text(
                                      memory.userDisplayName ?? "Traveler",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
  }
  void _showPublicProfileSheet(BuildContext context, String userId, String name, String? avatarUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.6, // Increased height for larger cards
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: StorageService().fetchUserProfile(userId),
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final unlockedIds = List<String>.from(profile?['unlocked_achievements'] ?? []);
              final allAchievements = AchievementService().achievements;
              final unlockedAchievements = allAchievements.where((a) => unlockedIds.contains(a.id)).toList();

              return Column(
                children: [
                  const SizedBox(height: 24),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text("Traveler", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                  if (profile?['instagram'] != null && (profile?['instagram'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final username = profile?['instagram'];
                        if (username == null || username.isEmpty) return;
                        
                        final nativeUrl = Uri.parse("instagram://user?username=$username");
                        final webUrl = Uri.parse("https://www.instagram.com/$username/");
                        
                        try {
                          if (await canLaunchUrl(nativeUrl)) {
                            await launchUrl(nativeUrl, mode: LaunchMode.externalApplication);
                          } else {
                            await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          // Fallback to web if everything fails
                          if (await canLaunchUrl(webUrl)) {
                            await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.pink.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/images/instagram.svg',
                              width: 14,
                              height: 14,
                              colorFilter: const ColorFilter.mode(Colors.pink, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "@${profile?['instagram']}",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.pink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    )
                  else if (unlockedAchievements.isNotEmpty) ...[
                    const Text("ACHIEVEMENTS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 100, // Increased height for larger cards
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: unlockedAchievements.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => Container(
                          width: 90,
                          height: 90,
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(unlockedAchievements[i].emoji, style: const TextStyle(fontSize: 28)),
                              const SizedBox(height: 4),
                              Text(
                                unlockedAchievements[i].name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        "$name is exploring the world with AI Wellness Pal.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              );
            }
          ),
        );
      },
    );
  }
}


