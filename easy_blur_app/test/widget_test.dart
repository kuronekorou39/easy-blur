import 'package:flutter_test/flutter_test.dart';
import 'package:easy_blur_app/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyBlurApp());
    expect(find.text('Easy Blur'), findsOneWidget);
  });
}
