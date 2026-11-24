import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'records.dart';

Future<String?> saveFile(String name, Uint8List bytes) =>
    FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить файл TEMPUS',
      fileName: name,
      bytes: bytes,
    );

Future<Uint8List> yearPdf(Snapshot snapshot, int year) async {
  final document = pw.Document(
    title: 'TEMPUS · $year',
    author: snapshot.name.isEmpty ? 'TEMPUS' : snapshot.name,
  );
  final start = DateTime(year);
  final end = DateTime(year + 1);
  final history = DateTime.parse(snapshot.history);
  final first = history.isAfter(start) ? history : start;
  final total = ProgressSummary.between(snapshot.records, first, end);
  final font = pw.Font.ttf(await rootBundle.load('assets/TempusSerif.ttf'));
  final rows =
      snapshot.records
          .where(
            (row) =>
                row.kind.isArchive &&
                !row.date.isBefore(first) &&
                row.date.isBefore(end),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  final planRows = [
    ['Сфера', 'Выполнено', 'План'],
    for (final area in areas)
      [
        area,
        ...(() {
          final summary = ProgressSummary.between(
            snapshot.records.where((row) => row.area == area).toList(),
            first,
            end,
          );
          return ['${summary.completed}', '${summary.planned}'];
        })(),
      ],
  ];
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font),
      margin: const pw.EdgeInsets.all(38),
      maxPages: 250,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.Text(
          'TEMPUS',
          style: const pw.TextStyle(
            fontSize: 34,
            color: PdfColor.fromInt(0xff8a5429),
          ),
        ),
        pw.Text(
          'Годовая сводка · $year',
          style: const pw.TextStyle(fontSize: 21),
        ),
        if (snapshot.name.isNotEmpty) pw.Text(snapshot.name),
        pw.SizedBox(height: 13),
        pw.Text('План и факт · ${total.completed} из ${total.planned}'),
        pw.Text('Доходы · ${money(total.income)}'),
        pw.Text('Расходы · ${money(total.expense)}'),
        pw.Text('Баланс · ${money(total.income - total.expense)}'),
        pw.SizedBox(height: 13),
        pw.TableHelper.fromTextArray(
          cellPadding: const pw.EdgeInsets.all(6),
          data: planRows,
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xffeee1d5),
          ),
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey300),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Летопись · ${total.archive}',
          style: const pw.TextStyle(fontSize: 18),
        ),
        for (final row in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              '${shortDate(row.date)} · ${row.kind.label} · ${row.title}',
            ),
          ),
      ],
    ),
  );
  return document.save();
}
