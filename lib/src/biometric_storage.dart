import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

final _logger = Logger('biometric_storage');

/// Reason for not supporting authentication.
/// **As long as this is NOT [unsupported] you can still use the secure
/// storage without biometric storage** (By setting
/// [StorageFileInitOptions.authenticationRequired] to `false`).
enum CanAuthenticateResponse {
  success,
  errorHwUnavailable,
  errorNoBiometricEnrolled,
  errorNoHardware,

  /// Passcode is not set (iOS/MacOS) or no user credentials (on macos).
  errorPasscodeNotSet,

  /// Used on android if the status is unknown.
  /// https://developer.android.com/reference/androidx/biometric/BiometricManager#BIOMETRIC_STATUS_UNKNOWN
  statusUnknown,

  /// Plugin does not support platform. This should no longer be the case.
  unsupported,
}

const _canAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
  'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
};

enum AuthExceptionCode {
  /// User taps the cancel/negative button or presses `back`.
  userCanceled,

  /// Authentication prompt is canceled due to another reason
  /// (like when biometric sensor becamse unavailable like when
  /// user switches between apps, logsout, etc).
  canceled,
  unknown,
  timeout,
}

enum BiometricAccessControl {
  biometryNone,
  biometryAny,
  // Android >= API 30
  biometryCurrentSet,
}

BiometricAccessControl biometricAccessControlFromString(
    String biometricAccessControlValue) {
  return BiometricAccessControl.values
      .firstWhere((c) => c.name == biometricAccessControlValue);
}

const _authErrorCodeMapping = {
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Canceled': AuthExceptionCode.canceled,
  'AuthError:Timeout': AuthExceptionCode.timeout,
};

class BiometricStorageException implements Exception {
  BiometricStorageException(this.message);
  final String message;

  @override
  String toString() {
    return 'BiometricStorageException{message: $message}';
  }
}

/// Exceptions during authentication operations.
/// See [AuthExceptionCode] for details.
class AuthException implements Exception {
  AuthException(this.code, this.message);

  final AuthExceptionCode code;
  final String message;

  @override
  String toString() {
    return 'AuthException{code: $code, message: $message}';
  }
}

class StorageFileInitOptions {
  final BiometricAccessControl biometricAccessControl;

  StorageFileInitOptions({
    this.biometricAccessControl = BiometricAccessControl.biometryAny,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'biometricAccessControl': biometricAccessControl.name,
      };
}

/// Android specific configuration of the prompt displayed for biometry.
class AndroidPromptInfo {
  const AndroidPromptInfo({
    this.title = 'Authenticate to unlock data',
    this.subtitle,
    this.description,
    this.negativeButton = 'Cancel',
    this.confirmationRequired = true,
  });

  final String title;
  final String? subtitle;
  final String? description;
  final String negativeButton;
  final bool confirmationRequired;

  static const defaultValues = AndroidPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'negativeButton': negativeButton,
        'confirmationRequired': confirmationRequired,
      };
}

/// iOS **and MacOS** specific configuration of the prompt displayed for biometry.
class IosPromptInfo {
  const IosPromptInfo({
    this.saveTitle = 'Unlock to save data',
    this.accessTitle = 'Unlock to access data',
  });

  final String saveTitle;
  final String accessTitle;

  static const defaultValues = IosPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
        'saveTitle': saveTitle,
        'accessTitle': accessTitle,
      };
}

/// Wrapper for platform specific prompt infos.
class PromptInfo {
  const PromptInfo({
    this.androidPromptInfo = AndroidPromptInfo.defaultValues,
    this.iosPromptInfo = IosPromptInfo.defaultValues,
    this.macOsPromptInfo = IosPromptInfo.defaultValues,
  });
  static const defaultValues = PromptInfo();

  final AndroidPromptInfo androidPromptInfo;
  final IosPromptInfo iosPromptInfo;
  final IosPromptInfo macOsPromptInfo;
}

/// Main plugin class to interact with. Is always a singleton right now,
/// factory constructor will always return the same instance.
///
/// * call [canAuthenticate] to check support on the platform/device.
/// * call [getStorage] to initialize a storage.
abstract class BiometricStorage extends PlatformInterface {
  // Returns singleton instance.
  factory BiometricStorage() => _instance;

  BiometricStorage.create() : super(token: _token);

