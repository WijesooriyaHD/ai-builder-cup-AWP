import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../services/revenue_cat_service.dart';
import '../utils/wellnesspal_snackbar.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _revenueCatService = RevenueCatService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // RevenueCat Paywall
            PaywallView(
              onRestoreCompleted: (CustomerInfo customerInfo) {
                // Check if user now has access
                _checkAccessAndDismiss();
              },
              onPurchaseCompleted: (CustomerInfo customerInfo, StoreTransaction storeTransaction) {
                // Purchase successful
                _checkAccessAndDismiss();
              },
              onDismiss: () {
                // User dismissed paywall
                Navigator.of(context).pop();
              },
            ),
            
            // Close button
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAccessAndDismiss() async {
    final hasAccess = await _revenueCatService.hasProAccess(forceRefresh: true);
    if (hasAccess && mounted) {
      // Update global state
      Provider.of<AppState>(context, listen: false).updateProStatus(forceRefresh: true);

      // Show success message
      WellnessPalSnackBar.show(
        context,
        message: '🎉 Welcome to AI Wellness Pal Premium!',
        icon: Icons.auto_awesome_rounded,
        iconColor: const Color(0xFFFF6B9D),
        duration: const Duration(seconds: 3),
      );
      
      // Dismiss paywall
      Navigator.of(context).pop(true);
    }
  }
}

/// Helper function to present paywall modally
Future<bool?> showPaywall(BuildContext context) async {
  return await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (context) => const PaywallScreen(),
      fullscreenDialog: true,
    ),
  );
}

/// Alternative: Present paywall using RevenueCat UI helper
Future<PaywallResult> presentPaywallModal() async {
  return await RevenueCatUI.presentPaywall();
}
