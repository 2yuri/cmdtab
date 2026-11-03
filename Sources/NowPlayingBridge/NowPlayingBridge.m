// What's playing, for the CmdTab island.
//
// macOS only answers MediaRemote ("Now Playing") questions from Apple's own programs, so CmdTab runs
// this library inside /usr/bin/perl: `cmdtab_now_playing_stream()` prints one JSON line each time
// the track or playback changes and reads commands ("toggle", "next", "previous", "seek 42.5")
// from stdin. When CmdTab goes away stdin closes and the process exits. Nothing polls: it sleeps
// until MediaRemote posts a change.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>

typedef void (*MRRegister)(dispatch_queue_t);
typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPID)(dispatch_queue_t, void (^)(int));
typedef Boolean (*MRSendCommand)(int, NSDictionary *);
typedef void (*MRSetElapsed)(double);

static MRRegister registerForNotifications;
static MRGetInfo getInfo;
static MRGetIsPlaying getIsPlaying;
static MRGetPID getPID;
static MRSendCommand sendCommand;
static MRSetElapsed setElapsed;
static dispatch_queue_t queue;
static NSString *lastArtworkKey;

static BOOL load(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) return NO;
    registerForNotifications = (MRRegister)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    getInfo = (MRGetInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetIsPlaying)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (MRGetPID)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = (MRSendCommand)dlsym(handle, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsed)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    return registerForNotifications && getInfo && getIsPlaying && getPID && sendCommand;
}

static void emit(NSDictionary *object) {
    if (![NSJSONSerialization isValidJSONObject:object]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    if (fflush(stdout) != 0 || ferror(stdout)) exit(0);
}

static id value(id object) {
    // Live streams report an infinite duration, which JSON can't carry.
    if ([object isKindOfClass:[NSNumber class]] && !isfinite([object doubleValue])) return [NSNull null];
    return object ?: [NSNull null];
}

static void report(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getIsPlaying(queue, ^(Boolean playing) {
            getPID(queue, ^(int pid) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                out[@"pid"] = @(pid);
                out[@"title"] = value(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
                out[@"artist"] = value(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                out[@"album"] = value(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                out[@"duration"] = value(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                out[@"elapsed"] = value(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                out[@"rate"] = value(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                out[@"timestamp"] = timestamp ? value(@([timestamp timeIntervalSince1970])) : [NSNull null];
                // Artwork only when it changes: it's the big part.
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *key = [NSString stringWithFormat:@"%@|%@|%lu", info[@"kMRMediaRemoteNowPlayingInfoTitle"],
                                 info[@"kMRMediaRemoteNowPlayingInfoAlbum"], (unsigned long)artwork.length];
                if (artwork.length > 0 && ![key isEqualToString:lastArtworkKey]) {
                    out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                    lastArtworkKey = key;
                } else if (artwork.length == 0) {
                    out[@"artwork"] = @"";
                    lastArtworkKey = nil;
                }
                emit(out);
            });
        });
    });
}

static void handle(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    // MRMediaRemoteCommand values.
    if ([command isEqualToString:@"toggle"]) sendCommand(2, nil);
    else if ([command isEqualToString:@"next"]) sendCommand(4, nil);
    else if ([command isEqualToString:@"previous"]) sendCommand(5, nil);
    else if ([command isEqualToString:@"shuffle"]) sendCommand(6, nil);
    else if ([command isEqualToString:@"seek"] && parts.count > 1 && setElapsed) setElapsed(parts[1].doubleValue);
}

void cmdtab_now_playing_stream(void) {
    if (!load()) { emit(@{@"error": @"unavailable"}); exit(0); }
    queue = dispatch_queue_create("dev.yuri.CmdTab.NowPlaying", DISPATCH_QUEUE_SERIAL);
    registerForNotifications(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(queue, ^{ report(); });
        }];
    }
    dispatch_async(queue, ^{ report(); });

    // Commands from CmdTab; end of input means CmdTab quit.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char buffer[256];
        while (fgets(buffer, sizeof buffer, stdin)) {
            NSString *line = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(queue, ^{ handle(line); });
        }
        exit(0);
    });
    CFRunLoopRun();
}
