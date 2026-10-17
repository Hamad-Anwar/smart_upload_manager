import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager_example/main.dart';

void main() {
  testWidgets('Renders SmartUploadApp initially', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartUploadApp());
    expect(find.byType(SmartUploadApp), findsOneWidget);
    expect(find.text('Pick 1 File'), findsOneWidget);
  });
}
