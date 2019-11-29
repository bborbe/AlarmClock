#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <iTunesLibrary/iTunesLibrary.h>

@class ITunesData;


@interface ITunesPlayer : NSObject
{
	// iTunesData reference
	ITunesData *iTunesData;
	
	// The current movie this object is playing
	AVPlayer *movie;
	
	// Volume percentage at which to play movies
	float volumePercentage;
	
	// Current type (file, track, playlist), and information
	ITLibMediaItem *currentTrack;
	int type;
	
	// Playlist Information
	BOOL shouldShuffle;
	NSInteger playlistIndex;
	NSMutableArray<ITLibMediaItem *> *playlist;
	
	// Delegate
	id delegate;
}

- (id)initWithITunesData:(ITunesData *)dataReference;

- (void)setFileWithPath:(NSString *)file;
- (void)setTrackWithTrackID:(int)trackID;
- (void)setPlaylistWithPlaylistID:(int)playlistID usesShuffle:(BOOL)shuffleFlag;

- (BOOL)isPlaying;
- (BOOL)isFile;
- (BOOL)isTrack;
- (BOOL)isPlaylist;

- (void)play;
- (void)stop;

- (void)nextTrack;
- (void)previousTrack;

- (ITLibMediaItem *)currentTrack;

- (void)setVolume:(float)volume;

- (void)setDelegate:(id)delegate;
- (id)delegate;

@end

/**
 Method definitions for the delegate of the ITunesPlayer class
**/
@interface NSObject (ITunesPlayerDelegate)
- (void)iTunesPlayerChangedSong;
@end
