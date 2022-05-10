import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetyproject/pages/login_page.dart';
import 'package:safetyproject/pages/sos.dart';

void main(){
  group('main page', (){
    testWidgets('has loging page', (WidgetTester tester) async {
      await tester.pumpWidget(SosPage());

    });

  });
}