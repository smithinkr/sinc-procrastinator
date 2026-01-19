import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final isDark = settings.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Settings", 
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // --- HEADER SECTION ---
          Center(
            child: Column(
              children: [
                Icon(Icons.tune, size: 48, color: isDark ? Colors.white70 : Colors.indigo),
                const SizedBox(height: 12),
                Text(
                  "Customize Experience",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                ),
                Text(
                  "Make it yours",
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // --- AI SECTION ---
          _buildSectionTitle("INTELLIGENCE", isDark),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: isDark ? Colors.white70 : Colors.indigo),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Enable AI Magic", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                            Text("Auto-detect dates & subtasks", style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey[500])),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: settings.isAiEnabled,
                      activeTrackColor: Colors.indigo,
                      onChanged: (val) => settings.toggleAiFeatures(val),
                    )
                  ],
                ),
                if (settings.isAiEnabled) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                  const Text("AI Personality", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Slider(
                    value: settings.aiCreativity,
                    min: 0.1, max: 1.0, divisions: 9,
                    activeColor: Colors.indigo,
                    onChanged: (val) => settings.updateAiCreativity(val),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSliderLabel("Basic", settings.aiCreativity <= 0.3, isDark),
                      _buildSliderLabel("Standard", settings.aiCreativity > 0.3 && settings.aiCreativity < 0.8, isDark),
                      _buildSliderLabel("Deep", settings.aiCreativity >= 0.8, isDark),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _getPersonalityHint(settings.aiCreativity),
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.white38 : Colors.grey[600]),
                    ),
                  ),
                ]
              ],
            ),
          ),
          
          const SizedBox(height: 32),

          // --- NOTIFICATIONS SECTION ---
          _buildSectionTitle("NOTIFICATIONS", isDark),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.alarm, color: isDark ? Colors.white70 : Colors.indigo),
              title: Text("Morning Briefing Time", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text("${settings.briefHour.toString().padLeft(2, '0')}:${settings.briefMinute.toString().padLeft(2, '0')}"),
              trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white24 : Colors.grey[400]),
              onTap: () async {
                // We use the context from the build method only for the initial dialog
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: settings.briefHour, minute: settings.briefMinute),
                );

                if (picked != null) {
                  // 1. PERFORM ASYNC WORK
                  await settings.updateBriefTime(picked.hour, picked.minute);
                  await NotificationService().updateNotifications(
                    briefHour: picked.hour,
                    briefMinute: picked.minute,
                  );

                  // 2. THE GUARD (Fixing the warnings)
                  if (!mounted) return;

                  // 3. USE STATE-LEVEL CONTEXT
                  // By using 'this.context', Flutter knows this check is tied to the State life.
                  final String timeLabel = picked.format(this.context);
                  
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text("Morning brief set for $timeLabel"),
                      backgroundColor: isDark ? Colors.indigo : Colors.black87,
                    ),
                  );
                }
              },
            ),
          ),
          
          const SizedBox(height: 32),

          // --- APPEARANCE SECTION ---
          _buildSectionTitle("APPEARANCE", isDark),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildThemeOption("indigo", Colors.indigo, settings),
                const SizedBox(width: 12),
                _buildThemeOption("emerald", Colors.teal, settings),
                const SizedBox(width: 12),
                _buildThemeOption("rose", Colors.pink, settings),
                const SizedBox(width: 12),
                _buildThemeOption("cyan", Colors.cyan, settings),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.dark_mode_outlined, color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 12),
                    Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  ],
                ),
                Switch(
                  value: settings.isDarkMode,
                  activeTrackColor: Colors.indigo,
                  onChanged: (val) => settings.updateTheme(settings.themeColor, val),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(title, style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _buildSliderLabel(String text, bool isActive, bool isDark) {
    return Text(text, style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.indigo : (isDark ? Colors.white24 : Colors.grey[400])));
  }

  String _getPersonalityHint(double val) {
    if (val <= 0.3) return "Essential subtasks. High-level overview.";
    if (val < 0.8) return "Standard breakdown. Practical actionable steps.";
    return "Deep Analysis. Exhaustive subtask mapping for complex projects.";
  }

  Widget _buildThemeOption(String name, Color color, SettingsService settings) {
    bool isSelected = settings.themeColor == name;
    return GestureDetector(
      onTap: () => settings.updateTheme(name, settings.isDarkMode),
      child: Container(
        width: 50, height: 50, margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.white, width: 2) : null),
        child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}