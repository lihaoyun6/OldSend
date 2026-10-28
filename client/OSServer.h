#import <Foundation/Foundation.h>

@class UIAlertView;

extern NSString * const OSServerDidUpdateNotification;
extern NSString * const OSServerSendDidFinishNotification;
extern NSString * const OSServerSendProgressNotification;
extern NSString * const OSServerDidReceiveTextNotification;

@interface OSServer : NSObject {
@private
    volatile BOOL _running;
    BOOL _refreshingDevices;
    NSString *_alias;
    NSString *_model;
    NSString *_fingerprint;
    NSString *_localIP;
    NSString *_status;
    NSMutableArray *_log;
    NSMutableArray *_devices;
    NSTimer *_announceTimer;
    void *_identity;
    NSCondition *_photoCondition;
    BOOL _photoSaveInProgress;
    BOOL _photoFinished;
    BOOL _photoSuccess;
    NSUInteger _photoSaveToken;
    NSUInteger _photoActiveToken;
    NSString *_photoActivePath;
    NSInteger _savingCount;
    NSInteger _pendingReceiveCompleteCount;
    NSString *_receiveStatus;
    NSCondition *_decisionCondition;
    BOOL _decisionMade;
    BOOL _decisionAccepted;
    UIAlertView *_decisionAlert;
    BOOL _receiving;
    BOOL _sessionActive;
    float _uploadProgress;
    long long _sessionTotalBytes;
    long long _sessionBaseBytes;
    long long _currentFileWritten;
    float _sessionProgress;
    NSString *_uploadName;
    NSMutableArray *_photoQueue;
    BOOL _photoQueueRunning;
    NSMutableArray *_receivedTexts;
    NSTimer *_receiveWatchdog;
    NSTimeInterval _lastReceiveActivity;
}

+ (OSServer *)shared;
+ (NSString *)localIPAddress;
+ (NSString *)generateAlias;

- (void)start;
- (void)stop;
- (void)announceNow;
- (void)refreshDevices;

- (NSString *)alias;
- (void)setAlias:(NSString *)alias;
- (NSString *)statusText;
- (NSString *)receiveStatus;
- (BOOL)isSavingToPhotos;
- (BOOL)isReceiving;
- (BOOL)isSessionActive;
- (float)uploadProgress;
- (NSString *)uploadName;
- (NSString *)fingerprint;
- (NSString *)localIP;
- (int)port;
- (NSArray *)devices;
- (NSArray *)receivedFiles;
- (BOOL)deleteReceivedFile:(NSDictionary *)file;
- (NSArray *)logLines;

- (void)sendItems:(NSArray *)items toDevice:(NSDictionary *)device;
- (void)cancelSending;

- (void)appendLog:(NSString *)line;

@end
