import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/challenge_step.dart';
import '../utils/wellnesspal_snackbar.dart';

void _showMicroActionBottomSheet(BuildContext context, AppState appState) {
    // Get the first incomplete step
    ChallengeStep? nextStepNullable;
    String? dreamTitle;
    String? dreamId;
    
    for (var dream in appState.dreams) {
      for (var step in dream.steps) {
        if (!step.isCompleted) {
          nextStepNullable = step;
          dreamTitle = dream.title;
          dreamId = dream.id;
          break;
        }
      }
      if (nextStepNullable != null) break;
    }

    if (nextStepNullable == null) return;
    
    final nextStep = nextStepNullable; // Now non-nullable

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        bool isLoading = false;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              margin: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Theme.of(context).cardColor 
                      : Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    
                    // Dream tag
                    if (dreamTitle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.1) 
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dreamTitle.toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white70 
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    
                    // Timer icon
                    Icon(
                      Icons.timer_outlined,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${nextStep.durationMinutes} MIN',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Task title
                    Text(
                      nextStep.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Complete button
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : () async {
                          if (dreamId != null) {
                            setState(() => isLoading = true);
                            try {
                              await appState.toggleStepCompletion(dreamId, nextStep.id);
                              if (context.mounted) {
                                Navigator.pop(context);
                                WellnessPalSnackBar.show(
                                  context,
                                  message: '🎉 Micro-action completed!',
                                  icon: Icons.check_circle_rounded,
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setState(() => isLoading = false);
                              }
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).brightness == Brightness.dark 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.black,
                          foregroundColor: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.black 
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                        child: isLoading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.black 
                                    : Colors.white,
                              ),
                            )
                          : Text(
                              'I did it!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.black 
                                    : Colors.white,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Skip button
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        WellnessPalSnackBar.show(
                          context,
                          message: "We'll skip this one for now!",
                          icon: Icons.refresh_rounded,
                        );
                      },
                      icon: Icon(Icons.refresh_rounded, size: 18, color: Colors.grey.shade600),
                      label: Text(
                        "Give me something easier",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }
