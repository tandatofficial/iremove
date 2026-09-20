#import "RootHelper.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <dlfcn.h>
#import <unistd.h>

extern char **environ;

@implementation RootHelper

+ (void)initialize {
    if (self == [RootHelper class]) {
        [self escalatePrivileges];
    }
}

+ (void)escalatePrivileges {
    setuid(0);
    seteuid(0);
    setgid(0);
    setegid(0);
}

+ (void)killProcessNamed:(NSString *)targetName {
    [self escalatePrivileges];
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return;
    
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return;
    }
    
    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        char *name = procs[i].kp_proc.p_comm;
        if (strcmp(name, [targetName UTF8String]) == 0) {
            kill(procs[i].kp_proc.p_pid, SIGTERM);
        }
    }
    free(procs);
}

+ (void)respring {
    [self escalatePrivileges];
    [self killProcessNamed:@"SpringBoard"];
}

+ (void)triggerTrollStoreHelperForPath:(NSString *)appPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *baseDir = @"/var/containers/Bundle/Application";
    NSArray *subdirs = [fm contentsOfDirectoryAtPath:baseDir error:nil];
    for (NSString *uuid in subdirs) {
        NSString *helper = [baseDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/TrollStore.app/trollstorehelper", uuid]];
        if ([fm fileExistsAtPath:helper]) {
            pid_t pid;
            const char *args[] = {[helper UTF8String], "uicache", NULL};
            int ret = posix_spawn(&pid, args[0], NULL, NULL, (char* const*)args, environ);
            if (ret == 0) {
                waitpid(pid, NULL, 0);
            }
            return;
        }
    }
}

+ (void)refreshCacheForPath:(NSString *)appPath bundleID:(NSString *)bundleID {
    [self escalatePrivileges];

    // 1. TrollStore helper uicache
    [self triggerTrollStoreHelperForPath:appPath];

    // 2. Private SpringBoardServices icon reload
    void *sb = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    if (sb) {
        mach_port_t (*SBSSpringBoardServerPort)(void) = dlsym(sb, "SBSSpringBoardServerPort");
        mach_msg_return_t (*SBReloadIconForIdentifier)(mach_port_t, const char*) = dlsym(sb, "SBReloadIconForIdentifier");
        if (SBSSpringBoardServerPort && SBReloadIconForIdentifier && bundleID) {
            SBReloadIconForIdentifier(SBSSpringBoardServerPort(), [bundleID UTF8String]);
        }
    }

    // 3. Clear iconservicesagent cache
    [self killProcessNamed:@"iconservicesagent"];
}

+ (NSString *)writePlistSafely:(NSDictionary *)plist toPath:(NSString *)plistPath {
    [self escalatePrivileges];

    const char *cPath = [plistPath UTF8String];
    chmod(cPath, 0777);

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (error || !data) {
        return [NSString stringWithFormat:@"Lỗi serialize: %@", error.localizedDescription];
    }

    BOOL ok = [data writeToFile:plistPath options:NSDataWritingAtomic error:&error];
    if (!ok) {
        ok = [data writeToFile:plistPath atomically:NO];
        if (!ok) {
            return [NSString stringWithFormat:@"Lỗi ghi file (UID=%d, EUID=%d): %@", getuid(), geteuid(), error.localizedDescription];
        }
    }

    chown(cPath, 33, 33);
    chmod(cPath, 0644);
    return nil; // Success
}

+ (NSArray<NSDictionary *> *)getInstalledApps {
    [self escalatePrivileges];
    NSMutableArray *result = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *baseDir = @"/var/containers/Bundle/Application";
    
    NSArray *subdirs = [fm contentsOfDirectoryAtPath:baseDir error:nil];
    if (!subdirs) return result;

    for (NSString *uuid in subdirs) {
        NSString *containerPath = [baseDir stringByAppendingPathComponent:uuid];
        NSArray *items = [fm contentsOfDirectoryAtPath:containerPath error:nil];
        
        for (NSString *item in items) {
            if ([item hasSuffix:@".app"]) {
                NSString *appPath = [containerPath stringByAppendingPathComponent:item];
                NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                
                if (plist) {
                    NSString *name = plist[@"CFBundleDisplayName"] ?: plist[@"CFBundleName"] ?: item;
                    NSString *bundleId = plist[@"CFBundleIdentifier"] ?: @"unknown";
                    NSArray *tags = plist[@"SBAppTags"] ?: @[];
                    BOOL isHidden = [tags containsObject:@"hidden"];
                    
                    [result addObject:@{
                        @"bundleId": bundleId,
                        @"name": name,
                        @"path": appPath,
                        @"isHidden": @(isHidden)
                    }];
                }
            }
        }
    }
    return result;
}

+ (NSString *)hideAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID hide:(BOOL)hide {
    [self escalatePrivileges];
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) {
        return @"Không thể đọc Info.plist của ứng dụng đích.";
    }

    NSMutableArray *tags = [plist[@"SBAppTags"] mutableCopy] ?: [NSMutableArray array];
    if (hide) {
        if (![tags containsObject:@"hidden"]) [tags addObject:@"hidden"];
    } else {
        [tags removeObject:@"hidden"];
    }

    plist[@"SBAppTags"] = tags;
    NSString *err = [self writePlistSafely:plist toPath:plistPath];
    if (err) return err;

    [self refreshCacheForPath:appPath bundleID:bundleID];
    return nil; // Thành công
}

+ (NSString *)renameAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID newName:(NSString *)newName {
    [self escalatePrivileges];
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) {
        return @"Không thể đọc Info.plist của ứng dụng đích.";
    }

    plist[@"CFBundleDisplayName"] = newName;
    plist[@"CFBundleName"] = newName;

    NSString *err = [self writePlistSafely:plist toPath:plistPath];
    if (err) return err;

    [self refreshCacheForPath:appPath bundleID:bundleID];
    return nil; // Thành công
}

+ (NSString *)changeIconAtPath:(NSString *)appPath bundleID:(NSString *)bundleID iconData:(NSData *)newIconPngData {
    [self escalatePrivileges];
    NSString *iconDest = [appPath stringByAppendingPathComponent:@"iRemoveCustomIcon60x60@2x.png"];
    chmod([iconDest UTF8String], 0777);
    [newIconPngData writeToFile:iconDest atomically:YES];
    chown([iconDest UTF8String], 33, 33);
    chmod([iconDest UTF8String], 0644);

    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) {
        return @"Không thể đọc Info.plist.";
    }

    NSDictionary *primaryIcon = @{
        @"CFBundleIconFiles": @[@"iRemoveCustomIcon60x60"],
        @"UIPrerenderedIcon": @YES
    };
    
    plist[@"CFBundleIcons"] = @{ @"CFBundlePrimaryIcon": primaryIcon };
    plist[@"CFBundleIcons~ipad"] = @{ @"CFBundlePrimaryIcon": primaryIcon };

    NSString *err = [self writePlistSafely:plist toPath:plistPath];
    if (err) return err;

    [self refreshCacheForPath:appPath bundleID:bundleID];
    return nil;
}

@end
