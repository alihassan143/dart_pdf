/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Document.debug = true;
  });

  group('AutoPageBreak', () {
    test('AutoPageBreak wraps oversized widget', () async {
      final pdf = Document();

      pdf.addPage(MultiPage(
        build: (Context context) => [
          // A widget that's larger than a page
          AutoPageBreak(
            child: Container(
              height: 1500, // Much larger than a typical page
              decoration: const BoxDecoration(
                color: PdfColors.blue100,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top of the container'),
                  Text('Middle of the container'),
                  Text('Bottom of the container'),
                ],
              ),
            ),
          ),
        ],
      ));

      final bytes = await pdf.save();
      expect(bytes.length, greaterThan(0));

      final file = File('auto_page_break_test.pdf');
      await file.writeAsBytes(bytes);
    });

    test('MultiPage with autoPageBreak handles oversized widgets', () async {
      final pdf = Document();

      pdf.addPage(MultiPage(
        autoPageBreak: true, // Enable automatic page breaking
        maxPages: 50, // Increase max pages for testing
        build: (Context context) => [
          Text('Before oversized widget'),
          // This container would normally throw an exception
          Container(
            height: 1000, // Smaller height for easier testing
            decoration: const BoxDecoration(
              color: PdfColors.green100,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Top'),
                Text('Bottom'),
              ],
            ),
          ),
          Text('After oversized widget'),
        ],
      ));

      final bytes = await pdf.save();
      expect(bytes.length, greaterThan(0));

      final file = File('multipage_auto_break_test.pdf');
      await file.writeAsBytes(bytes);
    });

    test('BreakableColumn handles mixed content', () async {
      final pdf = Document();

      pdf.addPage(MultiPage(
        build: (Context context) => [
          BreakableColumn(
            spacing: 10,
            children: [
              Container(
                height: 100,
                color: PdfColors.red100,
                child: Center(child: Text('Small widget 1')),
              ),
              Container(
                height: 1200, // Larger than a page
                color: PdfColors.yellow100,
                child: Center(child: Text('Large widget that will break')),
              ),
              Container(
                height: 100,
                color: PdfColors.green100,
                child: Center(child: Text('Small widget 2')),
              ),
            ],
          ),
        ],
      ));

      final bytes = await pdf.save();
      expect(bytes.length, greaterThan(0));

      final file = File('breakable_column_test.pdf');
      await file.writeAsBytes(bytes);
    });

    test('Without autoPageBreak, oversized widget throws', () async {
      final pdf = Document();

      pdf.addPage(MultiPage(
        build: (Context context) => [
          Container(
            height: 2000, // Oversized
            color: PdfColors.blue100,
          ),
        ],
      ));

      // This should throw an exception since autoPageBreak is false
      expect(
        () async => await pdf.save(),
        throwsA(isA<Exception>()),
      );
    });

    test('AutoPageBreak with nested widgets', () async {
      final pdf = Document();

      pdf.addPage(MultiPage(
        build: (Context context) => [
          AutoPageBreak(
            child: Column(
              children: List.generate(
                100,
                (index) => Container(
                  height: 50,
                  margin: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color:
                        index % 2 == 0 ? PdfColors.blue50 : PdfColors.green50,
                    border: Border.all(),
                  ),
                  child: Center(child: Text('Item $index')),
                ),
              ),
            ),
          ),
        ],
      ));

      final bytes = await pdf.save();
      expect(bytes.length, greaterThan(0));

      final file = File('auto_page_break_nested_test.pdf');
      await file.writeAsBytes(bytes);
    });
  });
}
