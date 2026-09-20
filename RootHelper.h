#import <Foundation/Foundation.h>

@interface RootHelper : NSObject
+ (void)escalatePrivileges;
+ (NSArray<NSDictionary *> *)getInstalledApps;
+ (NSString *)hideAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID hide:(BOOL)hide;
+ (NSString *)renameAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID newName:(NSString *)newName;
+ (NSString *)changeIconAtPath:(NSString *)appPath bundleID:(NSString *)bundleID iconData:(NSData *)newIconPngData;
+ (void)refreshCacheForPath:(NSString *)appPath bundleID:(NSString *)bundleID;
+ (void)respring;
@end
