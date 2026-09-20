#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <spawn.h>
#import <unistd.h>
#import <fcntl.h>

extern char **environ;

// Tìm và chạy trollstorehelper uicache
void triggerUicache(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appDir = @"/var/containers/Bundle/Application";
    NSArray *uuids = [fm contentsOfDirectoryAtPath:appDir error:nil];
    for (NSString *u in uuids) {
        NSString *sub = [appDir stringByAppendingPathComponent:u];
        NSArray *apps = [fm contentsOfDirectoryAtPath:sub error:nil];
        for (NSString *a in apps) {
            NSString *tsHelper = [sub stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/trollstorehelper", a]];
            if ([fm fileExistsAtPath:tsHelper]) {
                pid_t pid;
                const char *args[] = {[tsHelper UTF8String], "uicache", NULL};
                posix_spawn(&pid, args[0], NULL, NULL, (char * const *)args, environ);
                waitpid(pid, NULL, 0);
                return;
            }
        }
    }

    // Kiểm tra /Applications
    NSArray *systemApps = [fm contentsOfDirectoryAtPath:@"/Applications" error:nil];
    for (NSString *a in systemApps) {
        NSString *tsHelper = [NSString stringWithFormat:@"/Applications/%@/trollstorehelper", a];
        if ([fm fileExistsAtPath:tsHelper]) {
            pid_t pid;
            const char *args[] = {[tsHelper UTF8String], "uicache", NULL};
            posix_spawn(&pid, args[0], NULL, NULL, (char * const *)args, environ);
            waitpid(pid, NULL, 0);
            return;
        }
    }
}

// Khởi động lại SpringBoard ngay lập tức bằng SIGKILL (tương tự TrollStore respring)
void doRespring(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
            int count = (int)(size / sizeof(struct kinfo_proc));
            for (int i = 0; i < count; i++) {
                if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
                    kill(procs[i].kp_proc.p_pid, SIGKILL);
                }
            }
            free(procs);
        }
    }
}

// Ghi dữ liệu trực tiếp bằng POSIX low-level I/O để tránh lỗi directory permission của NSData
BOOL writeDirectly(NSString *path, NSData *data) {
    const char *cPath = [path UTF8String];
    chmod(cPath, 0777);

    int fd = open(cPath, O_WRONLY | O_TRUNC | O_CREAT, 0666);
    if (fd >= 0) {
        write(fd, [data bytes], [data length]);
        close(fd);
        chown(cPath, 33, 33);
        chmod(cPath, 0644);
        return YES;
    }

    // Fallback
    BOOL ok = [data writeToFile:path atomically:NO];
    chown(cPath, 33, 33);
    chmod(cPath, 0644);
    return ok;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Leo quyền root tối cao
        setuid(0);
        seteuid(0);
        setgid(0);
        setegid(0);

        if (argc < 2) {
            printf("iRemove Root Helper\n");
            return 1;
        }

        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        // 1. Respring
        if ([cmd isEqualToString:@"respring"]) {
            triggerUicache();
            doRespring();
            printf("Respring executed\n");
            return 0;
        }

        // 2. Hide / Unhide
        if ([cmd isEqualToString:@"hide"] && argc >= 4) {
            NSString *plistPath = [NSString stringWithUTF8String:argv[2]];
            BOOL hide = atoi(argv[3]) != 0;

            NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
            if (!plistData) {
                printf("Error: Không thể đọc Info.plist tại %s\n", [plistPath UTF8String]);
                return 2;
            }

            NSPropertyListFormat format;
            NSError *err = nil;
            NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                                  options:NSPropertyListMutableContainersAndLeaves
                                                                                   format:&format
                                                                                    error:&err];
            if (!plist || err) {
                printf("Error parse: %s\n", [[err localizedDescription] UTF8String]);
                return 3;
            }

            NSMutableArray *tags = [plist[@"SBAppTags"] mutableCopy] ?: [NSMutableArray array];
            if (hide) {
                if (![tags containsObject:@"hidden"]) [tags addObject:@"hidden"];
            } else {
                [tags removeObject:@"hidden"];
            }
            plist[@"SBAppTags"] = tags;

            NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                         format:format
                                                                        options:0
                                                                          error:&err];
            if (!outData || err) {
                printf("Error serialize: %s\n", [[err localizedDescription] UTF8String]);
                return 4;
            }

            if (!writeDirectly(plistPath, outData)) {
                printf("Error: Không thể ghi file (errno=%d)\n", errno);
                return 5;
            }

            triggerUicache();
            printf("Success\n");
            return 0;
        }

        // 3. Rename
        if ([cmd isEqualToString:@"rename"] && argc >= 4) {
            NSString *plistPath = [NSString stringWithUTF8String:argv[2]];
            NSString *newName = [NSString stringWithUTF8String:argv[3]];

            NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
            if (!plistData) {
                printf("Error: Không thể đọc Info.plist tại %s\n", [plistPath UTF8String]);
                return 2;
            }

            NSPropertyListFormat format;
            NSError *err = nil;
            NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                                  options:NSPropertyListMutableContainersAndLeaves
                                                                                   format:&format
                                                                                    error:&err];
            if (!plist || err) {
                printf("Error parse: %s\n", [[err localizedDescription] UTF8String]);
                return 3;
            }

            plist[@"CFBundleDisplayName"] = newName;
            plist[@"CFBundleName"] = newName;

            NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                         format:format
                                                                        options:0
                                                                          error:&err];
            if (!outData || err) {
                printf("Error serialize: %s\n", [[err localizedDescription] UTF8String]);
                return 4;
            }

            if (!writeDirectly(plistPath, outData)) {
                printf("Error: Không thể ghi file (errno=%d)\n", errno);
                return 5;
            }

            triggerUicache();
            printf("Success\n");
            return 0;
        }

        return 1;
    }
}
