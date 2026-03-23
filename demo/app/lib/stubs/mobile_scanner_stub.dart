/*
Copyright Gen Digital Inc. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

// Stub for mobile_scanner package on web platform
import 'package:flutter/material.dart';

enum DetectionSpeed { noDuplicates, normal, unrestricted }

class Barcode {
  final String? rawValue;
  const Barcode({this.rawValue});
}

class BarcodeCapture {
  final List<Barcode> barcodes;
  const BarcodeCapture({this.barcodes = const []});
}

class MobileScannerController {
  MobileScannerController({DetectionSpeed? detectionSpeed, bool? returnImage});
  void dispose() {}
}

class MobileScanner extends StatelessWidget {
  final MobileScannerController? controller;
  final void Function(BarcodeCapture)? onDetect;

  const MobileScanner({super.key, this.controller, this.onDetect});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
