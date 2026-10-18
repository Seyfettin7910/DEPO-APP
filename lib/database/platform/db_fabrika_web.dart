import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web: veriler tarayıcının IndexedDB'sinde saklanır. web/ klasöründe
/// sqlite3.wasm ve sqflite_sw.js bulunmalı; bunları
/// `dart run sqflite_common_ffi_web:setup` komutu üretir
/// (web_derle.bat ve GitHub derlemesi bunu otomatik yapar).
void veritabaniFabrikasiniAyarla() {
  databaseFactory = databaseFactoryFfiWeb;
}
