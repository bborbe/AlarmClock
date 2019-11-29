#import <Cocoa/Cocoa.h>
#import <iTunesLibrary/iTunesLibrary.h>

#define LIBRARY_PERSISTENTID          @"Library Persistent ID"
#define MUSIC_FOLDER                  @"Music Folder"

#define TRACK_ID                      @"Track ID"
#define TRACK_PERSISTENTID            @"Persistent ID"
#define TRACK_LOCATION                @"Location"
#define TRACK_TOTALTIME               @"Total Time"
#define TRACK_NAME                    @"Name"
#define TRACK_ARTIST                  @"Artist"
#define TRACK_ALBUM                   @"Album"
#define TRACK_TRACKNUMBER             @"Track Number"
#define TRACK_TRACKCOUNT              @"Track Count"
#define TRACK_ISPROTECTED             @"Protected"

#define PLAYLIST_ID                   @"Playlist ID"
#define PLAYLIST_PERSISTENTID         @"Playlist Persistent ID"
#define PLAYLIST_NAME                 @"Name"
#define PLAYLIST_ITEMS                @"Playlist Items"

#define PLAYLIST_PARENT_PERSISTENTID  @"Parent Persistent ID"

#define PLAYLIST_TYPE_MASTER          @"Master"
#define PLAYLIST_TYPE_MUSIC           @"Music"
#define PLAYLIST_TYPE_MOVIES          @"Movies"
#define PLAYLIST_TYPE_TVSHOWS         @"TV Shows"
#define PLAYLIST_TYPE_PODCASTS        @"Podcasts"
#define PLAYLIST_TYPE_VIDEOS          @"Videos"
#define PLAYLIST_TYPE_AUDIOBOOKS      @"Audiobooks"
#define PLAYLIST_TYPE_PURCHASED       @"Purchased Music"
#define PLAYLIST_TYPE_PARTYSHUFFLE    @"Party Shuffle"
#define PLAYLIST_TYPE_FOLDER          @"Folder"
#define PLAYLIST_TYPE_SMART           @"Smart Info"


@interface ITunesData : NSObject
{
	// Dictionary with contents of music library xml file
	ITLibrary *library;
}

- (id)init;

- (NSArray<ITLibPlaylist *> *)playlists;

- (ITLibPlaylist *)playlistForID:(int)playlistID;

- (ITLibMediaItem *)trackForID:(int)trackID;

- (int)trackIndexForPersistentID:(NSNumber *)trackID;
- (int)trackIndexForPersistentID:(NSNumber *)trackPersistentID withPlaylistID:(int)playlistID;

- (int)validateTrackID:(int)trackID withPersistentTrackID:(NSNumber *)persistentTrackID;
- (int)validatePlaylistID:(int)playlistID withPersistentPlaylistID:(NSNumber *)persistentPlaylistID;

@end
