import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class LocationPickerSheet extends StatefulWidget {
  final Point? initialPoint;
  const LocationPickerSheet({this.initialPoint, super.key});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  CircleAnnotationManager? _circleAnnotationManager;
  Point? _selectedPoint;
  MapboxMap? _mapboxMap;
  
  // Search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;
  final String _accessToken = "YOUR_MAPBOX_ACCESS_TOKEN";

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    
    // Handle Initial Point
    if (widget.initialPoint != null) {
      _selectedPoint = widget.initialPoint;
      await _circleAnnotationManager?.create(CircleAnnotationOptions(
        geometry: widget.initialPoint!,
        circleRadius: 10.0,
        circleColor: Colors.red.value,
        circleStrokeColor: Colors.white.value,
        circleStrokeWidth: 2.0,
      ));
      
      await mapboxMap.flyTo(
        CameraOptions(center: widget.initialPoint!, zoom: 12, pitch: 0),
        MapAnimationOptions(duration: 0) // Instant move
      );
    }

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
  }
  
  void _onMapTap(MapContentGestureContext context) async {
    final point = context.point;
    setState(() {
      _selectedPoint = point;
    });
    
    await _circleAnnotationManager?.deleteAll();
    await _circleAnnotationManager?.create(CircleAnnotationOptions(
      geometry: point,
      circleRadius: 10.0,
      circleColor: Colors.red.value,
      circleStrokeColor: Colors.white.value,
      circleStrokeWidth: 2.0,
    ));
  }
  
  void _startAutoCloseTimer() {
    _cancelAutoCloseTimer();
    _searchTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _searchController.text.isEmpty) {
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  void _cancelAutoCloseTimer() {
    _searchTimer?.cancel();
    _searchTimer = null;
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _startAutoCloseTimer();
      } else {
        _cancelAutoCloseTimer();
        _searchController.clear();
      }
    });
  }

  Future<void> _searchPlace(String query) async {
    _cancelAutoCloseTimer(); // Stop timer while searching
    if (query.trim().isEmpty) return;
    
    // Hide keyboard
    FocusScope.of(context).unfocus();

    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$_accessToken&limit=1'
    );
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final coords = data['features'][0]['geometry']['coordinates'];
          final lng = coords[0];
          final lat = coords[1];
          
          final point = Point(coordinates: Position(lng, lat));
          
          await _mapboxMap?.flyTo(
            CameraOptions(center: point, zoom: 12, pitch: 0),
            MapAnimationOptions(duration: 2000)
          );
          
          setState(() {
            _selectedPoint = point;
          });
          
          await _circleAnnotationManager?.deleteAll();
          await _circleAnnotationManager?.create(CircleAnnotationOptions(
            geometry: point,
            circleRadius: 10.0,
            circleColor: Colors.red.value,
            circleStrokeColor: Colors.white.value,
            circleStrokeWidth: 2.0,
          ));
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: "Search location...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 18),
                onChanged: (value) {
                  _startAutoCloseTimer();
                  setState(() {});
                },
                onSubmitted: _searchPlace,
              )
            : const Text("Pin Exact Location", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: _isSearching 
          ? [] 
          : [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _selectedPoint == null 
                    ? null 
                    : () => Navigator.pop(context, _selectedPoint),
              ),
              const SizedBox(width: 8),
            ],
      ),
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            onTapListener: _onMapTap,
            styleUri: MapboxStyles.OUTDOORS,
            cameraOptions: CameraOptions(
              zoom: 1.5, 
              center: Point(coordinates: Position(0, 20))
            ),
          ),
        ],
      ),
    );
  }
}
