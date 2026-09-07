import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ActivityStatsScreen extends StatelessWidget {
  const ActivityStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Garden Insights', 
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).textTheme.titleLarge?.color,
          )
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          final waterRate = appState.waterRate;
          final totalPlants = appState.gardenCells.where((c) => c > 0).length;
          final fullyBloomed = appState.gardenCells.where((c) => c == 4).length;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: Theme.of(context).brightness == Brightness.dark 
                          ? [
                              Colors.green.shade900.withOpacity(0.3), 
                              Theme.of(context).cardColor
                            ]
                          : [Colors.green.shade50, Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.green.withOpacity(0.2) 
                          : Colors.green.shade100
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.psychology_outlined, size: 48, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(
                        'Garden Vitality',
                        style: TextStyle(fontSize: 16, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(waterRate * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$totalPlants Active Plants • $fullyBloomed Fully Bloomed',
                        style: TextStyle(
                          fontSize: 14, 
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white70 
                              : Colors.grey.shade600
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                const SizedBox(height: 32),
                
                // Growth Stages
                const Text(
                  'Growth Guide',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildInsightRow(
                  context, 
                  Icons.fiber_manual_record, 
                  'Seed', 
                  'Starting a new habit or dream.',
                  Colors.green.shade300,
                ),
                _buildInsightRow(
                  context, 
                  Icons.eco_rounded, 
                  'Sprout', 
                  'Early progress and consistency.',
                  Colors.green.shade400,
                ),
                _buildInsightRow(
                  context, 
                  Icons.local_florist_rounded, 
                  'Plant (Level 3)', 
                  'A well-established daily commitment.',
                  Colors.green.shade500,
                ),
                _buildInsightRow(
                  context, 
                  Icons.auto_awesome_rounded, 
                  'Bloom (Level 4)', 
                  'Mastery and sustained growth!',
                  Colors.green.shade700,
                ),
                _buildInsightRow(
                  context, 
                  Icons.grass_rounded, 
                  'Lush Green (7 Days)', 
                  'Hit a 7-day streak to turn the garden bed lush.',
                  Colors.lightGreen,
                ),
                _buildInsightRow(
                  context, 
                  Icons.filter_vintage_rounded, 
                  'Flower Bloom (14 Days)', 
                  '14+ day streaks unlock wild flowers across the garden.',
                  Colors.pinkAccent,
                ),

                const SizedBox(height: 32),
                
                // How to Water
                const Text(
                  'How to Water',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildWateringRule(context, 'Daily Check-in', 'Grow a random plant stage', '+ Water'),
                _buildWateringRule(context, 'Add Memory/Dream', 'Give a growth boost', '++ Water'),
                _buildWateringRule(context, 'Missed Day', 'Streak -1 & -50 Points', '-1 & -Water'),

                const SizedBox(height: 32),
                
                // Garden Protection
                const Text(
                  'Garden Protection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.pink.withOpacity(0.1) 
                        : Colors.pink.shade50.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.pink.withOpacity(0.2) 
                          : Colors.pink.shade50
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pest Control', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                Text('Drag the spray to clear pests', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Pests like caterpillars (🐛) can occasionally attack your plants when you view your full garden. Drag the pesticide bottle from the header and drop it onto the pest to protect your growth!',
                        style: TextStyle(
                          fontSize: 14, 
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87, 
                          height: 1.5
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48), // Bottom spacing
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildInsightRow(BuildContext context, IconData icon, String title, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                Text(
                  desc, 
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white70 
                        : Colors.grey.shade600, 
                    fontSize: 13
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWateringRule(BuildContext context, String title, String effect, String impact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.blue.withOpacity(0.1) 
            : Colors.blue.shade50.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.blue.withOpacity(0.2) 
              : Colors.blue.shade50
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop_rounded, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).textTheme.bodyLarge?.color)),
                Text(
                  effect, 
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white70 
                        : Colors.grey.shade600, 
                    fontSize: 12
                  )
                ),
              ],
            ),
          ),
          Text(impact, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        ],
      ),
    );
  }
}

