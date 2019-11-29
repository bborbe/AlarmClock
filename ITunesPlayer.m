/**
 The ITunesPlayer class provides functionallity for playing items in the iTunes library.
 It can play tracks or entire playlists.
 
 @author Robbie Hanson
**/

#import "ITunesPlayer.h"
#import "ITunesData.h"
#import <stdlib.h>

#define TYPE_FILE      0
#define TYPE_TRACK     1
#define TYPE_PLAYLIST  2

@interface ITunesPlayer (PrivateAPI)
- (void)setMovieWithTrack:(ITLibMediaItem *)track;
- (void)shufflePlaylist;
- (double)randomDouble;
@end


@implementation ITunesPlayer

// INITIALIZATION
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 This method is automatically called (courtesy of Cocoa) before the first instantiation of this class.
 We use it to seed the random number generator.
**/
+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		// Seed the random number generator with the time
		srandom((unsigned int) time(NULL));
		
		initialized = YES;
	}
}

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Creates a new ITunesPlayer which references the given ITunesData.
**/
- (id)initWithITunesData:(ITunesData *)dataReference
{
	if(self = [super init])
	{
		// Retain reference to existing iTunesData
		iTunesData = [dataReference retain];
		
		// Configure default volume
		volumePercentage = 1.0;
		
		// Register for notifications
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(movieFinished:)
													 name:AVPlayerItemDidPlayToEndTimeNotification
												   object:movie.currentItem];
		
//		[movie addObserver:self forKeyPath:@"status" options:0 context:nil];
	}
	return self;
}

/**
 Don't forget to tidy up afterwards!
**/
- (void)dealloc
{
	// NSLog(@"Destroying %@", self);
	
	// Remove notification observers
	[[NSNotificationCenter defaultCenter] removeObserver:self];
//    [movie removeObserver:self forKeyPath:@"status"];
	
	// Remove any objects we created
	[iTunesData release];
	[movie release];
	[currentTrack release];
	[playlist release];
	
	// Move up the inheritance chain
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sets the player to play ths specified file.
 * 
 * If the player is currently playing a movie, the player is stopped, and the movie is released.
 * The player is automatically properly configured to repeat the track.
 * 
 * @param file - String that points to a file on the local filesystem.
**/
- (void)setFileWithPath:(NSString *)filepath
{
	// Stop and release the current movie if needed
	if(movie != nil)
	{
		[movie pause];
		[movie release];
		movie = nil;
	}
	
	// Save playlist information
	type = TYPE_FILE;
	
	// Set the movie
	NSURL *url = [NSURL fileURLWithPath:filepath];
	
	movie = [[AVPlayer alloc] initWithURL:url];
	[movie setVolume:volumePercentage];
	movie.actionAtItemEnd = AVPlayerActionAtItemEndNone;
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(movieRestart:)
												 name:AVPlayerItemDidPlayToEndTimeNotification
											   object:[movie currentItem]];
	
	[currentTrack release];
	currentTrack = nil;
}

/**
 * Private method to set the movie from the given track.
 * 
 * If the player is currently playing a movie, the player is stopped, and the movie is released.
 * Does not configure the movie's attributes.
 * Does not configure playlist information, or type variable.
 * 
 * @param track - An extracted track from the iTunesData dictionary.
**/
- (void)setMovieWithTrack:(ITLibMediaItem *)track
{
	// Stop and release the current movie if needed
	if(movie != nil)
	{
		[movie pause];
		[movie release];
		movie = nil;
	}
	
	// Save info about this track
	[currentTrack release];
	currentTrack = [track retain];
	
	// And double-check we're not working with a nil track
	// This would be the case if we encountered a bogus trackID
	if(track != nil)
	{
		// Assume the location points to a standard audio file
		movie = [[AVPlayer alloc] initWithURL:[track location]];
		
		// Now we check for any DRM, if necessary
		if(movie.currentItem.asset.hasProtectedContent) {
			NSLog(@"Not authorized to play track: %@", [track title]);
			[movie release];
			movie = nil;
		}
	}
}

