#import "PXHookOptions.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

// Daemon đang post notify này trong WebServerManager
CFStringRef const kPXHookPrefsChangedNotification = CFSTR("com.projectx.hookprefs.changed");

static NSDictionary *gPXPrefs = nil;

// Dedicated lock object (không synchronize trên class chưa chắc tồn tại)
static NSObject *PXPrefsLock(void) {
    static NSObject *lockObj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lockObj = [NSObject new];
    });
    return lockObj;
}

// ✅ IMPORTANT:
// Daemon lưu HookOptions vào ProjectXTweak.plist (cùng file filter Bundles).
// Vì vậy tweak cũng phải đọc từ đây.
static NSString *PXPrefsPath(void) {
    NSString *tweakPlist = jbroot(@"/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist");
    if ([[NSFileManager defaultManager] fileExistsAtPath:tweakPlist]) {
        return tweakPlist;
    }

    // Fallback legacy (nếu bạn từng dùng file prefs riêng)
    NSString *legacy = jbroot(@"/var/mobile/Library/Preferences/com.projectx.hookprefs.plist");
    return legacy;
}

// Backwards-compatible wrapper
NSString *PXCurrentBundleIdentifier(void) {
    return PXSafeBundleIdentifier();
}

static void PXLoadPrefsLocked(void) {
    NSString *path = PXPrefsPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if ([dict isKindOfClass:[NSDictionary class]]) {
        gPXPrefs = dict;
    } else {
        gPXPrefs = @{};
    }
}

void PXReloadHookPrefs(void) {
    @synchronized(PXPrefsLock()) {
        PXLoadPrefsLocked();
    }
}

static NSDictionary *PXPrefs(void) {
    if (gPXPrefs == nil) {
        PXReloadHookPrefs();
    }
    return gPXPrefs ?: @{};
}

BOOL PXHookEnabled(NSString *key) {
    if (key.length == 0) return YES;

    NSString *bundleID = PXCurrentBundleIdentifier() ?: @"";
    NSDictionary *prefs = PXPrefs();

    NSDictionary *global = prefs[@"HookOptions"];
    NSDictionary *perAppAll = prefs[@"PerAppHookOptions"];
    NSDictionary *perApp = (bundleID.length && [perAppAll isKindOfClass:[NSDictionary class]]) ? perAppAll[bundleID] : nil;

    id v = nil;
    if ([perApp isKindOfClass:[NSDictionary class]]) {
        v = perApp[key];
    }
    if (!v && [global isKindOfClass:[NSDictionary class]]) {
        v = global[key];
    }

    if ([v isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)v boolValue];
    }
    return YES; // default ON nếu không có config
}

static void PXPrefsChanged(CFNotificationCenterRef center,
                           void *observer,
                           CFStringRef name,
                           const void *object,
                           CFDictionaryRef userInfo) {
    PXReloadHookPrefs();
}

__attribute__((constructor))
static void PXHookOptionsInit(void) {
    PXReloadHookPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    PXPrefsChanged,
                                    kPXHookPrefsChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}
