import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart'; // Add for CustomerInfo
import 'package:intl/intl.dart'; // Add for date formatting
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/revenue_cat_service.dart';
import '../utils/pro_modal_utils.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../services/achievement_service.dart';
import 'achievement_completion_page.dart';

class CustomerCenterScreen extends StatefulWidget {
  const CustomerCenterScreen({super.key});

  @override
  State<CustomerCenterScreen> createState() => _CustomerCenterScreenState();
}

class _CustomerCenterScreenState extends State<CustomerCenterScreen> {
  final _revenueCatService = RevenueCatService();
  bool _isLoading = true;
  SubscriptionStatus _status = SubscriptionStatus.none;
  CustomerInfo? _customerInfo;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
  }

  Future<void> _loadSubscriptionStatus() async {
    setState(() => _isLoading = true);
    try {
      final status = await _revenueCatService.getSubscriptionStatus();
      final info = await _revenueCatService.getCustomerInfo();
      if (mounted) {
        setState(() {
          _status = status;
          _customerInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Subscription'),
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).appBarTheme.titleTextStyle?.color ?? Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _status == SubscriptionStatus.none
              ? _buildNoSubscriptionView()
              : _buildCustomerCenterView(),
    );
  }

  Widget _buildNoSubscriptionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primaryContainer,
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_rounded, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Active Subscription',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Unlock premium features and achieve your dreams faster.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () => _showPaywall(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Upgrade to Premium', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _restorePurchases(),
              child: Text(
                'Restore Purchases',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCenterView() {
    return Column(
      children: [
        if (_status != SubscriptionStatus.none && _customerInfo != null)
           _buildActiveSubscriptionCard(),
        Expanded(
          child: CustomerCenterView(
            onDismiss: () {
              // Refresh subscription status when dismissed
              _loadSubscriptionStatus();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSubscriptionCard() {
    final entitlement = _customerInfo?.entitlements.active[RevenueCatService.proEntitlementId];
    if (entitlement == null) return const SizedBox.shrink();

    final isMonthly = entitlement.productIdentifier.contains('monthly');
    final planName = isMonthly ? 'Premium Monthly' : 'Premium Yearly';
    final expiryDate = entitlement.expirationDate;
    final formattedDate = expiryDate != null ? DateFormat.yMMMd().format(DateTime.parse(expiryDate)) : 'Unknown';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white.withOpacity(0.1) 
              : Colors.grey.shade200
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("CURRENT PLAN", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text("active", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(planName, style: TextStyle(
            fontSize: 20, 
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          )),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Renews on $formattedDate", style: TextStyle(
                fontSize: 14, 
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white70 
                    : Colors.grey.shade600
              )),
              TextButton(
                onPressed: () => _revenueCatService.manageSubscriptions(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("Cancel Subscription", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showPaywall() async {
    try {
      final result = await RevenueCatUI.presentPaywall();
      
      if (result == PaywallResult.purchased || result == PaywallResult.restored) {
        // Refresh local UI state
        await _loadSubscriptionStatus();
        
        // Notify global AppState (to update AppBar etc.)
        if (mounted) {
          Provider.of<AppState>(context, listen: false).updateProStatus(forceRefresh: true);
        }
        
        // Check for Pro achievement
        final newAchievements = await AchievementService().checkAchievements(isPro: true);
        
        if (mounted) {
          if (newAchievements.isNotEmpty) {
             for (var achievement in newAchievements) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AchievementCompletionPage(achievement: achievement),
                    fullscreenDialog: true,
                  ),
                );
             }
             // Show welcome modal after achievement modal closes
             if (mounted) ProModalUtils.showWelcomeProModal(context);
          } else {
             ProModalUtils.showWelcomeProModal(context);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        WellnessPalSnackBar.show(
          context,
          message: 'Error: $e',
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      await _revenueCatService.restorePurchases();
      
      // Refresh global state
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.updateProStatus(forceRefresh: true);
        await _loadSubscriptionStatus();
        
        if (appState.isPro) {
          // Check for Pro achievement
          final newAchievements = await AchievementService().checkAchievements(isPro: true);
          
          if (mounted) {
            if (newAchievements.isNotEmpty) {
               for (var achievement in newAchievements) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AchievementCompletionPage(achievement: achievement),
                      fullscreenDialog: true,
                    ),
                  );
               }
               // Show welcome modal after achievement modal closes
               if (mounted) ProModalUtils.showWelcomeProModal(context);
            } else {
               ProModalUtils.showWelcomeProModal(context);
            }
          }
        } else {
          WellnessPalSnackBar.show(
            context,
            message: 'Restoration complete, but no active subscriptions were found.',
            icon: Icons.info_outline_rounded,
            duration: const Duration(seconds: 4),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        WellnessPalSnackBar.show(
          context,
          message: 'Restore failed: $e',
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      }
    }
  }
}
