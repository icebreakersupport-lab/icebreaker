import 'package:flutter_test/flutter_test.dart';
import 'package:icebreaker/app.dart';

void main() {
  testWidgets('App smoke test — IcebreakerApp renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const IcebreakerApp());
    // The app should render at least one widget.
    expect(find.byType(IcebreakerApp), findsOneWidget);
  });
}
