import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import 'package:procrastinator/utils/logger.dart';
import '../services/storage_service.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isRequesting = false;

  // --- 1. THE UNIFIED BETA ENGINE ---
  Future<void> _handleBetaRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isRequesting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance.collection('beta_requests').doc(user.uid).set({
        'email': user.email,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'deviceName': 'S23 FE / OnePlus',
      }, SetOptions(merge: true));

      messenger.showSnackBar(
        SnackBar(
          content: const Text("Beta request sent. Reviewing account..."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.indigo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Cloud Error: $e"), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }
  

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final isDark = settings.isDarkMode;
    final user = FirebaseAuth.instance.currentUser;
    final bool isApproved = user != null && settings.isBetaApproved;
    _getThemeColor(settings.themeColor);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("S.INC Workspace", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        children: [
          // --- SECTION 1: IDENTITY PASS ---
          _buildSectionTitle("IDENTITY PASS", isDark),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
            ),
            child: Column(
              children: [
                if (user == null) ...[
                  const Icon(Icons.face_unlock_outlined, size: 40, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("Anonymous Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await SyncService().signInWithGoogle();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text("LOG IN WITH S.INC", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24, backgroundColor: Colors.indigo,
                        child: Text((user.displayName ?? "U")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.displayName ?? "S.INC Member", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(user.email ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await SyncService().signOut();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (!settings.isBetaApproved) ...[
                    ElevatedButton.icon(
                      onPressed: _isRequesting ? null : _handleBetaRequest, 
                      icon: _isRequesting 
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo))
                          : const Icon(Icons.bolt, size: 14),
                      label: Text(_isRequesting ? "SENDING..." : "REQUEST BETA ACCESS", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.withValues(alpha: 0.1), foregroundColor: Colors.indigo,
                        elevation: 0, minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow("STATUS", "PENDING REVIEW", Colors.orange),
                  ] else ...[
                    _buildStatusRow("INTELLIGENCE", "VERIFIED", Colors.green),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),

          // --- SECTION 2: S.INC INTELLIGENCE ---
          _buildSectionTitle("S.INC INTELLIGENCE", isDark),
          const SizedBox(height: 12),
          Column(
            children: [
              if (!isApproved)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text("GET BETA ACCESS FOR AI SMARTNESS", style: TextStyle(color: Colors.indigoAccent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: isApproved ? 1.0 : 0.4,
                    child: IgnorePointer(
                      ignoring: !isApproved,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Smart Processing", style: TextStyle(fontWeight: FontWeight.bold)),
                                Switch(
                                  value: settings.isAiEnabled,
                                  activeTrackColor: Colors.indigo,
                                  onChanged: (val) => settings.toggleAiFeatures(val),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text("AI Personality Depth", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.grey)),
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
                            Center(child: Text(_getPersonalityHint(settings.aiCreativity), style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.white38 : Colors.grey[600]))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isApproved)
                    Positioned(top: 20, right: 20, child: Icon(Icons.lock_outline, color: isDark ? Colors.white12 : Colors.black12, size: 20)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // --- SECTION 3: SYSTEMS (HUD & BRIEFING) ---
          _buildSectionTitle("SYSTEMS", isDark),
          const SizedBox(height: 12),
          _buildSystemCard(
            icon: Icons.alarm,
            title: "Morning Briefing",
            subtitle: "${settings.briefHour.toString().padLeft(2, '0')}:${settings.briefMinute.toString().padLeft(2, '0')}",
            isDark: isDark,
            onTap: () async {
              final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: settings.briefHour, minute: settings.briefMinute));
              if (picked != null) await settings.updateBriefTime(picked.hour, picked.minute);
            },
          ),
          const SizedBox(height: 12),
          _buildSystemCard(
            icon: Icons.vignette_outlined,
            title: "Home Screen HUD",
            subtitle: "Today at a Glance",
            isDark: isDark,
            trailing: Switch(
              value: settings.isHudEnabled,
              activeTrackColor: Colors.indigo,
              onChanged: (val) => settings.toggleHud(val),
            ),
          ),
          const SizedBox(height: 32),

          // --- SECTION 4: VISUAL THEME ---
          _buildSectionTitle("VISUAL THEME", isDark),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildThemeOption("indigo", Colors.indigo, settings),
              _buildThemeOption("emerald", Colors.teal, settings),
              _buildThemeOption("rose", Colors.pink, settings),
              _buildThemeOption("cyan", Colors.cyan, settings),
            ],
          ),
          const SizedBox(height: 20),
          _buildSystemCard(
            icon: Icons.dark_mode_outlined,
            title: "Dark Mode",
            subtitle: "Inky Interface",
            isDark: isDark,
            trailing: Switch(
              value: settings.isDarkMode,
              activeTrackColor: Colors.indigo,
              onChanged: (val) => settings.updateTheme(settings.themeColor, val),
            ),
          ),
          const SizedBox(height: 60),
          _buildDangerZone(context),
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildSectionTitle(String title, bool isDark) => Text("  $title", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5));

  Widget _buildStatusRow(String label, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
          Text(status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSliderLabel(String text, bool isActive, bool isDark) => Text(text, style: TextStyle(fontSize: 9, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.indigo : (isDark ? Colors.white24 : Colors.grey[400])));

  Widget _buildSystemCard({required IconData icon, required String title, required String subtitle, required bool isDark, Widget? trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDark ? Colors.white70 : Colors.indigo, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey[500])),
              ]),
            ),
            trailing ?? Icon(Icons.chevron_right, size: 16, color: isDark ? Colors.white24 : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(String name, Color color, SettingsService settings) {
    bool isSelected = settings.themeColor == name;
    return GestureDetector(
      onTap: () => settings.updateTheme(name, settings.isDarkMode),
      child: Container(
        width: 44, height: 44, margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: isSelected ? Border.all(color: settings.isDarkMode ? Colors.white : Colors.black26, width: 2) : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }
  // 2. Add this Section to your Settings List (UI)
Widget _buildDangerZone(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(left: 16, top: 24, bottom: 8),
        child: Text("DANGER ZONE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
      ),
      ListTile(
        leading: const Icon(Icons.delete_forever, color: Colors.red),
        title: const Text("Delete My Account", style: TextStyle(color: Colors.red)),
        subtitle: const Text("Permanently erase all your S.INC data"),
        onTap: () => _handleAccountDeletion(context),
      ),
    ],
  );
}

  Color _getThemeColor(String theme) {
    switch (theme.toLowerCase()) {
      case 'emerald': return const Color(0xFF047857);
      case 'rose': return const Color(0xFFBE123C);
      case 'cyan': return const Color(0xFF0E7490);
      default: return const Color(0xFF4338CA);
    }
  }

  String _getPersonalityHint(double val) {
    if (val <= 0.3) return "Focused essential subtasks.";
    if (val < 0.8) return "Balanced practical steps.";
    return "Deep project analysis.";
  }
  // 1. THE MAIN TRIGGER
  Future<void> _handleAccountDeletion(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(context);
    if (!context.mounted) return; // 🔥 Add this guard here
    if (confirmed == true) {
      await _triggerNuclearWipe(context);
    }
  }
  

  // 2. THE ACTUAL DELETION ENGINE
  Future<void> _triggerNuclearWipe(BuildContext context) async {
    if (!context.mounted) return;

    try {
      // Show Loader
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // This now calls the re-authentication flow we added to SyncService
      await SyncService().deleteUserAccount(); 
      await StorageService.clearAll(); 

      if (!context.mounted) return;
      
      // Success: Close loader and navigate back to the very start
      Navigator.of(context).popUntil((route) => route.isFirst);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("S.INC: Account and data permanently erased."),
          backgroundColor: Colors.indigo,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close the loading spinner

      // 🔥 THE FIX: If Google demands a fresh login, we show the explanation FIRST
      if (e.toString().contains("requires-recent-login") || e.toString().contains("recent-login-required")) {
        _showReauthExplanation(context);
      } else {
        L.d("🚨 Deletion Error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // 3. THE RE-AUTH EXPLANATION (Solves the UI Race Condition)
  void _showReauthExplanation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Security Verification"),
        content: const Text("Google requires you to select your account again to verify this permanent deletion."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close this dialog first
              _triggerNuclearWipe(context); // Now trigger the Google popup safely
            },
            child: const Text("VERIFY & DELETE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 4. THE INITIAL CONFIRMATION
  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account?"),
        content: const Text("This is permanent. All your tasks and cloud data will be erased. S.INC cannot undo this."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("DELETE EVERYTHING", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}