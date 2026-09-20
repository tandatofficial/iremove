#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <spawn.h>
#import <unistd.h>
#import <fcntl.h>

extern char **environ;

// Ghi đè file cấp thấp POSIX
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

    BOOL ok = [data writeToFile:path atomically:NO];
    chown(cPath, 33, 33);
    chmod(cPath, 0644);
    return ok;
}

// Cập nhật tất cả các file InfoPlist.strings trong mọi thư mục ngôn ngữ (*.lproj)
void updateAllLprojStrings(NSString *appPath, NSString *newName) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:appPath error:nil];
    for (NSString *item in items) {
        if ([item hasSuffix:@".lproj"]) {
            NSString *lprojDir = [appPath stringByAppendingPathComponent:item];
            NSString *stringsPath = [lprojDir stringByAppendingPathComponent:@"InfoPlist.strings"];
            
            if ([fm fileExistsAtPath:stringsPath]) {
                NSData *data = [NSData dataWithContentsOfFile:stringsPath];
                if (data) {
                    NSPropertyListFormat fmt;
                    NSError *err = nil;
                    NSMutableDictionary *dict = [NSPropertyListSerialization propertyListWithData:data
                                                                                          options:NSPropertyListMutableContainersAndLeaves
                                                                                           format:&fmt
                                                                                            error:&err];
                    if (dict && [dict isKindOfClass:[NSMutableDictionary class]]) {
                        dict[@"CFBundleDisplayName"] = newName;
                        dict[@"CFBundleName"] = newName;
                        NSData *outData = [NSPropertyListSerialization dataWithPropertyList:dict
                                                                                     format:fmt
                                                                                    options:0
                                                                                      error:nil];
                        if (outData) {
                            writeDirectly(stringsPath, outData);
                        }
                    }
                }
            }
        }
    }
}

// Gọi uicache của TrollStore
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
}

// Respring SpringBoard bằng SIGKILL
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

int main(int argc, char *argv[]) {
    @autoreleasepool {
        setuid(0);
        seteuid(0);
        setgid(0);
        setegid(0);

        if (argc < 2) return 1;

        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        if ([cmd isEqualToString:@"respring"]) {
            triggerUicache();
            doRespring();
            return 0;
        }

        // Ẩn / Bỏ ẩn app
        if ([cmd isEqualToString:@"hide"] && argc >= 4) {
            NSString *appPath = [NSString stringWithUTF8String:argv[2]];
            BOOL hide = atoi(argv[3]) != 0;
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];

            NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
            if (!plistData) return 2;

            NSPropertyListFormat fmt;
            NSError *err = nil;
            NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                                  options:NSPropertyListMutableContainersAndLeaves
                                                                                   format:&fmt
                                                                                    error:&err];
            if (!plist || err) return 3;

            NSMutableArray *tags = [plist[@"SBAppTags"] mutableCopy] ?: [NSMutableArray array];
            if (hide) {
                if (![tags containsObject:@"hidden"]) [tags addObject:@"hidden"];
            } else {
                [tags removeObject:@"hidden"];
            }
            plist[@"SBAppTags"] = tags;

            NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist format:fmt options:0 error:nil];
            if (!outData || !writeDirectly(plistPath, outData)) return 4;

            triggerUicache();
            return 0;
        }

        // Đổi tên app: Can thiệp CẢ Info.plist VÀ tất cả *.lproj/InfoPlist.strings
        if ([cmd isEqualToString:@"rename"] && argc >= 4) {
            NSString *appPath = [NSString stringWithUTF8String:argv[2]];
            NSString *newName = [NSString stringWithUTF8String:argv[3]];
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];

            // 1. Cập nhật Info.plist
            NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
            if (plistData) {
                NSPropertyListFormat fmt;
                NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                                      options:NSPropertyListMutableContainersAndLeaves
                                                                                       format:&fmt
                                                                                        error:nil];
                if (plist) {
                    plist[@"CFBundleDisplayName"] = newName;
                    plist[@"CFBundleName"] = newName;
                    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist format:fmt options:0 error:nil];
                    if (outData) {
                        writeDirectly(plistPath, outData);
                    }
                }
            }

            // 2. Cập nhật toàn bộ các file bản địa hóa vi.lproj, en.lproj, Base.lproj...
            updateAllLprojStrings(appPath, newName);

            triggerUicache();
            return 0;
        }

        return 1;
    }
}
