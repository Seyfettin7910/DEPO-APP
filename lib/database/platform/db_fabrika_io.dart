import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android/iOS'ta sqflite doğrudan çalışır; Windows/Linux'ta FFI açılır.
void veritabaniFabrikasiniAyarla() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