/**
 Configures the player to play the specified trackID within iTunes.
 
 If the player is currently playing a movie, the player is stopped, and the movie is released.
 The player is automatically properly configured to repeat the track.
 
 @param trackID - ID of the track in the iTunes library.
**/
- (void)setTrackWithTrackID:(int)trackID
{
	// Stop and release the current movie if needed
	if(movie != nil)
	{
		[movie pause];
		[movie release];
		movie = nil;
	}
	
	// Save playlist information
	type = TYPE_TRACK;
	
	// Get the specified track from the iTunesData, and use it to set the movie
	[self setMovieWithTrack:[iTunesData trackForID:trackID]];
	
	// Since we're only using a single track, make sure it loops
	[movie setVolume:volumePercentage];
//	[movie setAttribute:[NSNumber numberWithBool:YES] forKey:QTMovieLoopsAttribute];
}

/**
 Configures the player to play the specified playlist within iTunes.
 
 If the player is currently playing a movie, the player is stopped, and the movie is released.
 The player is configured not to repeat the current track.
 The movieFinished method will take care of moving to the next track after the current track finishes.
 
 @param playlistID  ID of the playlist in the iTunes library.
**/
- (void)setPlaylistWithPlaylistID:(int)playlistID usesShuffle:(BOOL)shuffleFlag;
{
	// Stop and release the current movie if needed
	if(movie != nil)
	{
		[movie pause];
		[movie release];
		movie = nil;
	}
	
	// Save playlist information
	type = TYPE_PLAYLIST;
	shouldShuffle = shuffleFlag;
	
	// Fetch the desired playlist
	ITLibPlaylist *playlistObject = [iTunesData playlistForID:playlistID];
	NSArray<ITLibMediaItem *> *playlistArray = [playlistObject items];
	
	// Copy the playlistArray into our own playlist array
	// And don't forget to recycle the old playlist (since this method may be called multiple times)
	[playlist autorelease];
	playlist = [[playlistArray mutableCopy] retain];
	
	// Shuffle the playlist if needed
	if(shouldShuffle)
	{
		[self shufflePlaylist];
	}
	
	
	// We can stop now if the playlist is empty
	// This also avoids a divide by zero crash when doing modulus division
	if([playlist count] > 0)
	{
		// Setup playlistIndex
		// playlistIndex always points the the currently playing song in the playlist
		// -1 because it's immediately incremented in the loop below
		playlistIndex = -1;
		
		int loopCount = 0;
		do
		{
			// Increment playlistIndex, looping if needed
			playlistIndex = ++playlistIndex % [playlist count];
			
			[self setMovieWithTrack:[playlist objectAtIndex:playlistIndex]];
			
			// We don't configure the movie to loop, but we still need to set its volume
			[movie setVolume:volumePercentage];
			
			// Increment loopCount
			// We use a loopCount for simplicity (think about a playlist with only 1 item)
			loopCount++;
		}
		while((movie == nil) && (loopCount < [playlist count]));
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Player Status Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isPlaying
{
	return (movie != nil) && ([movie rate] != 0);
}

- (BOOL)isFile
{
	return (type == TYPE_FILE);
}

- (BOOL)isTrack
{
	return (type == TYPE_TRACK);
}

- (BOOL)isPlaylist
{
	return (type == TYPE_PLAYLIST);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Player Control Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Plays/Resumes the player.
 
 If the track or playlist has not been set, this method has no effect.
 If a track or playlist has been set, and a series of play/stop methods have been invoked, the player starts playing
 where it left off (unpauses).
**/
- (void)play
{
	if(movie != nil)
	{
		[movie play];
		
		NSError* error = [movie error];
		if (error) {
			[[NSApplication sharedApplication] presentError:error];
		}
	}
}


/*!
 Stops/Pauses the player from playing.
 
 If the track or playlist has not been set, or the movie is not playing,
 this method has no effect.
*/
- (void)stop
{
	if(movie != nil)
	{
		[movie pause];
	}
}

/**
 Moves the player to the next track.
 If we are only playing a single track or file, the file is started over from the beginning.
 If the player is playing when this method is invoked, the next track is automatically started.
**/
- (void)nextTrack
{
	// Ignore the command if no movie is loaded
	if(movie == nil)
	{
		NSLog(@"Ignoring nextTrack message because movie isn't configured yet.");
		return;
	}
	
	// Take care of the situation when not using a playlist
	if(type != TYPE_PLAYLIST)
	{
		// In this case all we can do is start the song over from the beginning
		[movie seekToTime:kCMTimeZero];
		return;
	}
	
	// Record playing status of current movie
	// If it's playing, then after we switch tracks, we should continue playing
	BOOL wasPlaying = [self isPlaying];
	
	// Perform the standard procedure for moving to the next track
	int loopCount = 0;
	do
	{
		// Increment playlistIndex, looping if needed
		playlistIndex = ++playlistIndex % [playlist count];
		
		// If we've made it all the way back to the beginning of the playlist
		// And we're using shuffle, then follow iTunes' lead, and reshuffle
		if((playlistIndex == 0) && shouldShuffle)
		{
			[self shufflePlaylist];
		}
		
		[self setMovieWithTrack:[playlist objectAtIndex:playlistIndex]];
		
		// We don't configure the movie to loop, but we still need to set its volume
		[movie setVolume:volumePercentage];
		
		// Increment loopCount
		// We use a loopCount because playlistIndex doesn't start from the beginning
		loopCount++;
	}
	while((movie == nil) && (loopCount < [playlist count]));
	
	// If we were playing before we switched tracks, we should continue playing now
	if(wasPlaying) [self play];
	
	// Send delegate notification that the song has changed
	if([delegate respondsToSelector:@selector(iTunesPlayerChangedSong)])
	{
		[delegate iTunesPlayerChangedSong];
	}
}

/**
 Moves the player to the previous track.
 If we are only playing a single track or file, the file is started over from the beginning.
 If the player is playing when this method is invoked, the previous track is automatically started.
**/
- (void)previousTrack
{
	// Ignore the command if no movie is loaded
	if(movie == nil)
	{
		NSLog(@"Ignoring previousTrack message because movie isn't configured yet.");
		return;
	}
	
	// Take care of the situation when not using a playlist
	if(type != TYPE_PLAYLIST)
	{
		// In this case all we can do is start the song over from the beginning
		[movie seekToTime:kCMTimeZero];
		return;
	}
	
	// Now remember what happens if you hit previous in iTunes...
	// If you hit previous in the middle of the song, it goes to the beginning of the song
	// Only if you hit previous in the first 3 seconds of the song, do you actually go to the previous song
	
	// Get the current time of the movie that's playing
	CMTime currentTime = [movie currentTime];
	
	// QTTime is a structure which contains the timeValue (long long), and timeScale (long)
	// We can determine the number of seconds into the song by division
	NSInteger seconds = currentTime.value / currentTime.timescale;
	if(seconds >= 3)
	{
		[movie seekToTime:kCMTimeZero];
		return;
	}
	
	// Record playing status of current movie
	// If it's playing, then after we switch tracks, we should continue playing
	BOOL wasPlaying = [self isPlaying];
	
	// Perform the standard procedure for moving to the previous track
	int loopCount = 0;
	do
	{
		// Decrement playlistIndex, looping if needed
		playlistIndex--;
		if(playlistIndex < 0)
		{
			playlistIndex = [playlist count] - 1;
		}
		
		[self setMovieWithTrack:[playlist objectAtIndex:playlistIndex]];
		
		// We don't configure the movie to loop, but we still need to set its volume
		[movie setVolume:volumePercentage];
		
		// Increment loopCount
		// We use a loopCount because playlistIndex doesn't start from the beginning
		loopCount++;
	}
	while((movie == nil) && (loopCount < [playlist count]));
	
	// If we were playing before we switched tracks, we should continue playing now
	if(wasPlaying) [self play];
	
	// Send delegate notification that the song has changed
	if([delegate respondsToSelector:@selector(iTunesPlayerChangedSong)])
	{
		[delegate iTunesPlayerChangedSong];
	}
}

/**
 Returns a dictionary with information about the currently playing song.
**/
- (ITLibMediaItem *)currentTrack
{
	return currentTrack;
}

/**
 Sets the volume of the player.
 Note: This is the volume of this player, NOT the system volume.
 
 @param percent - Percentage of volume. The valid range is 0.0 to 1.0.
**/
- (void)setVolume:(float)percent
{
	// Some users use the application for reminders (like at work and such)
	// Therefore, setting the volume to 0% is just fine
	if(percent < 0.00)
		volumePercentage = 0.00;
	else if(percent > 1.00)
		volumePercentage = 1.00;
	else
		volumePercentage = percent;
	
	if(movie != nil)
	{
		[movie setVolume:volumePercentage];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delegate Setup:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)delegate
{
	return delegate;
}

- (void)setDelegate:(id)newDelegate 
{
	delegate = newDelegate;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notification Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when a song has finished playing.
 * 
 * This method facilitates the playlist functionality.
 * It switches the movie to the next song in the playlist and plays it.
**/
- (void)movieFinished:(NSNotification *)notification
{
	// This method is called for every movie in the application finishing
	// Check to make sure the movie is the one we're looking for
	if((type == TYPE_PLAYLIST) && (movie.currentItem == [notification object]))
	{
		// Goto the next track in the playlist
		[self nextTrack];
		
		// And start playing it
		[self play];
	}
}

/**
 * Called when a song has finished playing.
 *
 * This method restarts playback.
 **/
- (void)movieRestart:(NSNotification *)notification
{
    // This method is called for every movie in the application finishing
    // Check to make sure the movie is the one we're looking for
    if(movie.currentItem == [notification object])
    {
        AVPlayerItem *p = [notification object];
        [p seekToTime:kCMTimeZero];
    }
}

/**
 * This method is called when the load state of a movie changes.
 * It will be called multiple times as the movie continues to load.
 * 
 * We use this method to immediately start playing the movie as soon as it's ready.
**/
//
//
//- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
//                        change:(NSDictionary *)change context:(void *)context {
//    if (object == movie && [keyPath isEqualToString:@"status"]) {
//        if (movie.status == AVPlayerStatusReadyToPlay) {
//            NSLog(@"ITunesPlayer: state: AVPlayerStatusReadyToPlay");
////            if(shouldPlay && ![self isPlaying]) {
////                [self play];
////            }
//        } else if (movie.status == AVPlayerStatusFailed) {
//            NSLog(@"ITunesPlayer: state: AVPlayerStatusFailed");
//        } else if (movie.status == AVPlayerStatusUnknown) {
//            NSLog(@"ITunesPlayer: state: AVPlayerStatusUnknown");
//        } else {
//            NSLog(@"ITunesPlayer: state: unknown");
//        }
//
//    }
//}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Helper Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Shuffles the playlist mutable array.
 This method assume that the playlist array is already setup.
**/
- (void)shufflePlaylist
{
	NSMutableArray *shuffledPlaylist = [NSMutableArray arrayWithCapacity:[playlist count]];
	
	while([playlist count] > 0)
	{
		// Randomly choose an index in the playlist
		int randomIndex = [self randomDouble] * [playlist count];
		
		// Then add the index to playlist, and remove it from tempArray
		[shuffledPlaylist addObject:[playlist objectAtIndex:randomIndex]];
		[playlist removeObjectAtIndex:randomIndex];
	}
	
	[playlist release];
	playlist = [shuffledPlaylist retain];
}

/**
 Returns a double in the range (0, 1]
 IE - from 0 (inclusive) to 1 (non inclusive).
 
 Note: The random number generator was seeded upon initilization of this class.
**/
- (double)randomDouble
{
	return random() / (RAND_MAX + 1.0);
}

@end
