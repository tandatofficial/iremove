#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Enforce true root
        setuid(0);
        seteuid(0);
        setgid(0);
        setegid(0);

        if (argc < 2) {
            printf("iRemove Root Helper - Usage: <respring|hide|rename> [args]\n");
            return 1;
        }

        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        // 1. Respring
        if ([cmd isEqualToString:@"respring"]) {
            int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
            size_t size;
            if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0) {
                struct kinfo_proc *procs = malloc(size);
                if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
                    int count = (int)(size / sizeof(struct kinfo_proc));
                    for (int i = 0; i < count; i++) {
                        if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
                            kill(procs[i].kp_proc.p_pid, SIGTERM);
                        }
                    }
                    free(procs);
                }
            }
            printf("Respring triggered\n");
            return 0;
        }

        // 2. Hide / Unhide
        if ([cmd isEqualToString:@"hide"] && argc >= 4) {
            NSString *plistPath = [NSString stringWithUTF8String:argv[2]];
            BOOL hide = atoi(argv[3]) != 0;

            chmod([plistPath UTF8String], 0777);
            NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
            if (!plist) {
                printf("Error: Không thể đọc Info.plist tại %s\n", [plistPath UTF8String]);
                return 2;
            }

            NSMutableArray *tags = [plist[@"SBAppTags"] mutableCopy] ?: [NSMutableArray array];
            if (hide) {
                if (![tags containsObject:@"hidden"]) [tags addObject:@"hidden"];
            } else {
                [tags removeObject:@"hidden"];
            }
            plist[@"SBAppTags"] = tags;

            NSError *err = nil;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:&err];
            if (err || !data) {
                printf("Error serialize: %s\n", [[err localizedDescription] UTF8String]);
                return 3;
            }

            BOOL ok = [data writeToFile:plistPath options:NSDataWritingAtomic error:&err];
            if (!ok) {
                ok = [data writeToFile:plistPath atomically:NO];
                if (!ok) {
                    printf("Error write (uid=%d): %s\n", getuid(), [[err localizedDescription] UTF8String]);
                    return 4;
                }
            }
            chown([plistPath UTF8String], 33, 33);
            chmod([plistPath UTF8String], 0644);
            printf("Success\n");
            return 0;
        }

        // 3. Rename
        if ([cmd isEqualToString:@"rename"] && argc >= 4) {
            NSString *plistPath = [NSString stringWithUTF8String:argv[2]];
            NSString *newName = [NSString stringWithUTF8String:argv[3]];

            chmod([plistPath UTF8String], 0777);
            NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
            if (!plist) {
                printf("Error: Không thể đọc Info.plist tại %s\n", [plistPath UTF8String]);
                return 2;
            }

            plist[@"CFBundleDisplayName"] = newName;
            plist[@"CFBundleName"] = newName;

            NSError *err = nil;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:&err];
            if (err || !data) {
                printf("Error serialize: %s\n", [[err localizedDescription] UTF8String]);
                return 3;
            }

            BOOL ok = [data writeToFile:plistPath options:NSDataWritingAtomic error:&err];
            if (!ok) {
                ok = [data writeToFile:plistPath atomically:NO];
                if (!ok) {
                    printf("Error write (uid=%d): %s\n", getuid(), [[err localizedDescription] UTF8String]);
                    return 4;
                }
            }
            chown([plistPath UTF8String], 33, 33);
            chmod([plistPath UTF8String], 0644);
            printf("Success\n");
            return 0;
        }

        return 1;
    }
}
