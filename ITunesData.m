#import "ITunesData.h"
#import "Prefs.h"

@implementation ITunesData

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if(self = [super init])
	{
		NSError * error = nil;
		library = [[ITLibrary alloc] initWithAPIVersion:@"1.0" error: &error];
		if (error) {
			[[NSApplication sharedApplication] presentError:error];
		}
	}
	return self;
}

- (void)dealloc
{
	NSLog(@"Destroying %@", self);
	[library release];
	[super dealloc];
}

// DATA EXTRACTION
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns array of playlist dictionaries.
 
 Returns an array, which may be accessed like any other array (objectAtIndex, count, etc...)
 Each object in the array is an NSDictionary, which contains info for that particular playlist.
 Each playlist dictionary contains the following keys (among others):
 Name - Name of playlist
 Playlist ID - Unique ID number of playlist, which should be used as name and index in array may change over time.
 Playlist Items - Array of dictionaries, each containing a track ID number.
**/
- (NSArray<ITLibPlaylist *> *)playlists
{
	return [library allPlaylists];
}

/**
Returns the playlist that has the given playlist ID.
 
 Searches all playlists for the one with the given ID.
 When this is found, it is returned.
 Otherwise, nil is returned.
 
 @param playlistID - The index of the desired playlist in the library's playlists array.
 **/
- (ITLibPlaylist *)playlistForID:(int)playlistID
{
	if(playlistID >= 0)
		return [[self playlists] objectAtIndex:playlistID];
	else
		return nil;
}

/**
 Returns the dictionary for the given track index.
  
 Each track dictionary contains the following keys (among others):
 Name - Name of song (IE - Your Body is a Wonderland)
 Artist - Name of artist (IE - John Mayer)
 Album - Name of album track is from (IE - Room For Squares)
 Total Time - Number of milliseconds in song
 Location - File URL
 
 @param trackID - The ID of the desired track in the library's `allMediaItems` array.
**/
- (ITLibMediaItem *)trackForID:(int)trackID
{
	if (trackID < [[library allMediaItems] count])
	{
		return [[library allMediaItems] objectAtIndex:trackID];
	}
	else
	{
		return nil;
	}
}

/**
 Returns the index of the track (in the main library) for the given track ID.
 
 Although tracks are stored in a dictionary, and accessed via a key (their track ID),
 an index may be needed when displaying the information in a table, and needing the position of the track.
 
 If the track is found in the library, the index of the track is returned.
 If it's not found, -1 is returned.
 
 @param trackID - The persistent ID of the desired track.
**/
- (int)trackIndexForPersistentID:(NSNumber *)trackID
{
	// Note: The main library is always the first playlist
	return [self trackIndexForPersistentID:trackID withPlaylistID:0];
}

/**
 Returns the index of the track (in the given playlist) for the given track ID.
 
 Although tracks are stored in a dictionary, and accessed via a key (their track ID),
 an index may be needed when displaying the information in a table, and needing the position of the track.
 
 If the track is found in the given playlist, the index of the track is returned.
 If it's not found, -1 is returned.
 
 @param trackID - The persistent ID of the desired track.
 @param playlistIndex - The index of the playlist that should be searched for the position of the given track.
**/
- (int)trackIndexForPersistentID:(NSNumber *)trackPersistentID withPlaylistID:(int)playlistIndex
{
	// First make sure the playlistIndex is valid
	if((playlistIndex < 0) || (playlistIndex >= [[self playlists] count]))
	{
		return -1;
	}
	
	NSArray<ITLibMediaItem *> *playlist = [[self playlistForID:playlistIndex] items];
	
	int index = 0;
	BOOL found = NO;
	while(!found && (index < [playlist count]))
	{
		NSNumber* trackRef = [[playlist objectAtIndex:index] persistentID];
		
		if([trackPersistentID isEqualToNumber:trackRef])
			found = YES;
		else
			index++;
	}
	
	if(found)
		return index;
	else
		return -1;
}


