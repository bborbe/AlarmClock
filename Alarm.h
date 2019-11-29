#import <Foundation/Foundation.h>

#define ALARMTYPE_DEFAULT  0
#define ALARMTYPE_TRACK    1
#define ALARMTYPE_PLAYLIST 2

@interface Alarm : NSObject <NSCopying>
{
	BOOL isEnabled;
	BOOL usesShuffle;
	BOOL usesEasyWake;
	int schedule;
	int type;
	int trackID;
	int playlistID;
	NSNumber *persistentTrackID;
	NSNumber *persistentPlaylistID;
	NSDate *time;
}

// Global Class Methods
+ (NSString *)defaultAlarmFile;

// Init routines
- (id)init;
- (id)initWithDict:(NSDictionary *)dict;

// For alarm comparisons
- (BOOL)isEqualToAlarm:(Alarm *)anAlarm;

// For saving to the userDefaults dictionary
- (NSDictionary *)prefsDictionary;

// For updating the time of alarms
- (BOOL)updateTime;
- (void)updateTimeZone;

// Get and Set Methods

- (BOOL)isEnabled;
- (void)setIsEnabled:(BOOL)newStatus;

- (BOOL)usesShuffle;
- (void)setUsesShuffle:(BOOL)shuffleFlag;

- (BOOL)usesEasyWake;
- (void)setUsesEasyWake:(BOOL)easyWakeFlag;

- (int)schedule;
- (void)setSchedule:(int)schedule;

- (BOOL)isTrack;
- (BOOL)isPlaylist;
- (void)setType:(int)type;

- (int)trackID;
- (NSNumber *)persistentTrackID;
- (void)setTrackID:(int)trackID withPersistentTrackID:(NSNumber *)persistentTrackID;

- (int)playlistID;
- (NSNumber *)persistentPlaylistID;
- (void)setPlaylistID:(int)playlistID withPersistentPlaylistID:(NSNumber *)persistentPlaylistID;

- (NSDate *)time;
- (void)setTime:(NSDate *)time;

@end
