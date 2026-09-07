import 'package:flutter/material.dart';

class CustomTabSwitcher extends StatelessWidget {
  final TabController tabController;
  final List<String> tabs;
  final List<IconData>? icons;
  final double? width;
  final double height;
  final bool isAppBarMode;

  const CustomTabSwitcher({
    super.key,
    required this.tabController,
    required this.tabs,
    this.icons,
    this.width,
    this.height = 56,
    this.isAppBarMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: isAppBarMode ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Theme.of(context).cardColor // Premium Surface #322e40
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(height / 2),
        border: Theme.of(context).brightness == Brightness.dark 
            ? Border.all(color: Colors.white10, width: 1) 
            : null,
        boxShadow: [
           BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final tabWidth = availableWidth / tabs.length;
          
          return Stack(
            children: [
              // Animated Indicator
              AnimatedBuilder(
                animation: tabController.animation!,
                builder: (context, child) {
                  final double offset = tabController.animation!.value * tabWidth;
                  
                  return Positioned(
                    left: offset,
                    top: 4,
                    bottom: 4,
                    width: tabWidth,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Theme.of(context).scaffoldBackgroundColor // Match app background #1c1a27
                            : Colors.white,
                        borderRadius: BorderRadius.circular((height - 8) / 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Labels
              Row(
                children: List.generate(tabs.length, (index) {
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => tabController.animateTo(index),
                      child: Container(
                        color: Colors.transparent, // Hit test
                        alignment: Alignment.center,
                        child: AnimatedBuilder(
                          animation: tabController.animation!,
                          builder: (context, child) {
                             final isSelected = (tabController.animation!.value - index).abs() < 0.5;
                             final color = isSelected 
                                    ? Theme.of(context).colorScheme.primary
                                    : (Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.grey);
                                    
                             return Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 if (icons != null && index < icons!.length) ...[
                                   Icon(
                                     icons![index],
                                     size: 16,
                                     color: color,
                                   ),
                                   const SizedBox(width: 6),
                                 ],
                                 Text(
                                   tabs[index],
                                   style: TextStyle(
                                     fontWeight: FontWeight.bold,
                                     color: color,
                                     fontSize: 13,
                                   ),
                                 ),
                               ],
                             );
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        }
      ),
    );
  }
}
