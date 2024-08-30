import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:secure_storage/secure_storage.dart';

final MemoryAppender logMessages = MemoryAppender();

final _logger = Logger('main');

void main() {
  Logger.root.level = Level.ALL;
  PrintAppender().attachToLogger(Logger.root);
  logMessages.attachToLogger(Logger.root);
  _logger.fine('Application launched. (v2)');
  runApp(const MyApp());
}

class StringBufferWrapper with ChangeNotifier {
  final StringBuffer _buffer = StringBuffer();

  void writeln(String line) {
    _buffer.writeln(line);
    notifyListeners();
  }

  @override
  String toString() => _buffer.toString();
}

class ShortFormatter extends LogRecordFormatter {
  @override
  StringBuffer formatToStringBuffer(LogRecord rec, StringBuffer sb) {
    sb.write(
        '${rec.time.hour}:${rec.time.minute}:${rec.time.second} ${rec.level.name} '
        '${rec.message}');

    if (rec.error != null) {
      sb.write(rec.error);
    }
    // ignore: avoid_as
    final stackTrace = rec.stackTrace ??
        (rec.error is Error ? (rec.error as Error).stackTrace : null);
    if (stackTrace != null) {
      sb.write(stackTrace);
    }
    return sb;
  }
}

class MemoryAppender extends BaseLogAppender {
  MemoryAppender() : super(ShortFormatter());

  final StringBufferWrapper log = StringBufferWrapper();

  @override
  void handle(LogRecord record) {
    log.writeln(formatter.format(record));
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final String baseName = 'default';
  BiometricStorageFile? _authStorage;
  BiometricStorageFile? _storage;
  BiometricStorageFile? _customPrompt;

  final TextEditingController _writeController =
      TextEditingController(text: 'Lorem Ipsum');

  @override
  void initState() {
    super.initState();
    logMessages.log.addListener(_logChanged);
    _checkAuthenticate();
  }

  @override
  void dispose() {
    logMessages.log.removeListener(_logChanged);
    super.dispose();
  }

  Future<CanAuthenticateResponse> _checkAuthenticate() async {
    final response = await BiometricStorage().canAuthenticate();
    _logger.info('checked if authentication was possible: $response');
    return response;
  }

  void _logChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            const Text('Methods:'),
            ElevatedButton(
              child: const Text('init'),
              onPressed: () async {
                _logger.finer('Initializing $baseName');
                final authenticate = await _checkAuthenticate();
                if (authenticate == CanAuthenticateResponse.unsupported) {
                  _logger.severe(
                      'Unable to use authenticate. Unable to get storage.');
                  return;
                }
                final supportsAuthenticated =
                    authenticate == CanAuthenticateResponse.success ||
                        authenticate == CanAuthenticateResponse.statusUnknown;
                if (supportsAuthenticated) {
                  _authStorage = await BiometricStorage().getStorage(
                      '${baseName}_authenticated_any',
                      options: StorageFileInitOptions());
                }
                _storage = await BiometricStorage()
                    .getStorage('${baseName}_authenticated_none',
                        options: StorageFileInitOptions(
                          biometricAccessControl:
                              BiometricAccessControl.biometryNone,
                        ));
                if (supportsAuthenticated) {
                  _customPrompt = await BiometricStorage().getStorage(
                      '${baseName}_authenticated_currentset',
                      options: StorageFileInitOptions(
                          biometricAccessControl:
                              BiometricAccessControl.biometryCurrentSet),
                      promptInfo: const PromptInfo(
                        iosPromptInfo: IosPromptInfo(
                          saveTitle: 'Custom save title',
                          accessTitle: 'Custom access title.',
                        ),
                        androidPromptInfo: AndroidPromptInfo(
                          title: 'Custom title',
                          subtitle: 'Custom subtitle',
                          description: 'Custom description',
                          negativeButton: 'Nope!',
                        ),
                      ));
                }
                setState(() {});
                _logger.info('initiailzed $baseName');
              },
            ),
            ...(_authStorage == null
                ? []
                : [
                    const Text('Biometric Authentication Any',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _authStorage!,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            ...?(_storage == null
                ? null
                : [
                    const Text('Biometric Authentication None',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _storage!,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            ...?(_customPrompt == null
                ? null
                : [
                    const Text('Biometric Authentication CurrentSet',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    StorageActions(
                        storageFile: _customPrompt!,
                        writeController: _writeController),
                    const Divider(),
                  ]),
            const Divider(),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Example text to write',
              ),
              controller: _writeController,
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                constraints: const BoxConstraints.expand(),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      logMessages.log.toString(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StorageActions extends StatelessWidget {
  const StorageActions({
    super.key,
    required this.storageFile,
    required this.writeController,
  });

  final BiometricStorageFile storageFile;
  final TextEditingController writeController;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        ElevatedButton(
          child: const Text('read'),
          onPressed: () async {
            _logger.fine('reading from ${storageFile.name}');
            try {
              final result = await storageFile.read();
              _logger.fine('read: {$result}');
            } on AuthException catch (e) {
              if (e.code == AuthExceptionCode.userCanceled) {
                _logger.info('User canceled.');
                return;
              }
              rethrow;
            }
          },
        ),
        ElevatedButton(
          child: const Text('write'),
          onPressed: () async {
            _logger.fine('Going to write...');
            try {
              await storageFile
                  .write(' [${DateTime.now()}] ${writeController.text}');
              _logger.info('Written content.');
            } on AuthException catch (e) {
              if (e.code == AuthExceptionCode.userCanceled) {
                _logger.info('User canceled.');
                return;
              }
              rethrow;
            }
          },
        ),
        ElevatedButton(
          child: const Text('delete'),
          onPressed: () async {
            _logger.fine('deleting...');
            await storageFile.delete();
            _logger.info('Deleted.');
          },
        ),
      ],
    );
  }
}
