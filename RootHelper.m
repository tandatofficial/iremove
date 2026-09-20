#import "RootHelper.h"
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

@implementation RootHelper

+ (void)refreshCacheForPath:(NSString *)appPath {
    pid_t pid;
    const char *args[] = {"/usr/bin/uicache", "-p", [appPath UTF8String], NULL};
    int status = posix_spawn(&pid, args[0], NULL, NULL, (char* const*)args, environ);
    if (status == 0) {
        waitpid(pid, &status, 0);
    }
}

+ (NSArray<NSDictionary *> *)getInstalledApps {
    NSMutableArray *result = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *baseDir = @"/var/containers/Bundle/Application";
    
    NSError *error = nil;
    NSArray *subdirs = [fm contentsOfDirectoryAtPath:baseDir error:&error];
    if (error || !subdirs) return result;

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

+ (BOOL)hideAppAtPath:(NSString *)appPath hide:(BOOL)hide {
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) return NO;

    NSMutableArray *tags = [plist[@"SBAppTags"] mutableCopy] ?: [NSMutableArray array];
    if (hide) {
        if (![tags containsObject:@"hidden"]) [tags addObject:@"hidden"];
    } else {
        [tags removeObject:@"hidden"];
    }

    plist[@"SBAppTags"] = tags;
    BOOL ok = [plist writeToFile:plistPath atomically:YES];
    if (ok) {
        [self refreshCacheForPath:appPath];
    }
    return ok;
}

+ (BOOL)renameAppAtPath:(NSString *)appPath newName:(NSString *)newName {
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) return NO;

    plist[@"CFBundleDisplayName"] = newName;
    plist[@"CFBundleName"] = newName;

    BOOL ok = [plist writeToFile:plistPath atomically:YES];
    if (ok) {
        [self refreshCacheForPath:appPath];
    }
    return ok;
}

+ (BOOL)changeIconAtPath:(NSString *)appPath iconData:(NSData *)newIconPngData {
    NSString *iconDest = [appPath stringByAppendingPathComponent:@"iRemoveCustomIcon60x60@2x.png"];
    [newIconPngData writeToFile:iconDest atomically:YES];

    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) return NO;

    NSDictionary *primaryIcon = @{
        @"CFBundleIconFiles": @[@"iRemoveCustomIcon60x60"],
        @"UIPrerenderedIcon": @YES
    };
    
    plist[@"CFBundleIcons"] = @{ @"CFBundlePrimaryIcon": primaryIcon };
    plist[@"CFBundleIcons~ipad"] = @{ @"CFBundlePrimaryIcon": primaryIcon };

    BOOL ok = [plist writeToFile:plistPath atomically:YES];
    if (ok) {
        [self refreshCacheForPath:appPath];
    }
    return ok;
}

@end
