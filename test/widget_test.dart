import 'package:flutter_test/flutter_test.dart';
import 'package:procrastinator/main.dart';

void main() {
  testWidgets('Procrastinator boot test', (WidgetTester tester) async {
    // 🔥 THE FIX: We provide the required parameters to MyApp
    await tester.pumpWidget(const MyApp(
      isLoggedIn: false, 
      initial: '',
    ));

    // Verify that the app at least starts on the HomeScreen
    // (Assuming your HomeScreen has the title 'Procrastinator')
    expect(find.text('Procrastinator'), findsOneWidget);
  });
}