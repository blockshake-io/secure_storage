#import "SecureStoragePlugin.h"
#import <secure_storage/secure_storage-Swift.h>

@implementation SecureStoragePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSecureStoragePlugin registerWithRegistrar:registrar];
}
@end
