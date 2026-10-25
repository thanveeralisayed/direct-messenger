import 'package:flutter_test/flutter_test.dart';
import 'package:direct/main.dart';

void main() {
  testWidgets('DirectApp initial load smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DirectApp());
    expect(find.byType(DirectApp), findsOneWidget);
  });
}
