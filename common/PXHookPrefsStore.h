#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Storage for hook options (global + per-app) using CFPreferences (NSUserDefaults domain).
///
/// Domain: com.projectx.hookprefs
/// Keys:
///   - GlobalOptions (NSDictionary<NSString*, NSNumber*>)
///   - PerAppOptions (NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>)
///
/// Change notification (Darwin): com.projectx.hookprefs.changed

extern NSString * const PXHookPrefsDomain;
extern NSString * const PXHookPrefsDarwinNotification;

@interface PXHookPrefsStore : NSObject

/// Returns the stored global options merged with defaults. Guaranteed to contain all known keys.
+ (NSDictionary<NSString *, NSNumber *> *)globalOptions;

/// Returns all per-app overrides (may be empty). Values are merged with defaults per-app.
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)allPerAppOptions;

/// Returns merged options for a specific bundle id. If no per-app override exists, returns globalOptions.
+ (NSDictionary<NSString *, NSNumber *> *)optionsForBundleID:(NSString *)bundleID;

/// Set one hook key for global or per-app.
+ (void)setEnabled:(BOOL)enabled forHookKey:(NSString *)hookKey bundleID:(nullable NSString *)bundleID;

/// Save whole dictionaries (will be normalized + merged with schema).
+ (void)saveGlobalOptions:(NSDictionary<NSString *, NSNumber *> *)options;
+ (void)savePerAppOptions:(NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)optionsByBundleID;

/// Reset
+ (void)resetGlobalToDefaults;
+ (void)resetBundleIDToDefaults:(NSString *)bundleID;
+ (void)resetAllToDefaults;

/// Export / import
/// Export returns a file URL in /tmp.
+ (nullable NSURL *)exportConfigurationToTemporaryJSON:(NSError * _Nullable * _Nullable)error;
+ (BOOL)importConfigurationFromJSONURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
