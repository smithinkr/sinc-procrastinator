import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

enum IdentityStatus { connecting, welcome, dashboard }

class IdentityCard extends StatefulWidget {
  final User? user;
  final bool isApproved;
  final VoidCallback onRequestBeta;
  final VoidCallback onSignOut;

  const IdentityCard({
    super.key,
    this.user,
    required this.isApproved,
    required this.onRequestBeta,
    required this.onSignOut,
  });

  @override
  State<IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<IdentityCard> {
  IdentityStatus _status = IdentityStatus.connecting;

  @override
  void initState() {
    super.initState();
    _playSequence();
  }

  void _playSequence() async {
    if (widget.user == null) return;
    
    // Phase 1: Connecting Handshake
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _status = IdentityStatus.welcome);
    
    // Phase 2: Personalization Beat
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      HapticFeedback.lightImpact(); // Subtle "Welcome" haptic
      setState(() => _status = IdentityStatus.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuart,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (widget.user == null) {
      return const Column(
        key: ValueKey('logged_out'),
        children: [
          Icon(Icons.lock_outline, color: Colors.grey, size: 32),
          SizedBox(height: 12),
          Text("Sign in to check Beta Status", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      );
    }

    switch (_status) {
      case IdentityStatus.connecting:
        return const Column(
          key: ValueKey('connecting'),
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 12),
            Text("Verifying Identity...", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        );

      case IdentityStatus.welcome:
        return Column(
          key: const ValueKey('welcome'),
          children: [
            const Icon(Icons.auto_awesome, color: Colors.indigoAccent, size: 32),
            const SizedBox(height: 12),
            Text("Welcome, ${widget.user!.displayName?.split(' ')[0]}!", 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        );

      case IdentityStatus.dashboard:
        return Column(
          key: const ValueKey('dashboard'),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: NetworkImage(widget.user!.photoURL ?? ''),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user!.displayName ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(widget.isApproved ? "✨ Approved Member" : "Invitation Pending", 
                        style: TextStyle(fontSize: 11, color: widget.isApproved ? Colors.indigoAccent : Colors.grey)),
                    ],
                  ),
                ),
                IconButton(onPressed: widget.onSignOut, icon: const Icon(Icons.logout, size: 18, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            if (!widget.isApproved)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onRequestBeta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white10 : Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("REQUEST BETA ACCESS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
    }
  }
}