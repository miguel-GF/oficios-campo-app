import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'backup_format.dart';
import 'database.dart';
import 'domain.dart';

Future<String> exportEncryptedBackup(Database db, String password) async {
  final snapshot = await exportSnapshot(db);
  final value = await encryptBackup(snapshot, password);
  final directory = await getTemporaryDirectory();
  final file = File(
    path.join(
      directory.path,
      'jale-backup-${DateTime.now().millisecondsSinceEpoch}.jale-backup',
    ),
  );
  await file.writeAsString(value);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: 'Respaldo cifrado de Jale'),
  );
  return file.path;
}

Future<BackupSnapshot?> importEncryptedBackup(
  Database db,
  String password,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    withData: false,
  );
  final selected = result?.files.single.path;
  if (selected == null) return null;
  final snapshot = await decryptBackup(
    await File(selected).readAsString(),
    password,
  );
  await importSnapshot(db, snapshot);
  return snapshot;
}
