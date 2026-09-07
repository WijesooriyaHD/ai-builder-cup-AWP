import 'package:flutter/material.dart';

class WellnessPalSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? iconColor,
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final backgroundColor = isError 
        ? const Color(0xFFFF5252) 
        : (isDark ? Theme.of(context).cardColor : Colors.white);
        
    final textColor = isError 
        ? Colors.white 
        : (isDark ? Colors.white : Colors.black87);
        
    final defaultIconColor = isError 
        ? Colors.white 
        : (isDark ? Colors.white70 : Colors.black87);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: iconColor ?? defaultIconColor,
                size: 20,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.1)) : BorderSide.none,
        ),
        elevation: 8,
        duration: duration,
      ),
    );
  }
}
