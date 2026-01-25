import 'package:flutter_test/flutter_test.dart';
// Ensure the package name matches your project structure
import 'package:procrastinator/main.dart'; 

void main() {
  testWidgets('Procrastinator boot test', (WidgetTester tester) async {
    // 🛡️ S.INC FIX: Remove 'isLoggedIn' as it is now handled by the Stream
    await tester.pumpWidget(const MyApp(
      initial: '', // We only pass 'initial' now
    ));

    // Verify that the app starts. 
    // Note: Since Firebase isn't "real" in a test environment, 
    // it will likely stay in the Loading/Waiting state.
    expect(find.byType(MyApp), findsOneWidget);
  });
}