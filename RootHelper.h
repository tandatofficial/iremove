#import <Foundation/Foundation.h>

@interface RootHelper : NSObject
+ (NSArray<NSDictionary *> *)getInstalledApps;
+ (BOOL)hideAppAtPath:(NSString *)appPath hide:(BOOL)hide;
+ (BOOL)renameAppAtPath:(NSString *)appPath newName:(NSString *)newName;
+ (BOOL)changeIconAtPath:(NSString *)appPath iconData:(NSData *)newIconPngData;
+ (void)refreshCacheForPath:(NSString *)appPath;
@end
