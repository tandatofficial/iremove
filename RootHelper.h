#import <Foundation/Foundation.h>

@interface RootHelper : NSObject
+ (void)escalatePrivileges;
+ (NSArray<NSDictionary *> *)getInstalledApps;
+ (NSString *)hideAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID hide:(BOOL)hide;
+ (NSString *)renameAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID newName:(NSString *)newName;
+ (void)respring;
+ (BOOL)isFilzaInstalled;
+ (void)openInFilza:(NSString *)path;
@end
