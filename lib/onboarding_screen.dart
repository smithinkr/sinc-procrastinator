import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // Required to navigate back to AppStartSwitcher

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  bool isLastPage = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Match this to the background color of your image edges
      backgroundColor: Colors.white, 
      body: Stack(
        children: [
          // 1. The Image Slider
          PageView(
            controller: _controller,
            onPageChanged: (index) {
              setState(() => isLastPage = (index == 2)); // Assumes 3 images
            },
            children: [
              _buildFullPageHint('assets/1.png'),
              _buildFullPageHint('assets/2.png'),
              _buildFullPageHint('assets/3.png'),
            ],
          ),

          // 🔵 NEW: The Progress Dots
          Container(
            alignment: const Alignment(0, 0.75), // Positions dots above the buttons
            child: SmoothPageIndicator(
              controller: _controller,
              count: 3, // Match this to your number of images
              effect: const WormEffect(
                spacing: 16,
                dotColor: Colors.black12,
                activeDotColor: Colors.indigo,
                dotHeight: 12,
                dotWidth: 12,
              ),
              // Allows users to click dots to jump to a page
              onDotClicked: (index) => _controller.animateToPage(
                index,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeIn,
              ),
            ),
          ),

          // 2. Navigation Overlay
          SafeArea(
            child: Container(
              alignment: const Alignment(0, 0.9),
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // SKIP BUTTON
                  TextButton(
                    onPressed: () => _completeOnboarding(context),
                    child: const Text(
                      "SKIP", 
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)
                    ),
                  ),

                  // NEXT / GET STARTED BUTTON
                  isLastPage 
                    ? ElevatedButton(
                        onPressed: () => _completeOnboarding(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text("GET STARTED"),
                      )
                    : IconButton(
                        onPressed: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        ),
                        icon: const Icon(Icons.arrow_forward_ios, color: Colors.indigo),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build images with the correct aspect ratio protection
  Widget _buildFullPageHint(String imagePath) {
    return Center(
      child: Image.asset(
        imagePath,
        fit: BoxFit.contain, // Ensures your baked-in text is never cut off
      ),
    );
  }

 void _completeOnboarding(BuildContext context) async {
  // 1. Save the flag to the phone's disk
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_done', true);
  
  // 🛡️ THE SAFETY GUARD:
  // This checks if the Onboarding screen is still "alive" in the UI tree.
  // We use 'context.mounted' for modern Flutter versions.
  if (!context.mounted) return;

  // 2. Since we are still mounted, it is now safe to use the context
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => const AppStartSwitcher(
        userInitial: "", 
        isReturning: true, // 👈 ADD THIS LINE
      ),
    ),
  );
}
}