// ID VALIDATION
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns the proper trackID for the given persistentID.
 
 Track ID's are not persistent across multiple instances of iTunesData.
 Thus storing the trackID will not guarantee the same song will be played after the music library is altered.
 Luckily Apple provides a persistentID which may be used to lookup a song.
 However, the trackID is the key in which to lookup the song, so it is more or less necessary.
 
 This method provides a means with which to map a persistentID to its corresponding trackID.
 The trackID which is assumed to be correct is passed along with it.
 This helps, because often times it is correct, and thus a search may be avoided.
 
 @param trackID - The old trackID that was used for the song with this persistentID.
 @param persistentTrackID - This is the persistentID for the song, which doesn't change as the library is altered.
 
 @return The trackID that currently corresponds to the given persistentID, or -1 if the persistentID was not found.
**/
- (int)validateTrackID:(int)trackID withPersistentTrackID:(NSNumber *)persistentTrackID
{
	// Ignore the validation request if the persistentTrackID is nil (uninitialized)
	// This will happen for new alarms
	// It will also happen after upgrading to 2.2.1, where prior versions didn't support persistent ID's.
	if(persistentTrackID == nil)
	{
		return trackID;
	}
	
	// Get the track for the specified trackID
	ITLibMediaItem *item = [self trackForID:trackID];
	
	// Does the persistentID match the one given
	if((item != nil) && [[item persistentID] isEqualToNumber:persistentTrackID])
	{
		// It's a match! Just return the original trackID.
		return trackID;
	}
	
	// The trackID has changed!
	// Now we have to loop through the tracks, and find the one with the correct persistentID
	int result = -1;
		
	for (int i = 0; i < [[library allMediaItems] count]; i++)
	{
		ITLibMediaItem *currentTrack = [[library allMediaItems] objectAtIndex:i];
		if ([[currentTrack persistentID] isEqualToNumber:persistentTrackID])
		{
			result = i;
			break;
		}
	}
	
	return result;
}

/**
 Returns the proper playlistID for the given persistentID.
 
 Playlist ID's are not persistent across multiple instances of iTunesData.
 Thus storing the playlistID will not guarantee the same playlist will be played after the music library is altered.
 Luckily Apple provides a persistentID which may be used to lookup a playlist.
 However, the playlistID is the key in which to lookup the playlist, so it is more or less necessary.
 
 This method provides a means with which to map a persistentID to its corresponding playlistID.
 The playlistID which is assumed to be correct is passed along with it.
 This helps, because often times it is correct, and thus a search may be avoided.
 
 @param playlistID - The old playlistID that was used for the song with this persistentID.
 @param persistentPlaylistID - This is the persistentID for the playlist, which doesn't change as the library is altered.
 
 @return The playlistID that currently corresponds to the given persistentID, or -1 if the persistentID was not found.
**/
- (int)validatePlaylistID:(int)playlistID withPersistentPlaylistID:(NSNumber *)persistentPlaylistID
{
	// Ignore the validation request if the persistentPlaylistID is nil (uninitialized)
	// This will happen for new alarms
	// It will also happen after upgrading to 2.2.1, where prior versions didn't support persistent ID's.
	if(persistentPlaylistID == nil)
	{
		return playlistID;
	}
	
	// Get the playlist for the specified playlistID
	ITLibPlaylist *playlist = [self playlistForID:playlistID];
	
	// Does the persistentID match the one given
	if((playlist != nil) && [[playlist persistentID] isEqualToNumber:persistentPlaylistID])
	{
		// It's a match.! Just return the original playlistID.
		return playlistID;
	}
	
	// The playlistID has changed!
	// Now we have to loop through the playlists, and find the one with the correct persistentID
	int result = -1;
		
	for (int i = 0; i < [[library allPlaylists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[library allPlaylists] objectAtIndex:i];
		if ([[currentPlaylist persistentID] isEqualToNumber:persistentPlaylistID])
		{
			result = i;
			break;
		}
	}
	
	return result;
}

@end
