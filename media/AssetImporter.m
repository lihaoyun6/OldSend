#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <dispatch/dispatch.h>

static NSString *OSWriteAssetBytes(ALAsset *asset, NSString *directory) {
    ALAssetRepresentation *representation = [asset defaultRepresentation];
    NSString *extension;
    NSString *name;
    NSString *path;
    NSFileHandle *handle;
    uint8_t *buffer;
    long long size;
    long long offset = 0;

    if (representation == nil) return nil;
    extension = [[representation filename] pathExtension];
    if ([extension length] == 0) {
        NSString *uti = [[representation UTI] lowercaseString];
        if ([uti rangeOfString:@"mpeg-4"].location != NSNotFound ||
            [uti rangeOfString:@"mp4"].location != NSNotFound) extension = @"mp4";
        else if ([uti rangeOfString:@"m4v"].location != NSNotFound) extension = @"m4v";
        else if ([uti rangeOfString:@"png"].location != NSNotFound) extension = @"png";
        else extension = @"jpg";
    }

    name = [NSString stringWithFormat:@"share-%u-%u.%@",
            (unsigned)[[NSDate date] timeIntervalSince1970],
            (unsigned)arc4random(), extension];
    path = [directory stringByAppendingPathComponent:name];
    size = [representation size];
    if (size <= 0) return nil;

    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    handle = [NSFileHandle fileHandleForWritingAtPath:path];
    buffer = (uint8_t *)malloc(256 * 1024);
    if (handle != nil && buffer != NULL) {
        while (offset < size) {
            NSUInteger length = (NSUInteger)MIN((long long)(256 * 1024), size - offset);
            NSError *error = nil;
            NSUInteger read = [representation getBytes:buffer
                                            fromOffset:offset
                                                length:length
                                                 error:&error];
            if (read == 0) break;
            [handle writeData:[NSData dataWithBytes:buffer length:read]];
            offset += read;
        }
        [handle closeFile];
    }
    if (buffer != NULL) free(buffer);

    if (offset <= 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return nil;
    }
    return name;
}

NSArray *OSExportAssetURLs(NSArray *urls, NSString *directory) {
    NSMutableArray *names = [NSMutableArray array];
    ALAssetsLibrary *library;
    NSUInteger i;

    if (![urls isKindOfClass:[NSArray class]] || directory == nil) return names;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    library = [[ALAssetsLibrary alloc] init];

    for (i = 0; i < [urls count]; i++) {
        id item = [urls objectAtIndex:i];
        NSURL *url = nil;
        __block ALAsset *asset = nil;
        dispatch_semaphore_t semaphore;

        if ([item isKindOfClass:[NSURL class]]) url = item;
        else if ([item isKindOfClass:[NSString class]]) url = [NSURL URLWithString:item];
        if (url == nil) continue;
        semaphore = dispatch_semaphore_create(0);
        [library assetForURL:url
                 resultBlock:^(ALAsset *result) {
                     asset = [result retain];
                     dispatch_semaphore_signal(semaphore);
                 }
                failureBlock:^(NSError *error) {
                     dispatch_semaphore_signal(semaphore);
                 }];
        dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 20LL * NSEC_PER_SEC));
        dispatch_release(semaphore);

        if (asset != nil) {
            NSString *name = OSWriteAssetBytes(asset, directory);
            if (name != nil) [names addObject:name];
            [asset release];
        }
    }
    [library release];
    return names;
}
