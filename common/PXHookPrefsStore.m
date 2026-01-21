#import "PXHookPrefsStore.h"
#import "PXHookKeys.h"

#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

NSString * const PXHookPrefsDomain = @"com.projectx.hookprefs";
NSString * const PXHookPrefsDarwinNotification = @"com.projectx.hookprefs.changed";

static NSString * const kPXHookPrefsKeyGlobal = @"GlobalOptions";
static NSString * const kPXHookPrefsKeyPerApp = @"PerAppOptions";

static NSDictionary<NSString*, NSNumber*> *PXSanitizeOptions(NSDictionary * _Nullable options) {
    NSDictionary<NSString*, NSNumber*> *defaults = PXDefaultHookOptions();
    if (![options isKindOfClass:[NSDictionary class]]) {
        return defaults;
    }
    NSMutableDictionary<NSString*, NSNumber*> *out = [defaults mutableCopy];
    for (NSString *key in PXAllHookKeys()) {
        id v = options[key];
        if ([v isKindOfClass:[NSNumber class]]) {
            out[key] = v;
        } else if ([v isKindOfClass:[NSString class]]) {
            // tolerate "0"/"1" strings
            out[key] = @([(NSString *)v boolValue]);
        }
    }
    return [out copy];
}

static NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*> *PXSanitizePerApp(NSDictionary * _Nullable perApp) {
    if (![perApp isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [perApp enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        NSDictionary *opt = PXSanitizeOptions(obj);
        out[key] = opt;
    }];
    return [out copy];
}

static void PXPrefsSetValue(NSString *key, id _Nullable value) {
    CFStringRef domain = (__bridge CFStringRef)PXHookPrefsDomain;
    CFStringRef k = (__bridge CFStringRef)key;
    CFPropertyListRef v = value ? (__bridge CFPropertyListRef)value : NULL;
    CFPreferencesSetAppValue(k, v, domain);
}

static id _Nullable PXPrefsCopyValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)PXHookPrefsDomain;
    CFStringRef k = (__bridge CFStringRef)key;
    CFPropertyListRef v = CFPreferencesCopyAppValue(k, domain);
    return CFBridgingRelease(v);
}

static void PXPrefsSync(void) {
    CFStringRef domain = (__bridge CFStringRef)PXHookPrefsDomain;
    CFPreferencesAppSynchronize(domain);
}

static void PXPostChangeNotification(void) {
    notify_post([PXHookPrefsDarwinNotification UTF8String]);
}

@implementation PXHookPrefsStore

#pragma mark - Compatibility aliases

+ (NSDictionary<NSString *, NSNumber *> *)globalHookOptions {
    return [self globalOptions];
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)allPerAppOptions {
    return [self perAppOptionsAll];
}

+ (void)resetGlobalToDefaults {
    [self resetGlobalToDefault];
}

+ (void)resetBundleIDToDefaults:(NSString *)bundleID {
    [self resetAppToDefault:bundleID];
}

+ (void)resetAllToDefaults {
    [self resetAllToDefault];
}

+ (NSURL *)exportConfigToTemporaryFile {
    return [self exportConfigToTemporaryFile:nil];
}

+ (NSURL *)exportConfigurationToTemporaryJSON:(NSError *__autoreleasing  _Nullable *)error {
    return [self exportConfigToTemporaryFile:error];
}

+ (NSDictionary<NSString *,NSNumber *> *)globalOptions {
    return PXSanitizeOptions(PXPrefsCopyValue(kPXHookPrefsKeyGlobal));
}

+ (NSDictionary<NSString *,NSDictionary<NSString *,NSNumber *> *> *)perAppOptionsAll {
    return PXSanitizePerApp(PXPrefsCopyValue(kPXHookPrefsKeyPerApp));
}

+ (NSDictionary<NSString *,NSNumber *> *)optionsForApp:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return [self globalOptions];
    }
    NSDictionary *perApp = [self perAppOptionsAll];
    NSDictionary *opt = perApp[bundleIdentifier];
    if ([opt isKindOfClass:[NSDictionary class]]) {
        return PXSanitizeOptions(opt);
    }
    return [self globalOptions];
}

+ (void)saveGlobalOptions:(NSDictionary<NSString *,NSNumber *> *)options {
    PXPrefsSetValue(kPXHookPrefsKeyGlobal, PXSanitizeOptions(options));
    PXPrefsSync();
    PXPostChangeNotification();
}

+ (void)savePerAppOptions:(NSDictionary<NSString *,NSNumber *> *)options forApp:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return;

    NSMutableDictionary *perApp = [[self perAppOptionsAll] mutableCopy];
    perApp[bundleIdentifier] = PXSanitizeOptions(options);

    PXPrefsSetValue(kPXHookPrefsKeyPerApp, [perApp copy]);
    PXPrefsSync();
    PXPostChangeNotification();
}

+ (void)resetGlobalToDefault {
    [self saveGlobalOptions:PXDefaultHookOptions()];
}

+ (void)resetAppToDefault:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return;
    NSMutableDictionary *perApp = [[self perAppOptionsAll] mutableCopy];
    [perApp removeObjectForKey:bundleIdentifier];
    PXPrefsSetValue(kPXHookPrefsKeyPerApp, [perApp copy]);
    PXPrefsSync();
    PXPostChangeNotification();
}

+ (void)resetAllToDefault {
    PXPrefsSetValue(kPXHookPrefsKeyGlobal, PXDefaultHookOptions());
    PXPrefsSetValue(kPXHookPrefsKeyPerApp, @{});
    PXPrefsSync();
    PXPostChangeNotification();
}

+ (NSURL *)exportConfigToTemporaryFile:(NSError *__autoreleasing  _Nullable *)error {
    NSDictionary *payload = @{
        @"version": @1,
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"global": [self globalOptions],
        @"perApp": [self perAppOptionsAll]
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:error];
    if (!data) {
        return nil;
    }

    NSString *fileName = [NSString stringWithFormat:@"projectx-hook-options-%@.json", [[NSUUID UUID] UUIDString]];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) {
        return nil;
    }
    return url;
}

+ (BOOL)importConfigFromURL:(NSURL *)url error:(NSError *__autoreleasing  _Nullable *)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return NO;

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json || ![json isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PXHookPrefsStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON"}];
        }
        return NO;
    }

    NSDictionary *dict = (NSDictionary *)json;
    NSDictionary *global = dict[@"global"];
    NSDictionary *perApp = dict[@"perApp"];

    PXPrefsSetValue(kPXHookPrefsKeyGlobal, PXSanitizeOptions(global));
    PXPrefsSetValue(kPXHookPrefsKeyPerApp, PXSanitizePerApp(perApp));
    PXPrefsSync();
    PXPostChangeNotification();
    return YES;
}

@end
