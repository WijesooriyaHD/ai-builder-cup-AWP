import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import '../../models/travel_memory.dart';
import 'package:country_picker/country_picker.dart';
import '../../providers/app_state.dart';
import '../../utils/wellnesspal_snackbar.dart';
import '../../utils/pro_modal_utils.dart';
import '../add_memory_sheet.dart';

class PlacesTabWidget extends StatefulWidget {
  const PlacesTabWidget({super.key});

  @override
  State<PlacesTabWidget> createState() => _PlacesTabWidgetState();
}

class _PlacesTabWidgetState extends State<PlacesTabWidget> {
  bool _isProcessing = false;

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Delete Memory?"),
            content: const Text(
                "This action cannot be undone. Are you sure you want to delete this travel memory?"),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        ) ??
        false;
  }

  void _editMemory(TravelMemory memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddMemorySheet(
          memoryToEdit: memory,
          onAdd: (placeName, lat, lng, note, photos, isPublic, {id}) async {
            try {
              final updated = TravelMemory(
                  id: memory.id,
                  place: placeName,
                  latitude: lat == 0.0 ? memory.latitude : lat,
                  longitude: lng == 0.0 ? memory.longitude : lng,
                  visitedDate: memory.visitedDate,
                  memory: "",
                  note: note,
                  photos: photos,
                  isPublic: isPublic);

              await Provider.of<AppState>(context, listen: false)
                  .updateTravelMemory(updated);
             
              if (mounted) {
                WellnessPalSnackBar.show(context,
                    message: "Memory updated successfully",
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.green);
              }
            } catch (e) {
              if (mounted) {
                WellnessPalSnackBar.show(context,
                    message: "Failed to update memory: $e", isError: true);
              }
              rethrow;
            }
          },
        );
      },
    );
  }

  final String _accessToken = "YOUR_MAPBOX_ACCESS_TOKEN";

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.travelMemories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset(
                  'assets/images/exploring.json',
                  height: 280,
                  width: 280,
                  repeat: true,
                ),
                const SizedBox(height: 24),
                Text('No Places Yet',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('Tap + to add your first travel memory',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }
        // Check for limit
        final isLimitReached = !appState.isPro && appState.travelMemories.length >= 3;

        return RefreshIndicator(
          onRefresh: () async {
            await appState.fetchPublicMemories();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: appState.travelMemories.length + (isLimitReached ? 1 : 0),
            itemBuilder: (context, index) {
              if (isLimitReached && index == 0) {
                return GestureDetector(
                  onTap: () => ProModalUtils.showTravelLimitModal(context),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade400, Colors.deepOrange.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Travel Limit Reached",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Upgrade to add more places",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "Upgrade",
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final reversedIndex = index - (isLimitReached ? 1 : 0);
              final memory = appState.travelMemories.reversed.toList()[reversedIndex];
              
              String flag = "📍";
              try {
                final countryName = memory.place.contains(",") ? memory.place.split(",").last.trim() : memory.place;
                final country = CountryService().findByName(countryName);
                if (country != null) {
                  flag = country.flagEmoji;
                }
              } catch (_) {}

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          shape: BoxShape.circle, // Circular for flag
                      ),
                      child: Text(
                        flag,
                        style: const TextStyle(fontSize: 24),
                      )
                  ),
                  title: Text(memory.place,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      if (memory.memory.isNotEmpty)
                        Text(memory.memory,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          '${memory.latitude.toStringAsFixed(4)}, ${memory.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 100,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.blueGrey),
                          onPressed: () => _editMemory(memory),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () async {
                            final confirmed = await _confirmDelete(context);
                            if (confirmed) {
                              setState(() => _isProcessing = true);
                              try {
                                await appState.deleteTravelMemory(memory.id);
                                if (mounted) {
                                  WellnessPalSnackBar.show(context,
                                      message: "Memory deleted",
                                      icon: Icons.delete_forever);
                                }
                              } catch (e) {
                                if (mounted) {
                                  WellnessPalSnackBar.show(context,
                                      message: "Failed to delete: $e",
                                      isError: true);
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isProcessing = false);
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  onLongPress: () => _editMemory(memory),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