  static BiometricStorage _instance = MethodChannelBiometricStorage();

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [UrlLauncherPlatform] when they register themselves.
  static set instance(BiometricStorage instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  static const Object _token = Object();

  /// Returns whether this device supports biometric/secure storage or
  /// the reason [CanAuthenticateResponse] why it is not supported.
  Future<CanAuthenticateResponse> canAuthenticate();

  /// Retrieves the given biometric storage file.
  /// Each store is completely separated, and has it's own encryption and
  /// biometric lock.
  /// if [forceInit] is true, will throw an exception if the store was already
  /// created in this runtime.
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  });

  @protected
  Future<String?> read(
    String name,
    PromptInfo promptInfo,
  );

  @protected
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  );

  @protected
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo,
  );
}

class MethodChannelBiometricStorage extends BiometricStorage {
  MethodChannelBiometricStorage() : super.create();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  @override
  Future<CanAuthenticateResponse> canAuthenticate() async {
    if (kIsWeb) {
      return CanAuthenticateResponse.unsupported;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final response = await _channel.invokeMethod<String>('canAuthenticate');
      final ret = _canAuthenticateMapping[response];
      if (ret == null) {
        throw StateError('Invalid response from native platform. {$response}');
      }
      return ret;
    }
    return CanAuthenticateResponse.unsupported;
  }

  /// Retrieves the given biometric storage file.
  /// Each store is completely separated, and has it's own encryption and
  /// biometric lock.
  /// if [forceInit] is true, will throw an exception if the store was already
  /// created in this runtime.
  @override
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'init',
        {
          'name': name,
          'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
          'forceInit': forceInit,
        },
      );
      _logger.finest('getting storage. was created: $result');
      return BiometricStorageFile(
        this,
        name,
        promptInfo,
      );
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while initializing biometric storage.', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod<String>('read', <String, dynamic>{
        'name': name,
        ..._promptInfoForCurrentPlatform(promptInfo),
      }));

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod<bool>('delete', <String, dynamic>{
        'name': name,
        ..._promptInfoForCurrentPlatform(promptInfo),
      }));

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod('write', <String, dynamic>{
        'name': name,
        'content': content,
        ..._promptInfoForCurrentPlatform(promptInfo),
      }));

  Map<String, dynamic> _promptInfoForCurrentPlatform(PromptInfo promptInfo) {
    // Don't expose Android configurations to other platforms
    if (Platform.isAndroid) {
      return <String, dynamic>{
        'androidPromptInfo': promptInfo.androidPromptInfo._toJson()
      };
    } else if (Platform.isIOS) {
      return <String, dynamic>{
        'iosPromptInfo': promptInfo.iosPromptInfo._toJson()
      };
    } else if (Platform.isMacOS) {
      return <String, dynamic>{
        // This is no typo, we use the same implementation on iOS and MacOS,
        // so we use the same parameter.
        'iosPromptInfo': promptInfo.macOsPromptInfo._toJson()
      };
    } else {
      // Windows has no method channel implementation
      // Web has a Noop implementation.
      throw StateError('Unsupported Platform ${Platform.operatingSystem}');
    }
  }

  Future<T> _transformErrors<T>(Future<T> future) =>
      future.catchError((Object error, StackTrace stackTrace) {
        if (error is PlatformException) {
          _logger.finest(
              'Error during plugin operation (details: ${error.details})',
              error,
              stackTrace);
          if (error.code.startsWith('AuthError:')) {
            return Future<T>.error(
              AuthException(
                _authErrorCodeMapping[error.code] ?? AuthExceptionCode.unknown,
                error.message ?? 'Unknown error',
              ),
              stackTrace,
            );
          }
        }
        return Future<T>.error(error, stackTrace);
      });
}

class BiometricStorageFile {
  BiometricStorageFile(this._plugin, this.name, this.defaultPromptInfo);

  final BiometricStorage _plugin;
  final String name;
  final PromptInfo defaultPromptInfo;

  /// read from the secure file and returns the content.
  /// Will return `null` if file does not exist.
  Future<String?> read({PromptInfo? promptInfo}) =>
      _plugin.read(name, promptInfo ?? defaultPromptInfo);

  /// Write content of this file. Previous value will be overwritten.
  Future<void> write(String content, {PromptInfo? promptInfo}) =>
      _plugin.write(name, content, promptInfo ?? defaultPromptInfo);

  /// Delete the content of this storage.
  Future<void> delete({PromptInfo? promptInfo}) =>
      _plugin.delete(name, promptInfo ?? defaultPromptInfo);
}
