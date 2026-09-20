#import "RootHelper.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <unistd.h>

extern char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

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

+ (NSString *)helperPath {
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    NSString *path = [bundlePath stringByAppendingPathComponent:@"iremovehelper"];
    return path;
}

+ (int)spawnRoot:(NSString *)path args:(NSArray *)args stdOut:(NSString **)stdOut stdErr:(NSString **)stdErr {
    chmod([path UTF8String], 0755);

    NSMutableArray *argsM = [args mutableCopy] ?: [NSMutableArray array];
    [argsM insertObject:path atIndex:0];

    NSUInteger argCount = [argsM count];
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char *));
    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outPipe[2];
    pipe(outPipe);
    posix_spawn_file_actions_adddup2(&action, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&action, outPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&action, outPipe[0]);

    pid_t task_pid;
    int spawnError = posix_spawn(&task_pid, [path UTF8String], &action, &attr, (char * const *)argsC, environ);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&action);

    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);

    close(outPipe[1]);

    if (spawnError != 0) {
        if (stdErr) *stdErr = [NSString stringWithFormat:@"Không thể spawn root helper (%d)", spawnError];
        close(outPipe[0]);
        return spawnError;
    }

    NSMutableString *output = [NSMutableString new];
    char buf[512];
    ssize_t bytesRead;
    while ((bytesRead = read(outPipe[0], buf, sizeof(buf) - 1)) > 0) {
        buf[bytesRead] = '\0';
        [output appendString:[NSString stringWithUTF8String:buf]];
    }
    close(outPipe[0]);

    int status = 0;
    waitpid(task_pid, &status, 0);
    if (stdOut) *stdOut = output;
    return WEXITSTATUS(status);
}

+ (void)respring {
    NSString *helper = [self helperPath];
    [self spawnRoot:helper args:@[@"respring"] stdOut:nil stdErr:nil];
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
    NSString *helper = [self helperPath];
    NSString *stdOut = nil;
    NSString *stdErr = nil;
    int ret = [self spawnRoot:helper
                         args:@[@"hide", appPath, hide ? @"1" : @"0"]
                       stdOut:&stdOut
                       stdErr:&stdErr];
                       
    if (ret != 0) {
        return [NSString stringWithFormat:@"Root helper lỗi (%d): %@ %@", ret, stdErr ?: @"", stdOut ?: @""];
    }
    return nil;
}

+ (NSString *)renameAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID newName:(NSString *)newName {
    NSString *helper = [self helperPath];
    NSString *stdOut = nil;
    NSString *stdErr = nil;
    int ret = [self spawnRoot:helper
                         args:@[@"rename", appPath, newName]
                       stdOut:&stdOut
                       stdErr:&stdErr];
                       
    if (ret != 0) {
        return [NSString stringWithFormat:@"Root helper lỗi (%d): %@ %@", ret, stdErr ?: @"", stdOut ?: @""];
    }
    return nil;
}

@end
