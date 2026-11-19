import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inventory_item.dart';

const assetLabelPageFormat = PdfPageFormat(
  80 * PdfPageFormat.mm,
  42 * PdfPageFormat.mm,
  marginAll: 2 * PdfPageFormat.mm,
);

/// CATATAN PEMELIHARAAN: PDF memakai ukuran label 80 × 42 mm, nama sekolah
/// dari rantai induk lokasi, dan kode aset server sebagai data Code 128. Jika
/// label fisik/driver sekolah memakai ukuran lain, ubah format dan ruang barcode
/// bersama agar kode tetap mudah dipindai.
Future<Uint8List> buildAssetLabelPdf({
  required InventoryItem item,
  required String schoolName,
}) async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: assetLabelPageFormat,
      build: (context) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(
          horizontal: 2 * PdfPageFormat.mm,
          vertical: 1.2 * PdfPageFormat.mm,
        ),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                schoolName.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.blueGrey700,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                item.name,
                style: pw.TextStyle(
                  color: PdfColors.blueGrey900,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: item.code,
              width: 72 * PdfPageFormat.mm,
              height: 16 * PdfPageFormat.mm,
              drawText: false,
            ),
            pw.Text(
              item.code,
              style: pw.TextStyle(
                color: PdfColors.blueGrey900,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            pw.Text(
              'ASET SEKOLAH  |  CODE 128',
              style: const pw.TextStyle(
                color: PdfColors.blueGrey400,
                fontSize: 6,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return document.save();
}

/// Membuka dialog cetak platform dan meneruskan PDF label sebagai satu halaman.
/// CATATAN PEMELIHARAAN: browser membuka print preview; Windows/Android
/// meneruskan ukuran halaman khusus ke dialog sistem, tempat pengguna memilih
/// printer dan media yang sesuai.
Future<bool> printAssetLabel({
  required InventoryItem item,
  required String schoolName,
}) {
  return Printing.layoutPdf(
    name: 'Label-${item.code}.pdf',
    format: assetLabelPageFormat,
    onLayout: (_) => buildAssetLabelPdf(item: item, schoolName: schoolName),
  );
}
