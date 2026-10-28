#import "FileTypeIcon.h"

NSString *OSFileTypeIconName(NSString *fileName) {
    static NSDictionary *icons = nil;
    NSString *extension;
    NSString *icon;

    if (icons == nil) {
        icons = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"jpeg", @"jpg", @"jpeg", @"jpeg", @"png", @"png", @"gif", @"gif",
            @"bmp", @"bmp", @"tiff", @"tif", @"tiff", @"tiff", @"ico", @"ico",
            @"video", @"mp4", @"video", @"mov", @"video", @"m4v", @"video", @"avi",
            @"video", @"mkv", @"video", @"wmv", @"mpeg", @"mpg", @"mpeg", @"mpeg",
            @"3gpp", @"3gp", @"3gpp", @"3gpp", @"flash", @"flv", @"flash", @"swf",
            @"mp3", @"mp3", @"aac", @"aac", @"aiff", @"aiff", @"wav", @"wav",
            @"m4r", @"m4r", @"m3u", @"m3u", @"mp2", @"mp2", @"sound", @"m4a",
            @"sound", @"ogg", @"sound", @"flac",
            @"text", @"txt", @"text", @"md", @"text", @"csv", @"rtf", @"rtf",
            @"html", @"html", @"html", @"htm", @"css", @"css", @"js", @"js",
            @"log", @"log", @"config", @"plist", @"config", @"xml",
            @"config", @"json", @"config", @"conf", @"config", @"ini",
            @"zip", @"zip", @"tar", @"tar", @"gz", @"gz", @"bz2", @"bz2",
            @"tbz2", @"tbz2", @"tgz", @"tgz", @"compressed", @"rar",
            @"compressed", @"7z", @"compressed", @"deb", @"compressed", @"ipa",
            @"pdf", @"pdf", @"doc", @"doc", @"doc", @"docx", @"ppt", @"ppt",
            @"ppt", @"pptx", @"ppt", @"pps", @"spreadsheet", @"xls",
            @"spreadsheet", @"xlsx", @"pages", @"pages", @"numbers", @"numbers",
            @"keynote", @"keynote", @"xib", @"xib",
            @"c", @"c", @"cpp", @"cpp", @"h", @"h", @"m", @"m", @"java", @"java",
            @"sqlite3", @"sqlite", @"sqlite3", @"sqlite3", @"sqlite3", @"db",
            @"diskimage", @"iso", @"diskimage", @"dmg",
            @"folder", @"folder",
            nil];
    }

    extension = [[fileName pathExtension] lowercaseString];
    icon = [icons objectForKey:extension];
    if (icon == nil) icon = @"empty";
    return [icon stringByAppendingString:@".png"];
}
