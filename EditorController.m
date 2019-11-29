#import "EditorController.h"
#import "AlarmScheduler.h"
#import "Alarm.h"
#import "CalendarView.h"
#import "ITunesData.h"
#import "ITunesTable.h"
#import "ITunesPlayer.h"


@interface EditorController (PrivateAPI)
- (void)parseITunesMusicLibrary;
- (void)setupPlaylistMenu;
- (void)addPlaylistItemsWithFolder:(NSNumber *)parentID indentation:(int)level;
- (void)setIsEnabled:(BOOL)status;
- (void)updateTimeImage;
- (void)updateSearchLabel;
- (void)updateSongLabelAndShuffleButton;
- (void)updateWindowStatus;
@end


@implementation EditorController

- (id)init;
{
	return [self initWithIndex:-1];
}

- (id)initWithIndex:(int)index
{
	if(self = [super initWithWindowNibName:@"AlarmEditor"])
	{
		// Initialize alarm reference and copy
		if(index < 0)
		{
			alarmReference = nil;
			alarm = [[Alarm alloc] init];
		}
		else
		{
			alarmReference = [[AlarmScheduler alarmReferenceForIndex:index] retain];
			alarm = [[AlarmScheduler alarmCloneForIndex:index] retain];
		}
		
		// Intialize images
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];
		NSString *path = [bundle resourcePath];
		playImage = [[NSImage alloc] initByReferencingFile:[path stringByAppendingString:@"/play.tif"]];
		stopImage = [[NSImage alloc] initByReferencingFile:[path stringByAppendingString:@"/stop.tif"]];
		
		// Initialize lock
		lock = [[NSLock alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Loading and Opening Window:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/* Called after laoding the nib file
** Configures gui elements
**/
- (void)awakeFromNib
{
	// Interface Builder Bug (I think)
	// The "Auto Save Name" doesn't work properly when using an NSWindowController
	[self setShouldCascadeWindows:NO];
	[self setWindowFrameAutosaveName:@"AlarmEditorWindow"];
	
	// Change window title, if needed
	if(alarmReference != nil)
	{
		NSString *title = NSLocalizedStringFromTable(@"Edit Alarm", @"AlarmEditor", @"Window title when editing an alarm");
		[[self window] setTitle:title];
	}
	
	// Set status button
	[statusButton setState:([alarm isEnabled] ? NSOnState: NSOffState)];
	
	// Set delete button
	[deleteButton setEnabled:(alarmReference == nil) ? NO : YES];
	
	// Set time
	[timeField setDateValue:[alarm time]];
	[self updateTimeImage];
	
	// Set date
	[dateField setDateValue:[alarm time]];
	
	// Set repeat type (One-time or Repeating)
	if([alarm schedule] > 0)
		[repeatType selectCellAtRow:1 column:0];
	else
		[repeatType selectCellAtRow:0 column:0];
	
	// Set repeat schedule
	int schedule = [alarm schedule];
	
	if(schedule > 0)
	{
		if(schedule >= 64) {
			[repeatSchedule selectCellWithTag:6];
			schedule -= 64;
		}
		if(schedule >= 32) {
			[repeatSchedule selectCellWithTag:5];
			schedule -= 32;
		}
		if(schedule >= 16) {
			[repeatSchedule selectCellWithTag:4];
			schedule -= 16;
		}
		if(schedule >= 8) {
			[repeatSchedule selectCellWithTag:3];
			schedule -= 8;
		}
		if(schedule >= 4) {
			[repeatSchedule selectCellWithTag:2];
			schedule -= 4;
		}
		if(schedule >= 2) {
			[repeatSchedule selectCellWithTag:1];
			schedule -= 2;
		}
		if(schedule >= 1)
			[repeatSchedule selectCellWithTag:0];
	}
	
	// Set easyWake
	[easyWakeButton setState:([alarm usesEasyWake] ? NSOnState : NSOffState)];
	
	// Set shuffle
	[shuffleButton setState:([alarm usesShuffle] ? NSOnState : NSOffState)];
	
	// Call methods to properly disable components (such as one-time-date if using a repeating alarm)
	[self setIsEnabled:[alarm isEnabled]];
}

/* Called when window loads
** Start a background thread to parse the iTunes library.
**/
- (void)windowDidLoad
{
	// Start parsing iTunes Music Library in background thread
	[NSThread detachNewThreadSelector:@selector(parseThread:) toTarget:self withObject:nil];
	
	// Note that Cocoa's thread management system retains the target during the execution of the detached thread
	// When the thread terminates, the target gets released
	// Thus, dealloc won't be called until this thread is completed
}


/*!
 Background thread function to parse iTunes library
 
 This method is run in a separate thread.
 It parses the iTunes music library in a background thread, allowing the GUI to remain responsive.
*/
- (void)parseThread:(NSObject *)obj
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self parseITunesMusicLibrary];
    [pool release];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Closing and Releasing Window:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user clicks the red close button in the window titleBar.
 
 This method checks to see if the user is trying to close the window with unsaved changes.
 If they are, they are first prompted with the standard, "wanna save changes?" dialog.
**/
- (BOOL)windowShouldClose:(id)sender
{
	if([[self window] isDocumentEdited])
	{
		// Repeating alarm type was selected, but no days were selected
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Do you want to save changes to this alarm before closing?", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"If you don't save, your changes will be lost.", @"AlarmEditor", @"Sub prompt in sheet")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Save", @"AlarmEditor", @"Dialog Button")];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Don't Save", @"AlarmEditor", @"Dialog Button")];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				// User clicked "Save"
				// Programmatically click "OK" to start the save routine
				[self ok:self];
				
			}
			else if (returnCode == NSAlertSecondButtonReturn)
			{
				// User clicked "Don't Save"
				// Don't wait for sheet to be dismissed, immediately close the window
				[[self window] close];
			}
		}];
		return NO;
	}
	
	return YES;
}

/**
 Called immediately before the window closes.
 
 This method's job is to release the WindowController (self)
 This is so that the nib file is not held in memory,
 which helps because the alarm clock is supposed to be a background program.
**/
- (void)windowWillClose:(NSNotification *)aNotification
{
	// Post notification for closed alarm editor window
	[[NSNotificationCenter defaultCenter] postNotificationName:@"AlarmEditorWindowClosed" object:self];
	
	// Release self
	[self autorelease];
}

/**
 Standard Deallocation method.
 Release any objects this instance is retaining.
**/
- (void)dealloc
{	
	NSLog(@"Destroying %@", self);
	[alarmReference release];
	[alarm release];
	[data release];
	[playImage release];
	[stopImage release];
	[player release];
	[lock release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Parsing of iTunes Music Library:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user switches tabs, before the tab is displayed.
  
 This method ensures the iTunes library is parsed, before the alarms tab may be shown.
 This is because the alarms tab must display the iTunes data.
 It calls the parse method, which will return immediately if it is already parsed.
 
 @result The tab is allowed to be viewed, and the iTunes data is ready.
**/
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	[self parseITunesMusicLibrary];
	return YES;
}

/**
 Called when the user switches tabs, after the tab has been displayed.
 
 This method takes care of selecting the proper track/playlist.
 
 Why would we do this here, instead of immediately after parsing the iTunes library?
 Because, for some reason, the table's view has not been notified of it's correct size.
 The table still thinks it's the same size it was initiallly set to in the AlarmEditor.nib file.
 Only after the Music tab is displayed, is the table informed of it's correct size.
 This affects scrolling songs into view, because if the size is wrong, the songs won't properly be in view.
**/
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	// Remember, we only want to do this the FIRST time they display the music tab
	if(!hasSelectedTrackOrPlaylist)
	{
		// There are 4 scenarios to handle here:
		// 1. The alarm type is a playlist
		//    Thus we must select and display this playlist
		// 2. The alarm type is a track, and the track was NOT selected within a particular playlist
		//    Thus we want to select and display the selected song only (the playlist will remain the entire library)
		// 3. The alarm type is a track, and the track was selected with a playlist, but no longer exists in the playlist
		//    Thus we want to select and display the selected song only (the playlist will remain the entire library)
		//    Note that this has the same effect as number two.
		// 4. The alarm type is a track, and the track was selected within a particular playlist
		//    Thus we want to select and display the playlist
		//    Then we want to select and display the selected song within this playlist
		
		int trackIndex = -1;
		int playlistIndex = -1;
		
		if([alarm isPlaylist])
		{
			// If we're using a playlist, we don't have to worry about the trackIndex
			
			trackIndex = -1;
			playlistIndex = [alarm playlistID];
		}
		else if([alarm isTrack])
		{
			// First try to get a trackIndex within the playlist
			trackIndex = [data trackIndexForPersistentID:[alarm persistentTrackID] withPlaylistID:[alarm playlistID]];
			if(trackIndex >= 0)
			{
				// The track was found in the playlist!
				// Grab the playlist index, and we're ready to rock and roll!
				playlistIndex = [alarm playlistID];
			}
			else
			{
				// The track wasn't found in the playlist.
				// So we can ignore the playlist now, and just lookup the track in the library
				
				trackIndex = [data trackIndexForPersistentID:[alarm persistentPlaylistID]];
				playlistIndex = -1;
			}
		}

		if(playlistIndex >= 0)
		{
			// Select the proper playlist in the popup box
			[playlists selectItemWithTag:playlistIndex];
				
			// Perform switch on table
			[data setPlaylist:playlistIndex];
				
			// Update table
			[table reloadData];
				
			// Update search label
			[self updateSearchLabel];
		}
		
		if(trackIndex >= 0)
		{
			// Select the proper row index in the table
			[table selectRowIndexes:[NSIndexSet indexSetWithIndex:trackIndex] byExtendingSelection:NO];
				
			// Note: selecting the row in the table automatically invokes tableViewSelectionDidChange
			// This is acceptable as it simply resets labels and such with their existing values.
			
			// Scroll to the selected index so the user can see their selection
			[table scrollRowToVisible:trackIndex];
		}
		
		
		hasSelectedTrackOrPlaylist = YES;
	}
}

/**
 Parses the iTunes data into memory.
  
 Invokes the proper procedures to parse the iTunes music library into memory.
 After this is complete, the playlist popup box is populated, and the table is loaded, and the labels are set.
 
 This method is muli-thread safe (the method first requests a lock).
 This method should complete PRIOR to displaying the alarms tab.
**/
- (void)parseITunesMusicLibrary
{
	[lock lock];
	
	// Parse iTunes data if needed
	if(data == nil)
	{
		NSLog(@"Parsing iTunes Music Library...");
		NSDate *start = [NSDate date];
		
		// Initialize data
		data = [[ITunesTable alloc] init];
		
		// Initialize player
		player = [[ITunesPlayer alloc] initWithITunesData:data];
		
		// The stored trackID may have changed
		// Check this, and update the alarm if needed
		// Also update the alarm reference, so we don't have to continually fix this everytime
		int correctTrackID = [data validateTrackID:[alarm trackID] withPersistentTrackID:[alarm persistentTrackID]];
		if(correctTrackID != [alarm trackID])
		{
			[alarm setTrackID:correctTrackID withPersistentTrackID:[alarm persistentTrackID]];
			[alarmReference setTrackID:correctTrackID withPersistentTrackID:[alarm persistentTrackID]];
		}
		
		// The stored playlistID may have changed
		// Check this, and update the alarm if needed
		// Also update the alarm reference, so we don't have to continually fix this everytime
		int correctPlaylistID = [data validatePlaylistID:[alarm playlistID] withPersistentPlaylistID:[alarm persistentPlaylistID]];
		if(correctPlaylistID != [alarm playlistID])
		{
			[alarm setPlaylistID:correctPlaylistID withPersistentPlaylistID:[alarm persistentPlaylistID]];
			[alarmReference setPlaylistID:correctPlaylistID withPersistentPlaylistID:[alarm persistentPlaylistID]];
		}
		
		NSDate *end = [NSDate date];
		NSLog(@"Done parsing (time: %f seconds)", [end timeIntervalSinceDate:start]);
		
		// Setup the playlist menu
		[self setupPlaylistMenu];
		
		// Load the data into the table
		[table reloadData];
		
		// Update song label
		[self updateSongLabelAndShuffleButton];
		
		// Update search label
		[self updateSearchLabel];
	}
	
	[lock unlock];
}

/**
 Configures the playlist using the fetched iTunes data.
 Everything is added in the proper order, with proper icons and tags.
**/
- (void)setupPlaylistMenu
{
	// Update playlist menu
	[playlists removeAllItems];
	
	int i;
	
	// Library
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist isMaster])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesLibrary.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Music
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMusic)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesMusic.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Movies
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMovies)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesMovies.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// TV Shows
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindTVShows)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesTVShows.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Podcasts
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindPodcasts)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPodcasts.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Videos
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindHomeVideos ||
		   [currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindMusicVideos ||
		   [currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindLibraryMusicVideos)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesVideos.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Audiobooks
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindAudiobooks)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesAudiobooks.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Purchased Music
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindPurchases)
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPurchasedMusic.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Folders
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist kind] == ITLibPlaylistKindFolder && ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesFolder.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
			
			// Add sub-folders and folder items
			[self addPlaylistItemsWithFolder:[currentPlaylist persistentID] indentation:1];
		}
	}
	
	// Smart Playlists
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindNone &&
		   [currentPlaylist kind] == ITLibPlaylistKindSmart &&
		   ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesSmartPlaylist.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
	
	// Normal Playlists
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		if([currentPlaylist distinguishedKind] == ITLibDistinguishedPlaylistKindNone &&
		   ![currentPlaylist isMaster] &&
		   [currentPlaylist kind] == ITLibPlaylistKindRegular &&
		   ![currentPlaylist parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
			[temp setTag:i];
			[[playlists menu] addItem:temp];
		}
	}
}

/**
 Recursively adds folders (since folders may be nested), and their internal playlists
**/
- (void)addPlaylistItemsWithFolder:(NSNumber *)parentID indentation:(int)level
{
	int i;
	
	for(i = 0; i < [[data playlists] count]; i++)
	{
		ITLibPlaylist *currentPlaylist = [[data playlists] objectAtIndex:i];
		
		if([[currentPlaylist parentID] isEqualToNumber:parentID])
		{
			NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
			[temp setTitle:[currentPlaylist name]];
			[temp setIndentationLevel:level];
			
			if([currentPlaylist kind] == ITLibPlaylistKindFolder)
				[temp setImage:[NSImage imageNamed:@"iTunesFolder.png"]];
			else if([currentPlaylist kind] == ITLibPlaylistKindSmart)
				[temp setImage:[NSImage imageNamed:@"iTunesSmartPlaylist.png"]];
			else
				[temp setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
			
			[temp setTag:i];
			[[playlists menu] addItem:temp];
			
			if([currentPlaylist kind] == ITLibPlaylistKindFolder)
			{
				[self addPlaylistItemsWithFolder:[currentPlaylist persistentID] indentation:(level+1)];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Methods Called by MenuController:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Returns the alarm object this EditorController is for
  
 This method allows the WindowManager to probe open AlarmEditor windows,
 to discover if the wanted window is already open.  If it is, it can be brought
 to the front.  If not, a new AlarmEditor window can be opened.
 
 @result  The original alarm object (a reference) is returned, which may be compared to desired alarm objects.
**/
- (Alarm *)alarmReference
{
	return alarmReference;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Toggle Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when user enables/disables the alarm.
  
 This method enables/disables all GUI elements appropriately.
 IE - if alarm is being disabled, then all GUI elements are disabled.
 The reason for doing this in rather fundamental. It should be overly obvious
 when an alarm is enabled or disabled. Users should not be allowed to edit
 disabled alarms, as they may not notice they forgot to enable the alarm.
 The last thing we want is for users to be under the impression they set an alarm, when in fact they didn't.
 
 @param sender - Object invoking method (sent from nib file)
 
 @result All GUI elements are properly enabled/disabled.
**/
- (IBAction)toggleStatus:(id)sender
{
	// Grab the status of the statusButton
	BOOL status = [statusButton state] == NSOnState;
	
	// Set the alarm status appropriately
	[alarm setIsEnabled:status];
	
	// Enable/Disable gui elements properly
	[self setIsEnabled:status];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/**
 Called when the user alters the date or time.
 Changes the date/time of the alarm accordingly.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleDateTime:(id)sender
{
	BOOL isRepeating = [repeatType selectedRow] == 1;
	
	// Update the schedule if needed
	if(sender == repeatType || sender == repeatSchedule)
	{
		// Enable, disable components
		[dateField		setEnabled:!isRepeating];
		[dateButton     setEnabled:!isRepeating];
		[repeatSchedule setEnabled:isRepeating];
		
		if(!isRepeating)
		{
			[alarm setSchedule:0];
		}
		else
		{
			// Get schedule total
			int total = 0;
			
			// If it repeats weekly
			if([[repeatSchedule cellWithTag:6] state] == NSOnState) total += 64;
			if([[repeatSchedule cellWithTag:5] state] == NSOnState) total += 32;
			if([[repeatSchedule cellWithTag:4] state] == NSOnState) total += 16;
			if([[repeatSchedule cellWithTag:3] state] == NSOnState) total += 8;
			if([[repeatSchedule cellWithTag:2] state] == NSOnState) total += 4;
			if([[repeatSchedule cellWithTag:1] state] == NSOnState) total += 2;
			if([[repeatSchedule cellWithTag:0] state] == NSOnState) total += 1;
			
			[alarm setSchedule:total];
		}
	}
	
	// Update the date/time
	NSDate *dmy, *hm, *newTime;
	NSCalendar *calendar = [NSCalendar currentCalendar];
	
	// Set the time from timeField
	hm = [timeField dateValue];
	
	// Set the date from the dateField if one-time alarm
	//  or from a time in the past (yesterday) if a repeating alarm (It will get updated to the proper time)
	dmy = [dateField dateValue];
	if(isRepeating) {
		NSDateComponents *components = [[NSDateComponents alloc] init];
		[components setDay:-1];
		dmy = [calendar dateByAddingComponents:components toDate:[NSDate date] options:0];
		[components release];
	}
	
	NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:dmy];
	components.hour  = [calendar component:NSCalendarUnitHour fromDate:hm];
	components.minute = [calendar component:NSCalendarUnitMinute fromDate:hm];
	components.second = 0;
	
	newTime = [calendar dateFromComponents:components];
	
	// Set the alarm's time
	[alarm setTime:newTime];
	
	// And make sure it's updated
	[alarm updateTime];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
	
	// And finally, update the sunMoonImage to reflect the AM/PM status
	[self updateTimeImage];
}

/**
 Called when user alters the state of the easyWake switch button.
 Changes usesEasyWake option of alarm accordingly.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleEasyWake:(id)sender
{
	// Set the alarm easyWake property appropriately
	[alarm setUsesEasyWake:([sender state] == NSOnState)];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/**
 * Called when user alters the state of the shuffle switch button.
 * Changes usesShuffle option of alarm accordingly.
 *
 * @param  sender - Object invoking method (sent from nib file)
**/
- (IBAction)toggleShuffle:(id)sender
{
	// Set the alarm usesShuffle property appropriately
	[alarm setUsesShuffle:([sender state] == NSOnState)];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Date Selection:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when the user clicks the button to select a date.
 *
 * Prepares the calendar sheet, by setting up the proper day, month, and year
 * (which is currently being displayed in the text field),
 * sets the calendar accordingly, and displays it.
 *
 * @result  Calendar sheet is displayed.
**/
- (IBAction)selectDate:(id)sender
{
	int i;
	
	// Setup months popup button
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSArray *months = [calendar standaloneMonthSymbols];
	
	[calMonths removeAllItems];
	for(i=0; i<[months count]; i++)
	{
		[calMonths addItemWithTitle:[months objectAtIndex:i]];
	}
	
	// Setup years popup button
	NSInteger year = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
	
	[calYears removeAllItems];
	for(i=0; i<4; i++)
	{
		[calYears addItemWithTitle:[NSString stringWithFormat:@"%li", year + i]];
	}
	
	// Get date from text field
	NSDate *date = [dateField dateValue];
	
	// Select proper month, year, day
	[calMonths selectItemAtIndex:[calendar component:NSCalendarUnitMonth fromDate:date]-1];
	[calYears setTitle:[NSString stringWithFormat:@"%li", (long)[calendar component:NSCalendarUnitYear fromDate:date]]];
	[calView setCalendarDate:date withValidDay:YES];
	
	[[self window] beginSheet:calPanel completionHandler:^(NSModalResponse returnCode){
		[self setNewDate];
	}];
}

/**
 * Called when the user changes the value of the month or year in their respective popup boxes.
**/
- (IBAction)changeCal:(id)sender
{
	NSInteger year = [[calYears titleOfSelectedItem] intValue];
	NSInteger month = [calMonths indexOfSelectedItem]+1;
	
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.year = year;
	components.month = month;
	components.day = 1;
	components.hour = 0;
	components.minute = 0;
	components.second = 0;
	NSDate *date = [calendar dateFromComponents:components];
	[components release];
	
	[calView setCalendarDate:date withValidDay:NO];
}

- (IBAction)closeCalPanel:(id)sender
{
	[calPanel orderOut:self];
	[[self window] endSheet:calPanel returnCode:NSModalResponseOK];
}

- (void)setNewDate
{
	[dateField setDateValue:[calView calendarDate]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Table Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user switches the playlist.
 Method performs switch, and updates table and label.
 
 @param sender - Object invoking method (sent from nib file)
**/
- (IBAction)switchSource:(id)sender
{
	// First deselect any selected songs
	// This is important, because this fires the tableSelectionDidChange method
	[table deselectAll:self];
	
	NSInteger playlistIndex = [[playlists selectedItem] tag];
		
	// Perform switch on table
	[data setPlaylist:playlistIndex];
		
	// Get playlist
	ITLibPlaylist *playlist = [[data playlists] objectAtIndex:playlistIndex];
	
	// Update alarm playlist and type
	NSNumber *persistentPlaylistID = [playlist persistentID];
	[alarm setPlaylistID:(int)playlistIndex withPersistentPlaylistID:persistentPlaylistID];
	[alarm setType:ALARMTYPE_PLAYLIST];
	
	// Clear search field
	[searchField setStringValue:@""];
	
	// Update search label
	[self updateSearchLabel];
	
	// Update song label (and shuffle button)
	[self updateSongLabelAndShuffleButton];
	
	// Update table
	[table reloadData];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

/*!
 @abstract   Called whenever the user types something into the search field.
 @discussion
 
 Performs the search, and updates table and search label.
 
 @result Table is properly filtered, displaying search results.
*/
- (IBAction)search:(id)sender
{
	// Perform search
	[data setSearchCriteria:[searchField stringValue]];
		
	// Update search label
	[self updateSearchLabel];
		
	// Notify table of changes
	[table reloadData];
}

- (IBAction)preview:(id)sender
{
	if([player isPlaying])
	{
		[player stop];
		[previewButton setImage:playImage];
	}
	else
	{
		// Configure the player for the new preview
		if([alarm isPlaylist])
		{
			[player setPlaylistWithPlaylistID:[alarm playlistID] usesShuffle:[alarm usesShuffle]];
		}
		else if([alarm isTrack])
		{
			[player setTrackWithTrackID:[alarm trackID]];
		}
		else
		{
			[player setFileWithPath:[Alarm defaultAlarmFile]];
		}
		
		// Start the player
		[player play];
		
		// Verify it's playing, and change the button if needed
		if([player isPlaying])
		{
			[previewButton setImage:stopImage];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Table Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called automatically by Cocoa.
 Returns the number of items in the table.
**/
- (NSUInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [[data table] count];
}

/**
 Called automatically by Cocoa.
 Returns the proper object that should be placed at the given row and column.
**/
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)col row:(int)rowIndex
{
	int trackID = [[[data table] objectAtIndex:rowIndex] intValue];
	ITLibMediaItem *track = [data trackForID:trackID];
	
	if([@"Song" isEqualToString:[col identifier]])
	{
		return [track title];
	}
	else if([@"Artist" isEqualToString:[col identifier]])
	{
		return [[track artist] name];
	}
	else
	{
		int millis = (int)[track totalTime];
		int totalSeconds = millis / 1000;
		int minutes = totalSeconds / 60;
		int seconds = totalSeconds % 60;
		
		if(seconds < 10)
			return [NSString stringWithFormat:@"%i:0%i",minutes,seconds];
		else
			return [NSString stringWithFormat:@"%i:%i", minutes,seconds];
	}
}

/**
 Called before cells in table are displayed.
 Allows the programmer to alter the default appearance of cells.
 This is used to make the table smaller by using a smaller font size.
**/
- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)col row:(int)rowIndex
{
	NSFont *smallFont = [NSFont userFontOfSize:[NSFont smallSystemFontSize]];
	[aCell setFont:smallFont];
}

/**
 Called when the user double-clicks on a cell.
 This is used to play a preview of a song.
**/
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)col row:(int)rowIndex
{	
	// Stop playing current song
	if([player isPlaying])
	{
		[player stop];
		[previewButton setImage:playImage];
	}
	
	// Play selected song
	[self preview:self];
	
	return NO;
}

/**
 Called when the user selects a song in the table.
  
 This method updates the alarm file.
 It updates the trackID and persistentTrackID of the alarm.
 
 @param  aNotification - NSNotification sent from table
**/
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([table selectedRow] >= 0)
	{
		// User selected a song
		// Grab the trackID, which is simply the object at that index in the table
		int trackID = [[[data table] objectAtIndex:[table selectedRow]] intValue];
		
		// Now grab the Track dictionary
		ITLibMediaItem *track = [data trackForID:trackID];
		NSNumber *persistentTrackID = [track persistentID];
		
		// Set the alarm file and type
		[alarm setTrackID:trackID withPersistentTrackID:persistentTrackID];
		[alarm setType:ALARMTYPE_TRACK];
	}
	else
	{
		// User deselected a song, so nothing is selected
		// Revert to default alarm file
		[alarm setTrackID:0 withPersistentTrackID:nil];
		[alarm setType:ALARMTYPE_DEFAULT];
	}
	
	// Update the song label (and shuffle button)
	[self updateSongLabelAndShuffleButton];
	
	// Add or remove the little dot in the red close button
	[self updateWindowStatus];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Button Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 Called when the user clicks the 'OK' button.
**/
- (IBAction)ok:(id)sender
{
	BOOL isRepeating = [repeatType selectedRow] == 1;
	
	if(([alarm schedule] == 0) && isRepeating)
	{
		// Repeating alarm type was selected, but no days were selected
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Invalid alarm time", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Please select the days the alarm should repeat.", @"AlarmEditor", @"Sub prompt in sheet")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
		return;
	}
	
	NSDate *dmy, *hm, *newTime;
	NSCalendar *calendar = [NSCalendar currentCalendar];
	
	// Set the time from timeField
	hm = [timeField dateValue];
	
	// Set the date from the dateField if one-time alarm
	//  or from a time in the past (yesterday) if a repeating alarm (It will get updated to the proper time)
	dmy = [dateField dateValue];
	if(isRepeating) {
		NSDateComponents *components = [[NSDateComponents alloc] init];
		[components setDay:-1];
		dmy = [calendar dateByAddingComponents:components toDate:[NSDate date] options:0];
		[components release];
	}
	
	NSDateComponents *components = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:dmy];
	components.hour  = [calendar component:NSCalendarUnitHour fromDate:hm];
	components.minute = [calendar component:NSCalendarUnitMinute fromDate:hm];
	components.second = 0;

	newTime = [calendar dateFromComponents:components];
	
	// Set the time
	[alarm setTime:newTime];
	
	// Make sure the time is updated
	[alarm updateTime];
	
	// Ensure the time is at least a second or two after now
	if([[alarm time] timeIntervalSinceNow] < 1)
	{
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:NSLocalizedStringFromTable(@"Invalid alarm time", @"AlarmEditor", @"Main prompt in sheet")];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Please select a date and time in the future.", @"AlarmEditor", @"Error message in AlarmEditor")];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"AlarmEditor", @"Dialog Button")];
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
	}
	else
	{
		// Register alarm with Alarms
		if(alarmReference == nil)
			[AlarmScheduler addAlarm:alarm];
		else
			[AlarmScheduler setAlarm:alarm forReference:alarmReference];
		
		// Close the window
		// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
		[[self window] close];
	}
}

/**
 Called when the user clicks the 'Cancel' button.
**/
- (IBAction)cancel:(id)sender
{
	// Close the window
	// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
	[[self window] close];
}

/**
 Called when the user clicks the 'Delete' button.
**/
- (IBAction)delete:(id)sender
{
	// Delete the alarm, using the original reference
	[AlarmScheduler removeAlarm:alarmReference];
	
	// Close the window
	// Note: this is different than performClose as the delegate is NOT sent shouldWindowClose
	[[self window] close];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setIsEnabled:(BOOL)isEnabled
{	
	/// Time Tab ///
	
	// Time
	[timeField      setEnabled:isEnabled];
	
	// Date, repeat type, and repeat schedule
	[repeatType     setEnabled:isEnabled];
	
	BOOL isRepeating = [alarm schedule] > 0;
	
	[dateField      setEnabled:(isEnabled && !isRepeating)];
	[dateButton     setEnabled:(isEnabled && !isRepeating)];
	[repeatSchedule setEnabled:(isEnabled && isRepeating)];
	
	/// Alarm Tab ///
	
	// Playlist chooser, preview button, search field
	[playlists      setEnabled:isEnabled];
	[previewButton  setEnabled:isEnabled];
	[searchField    setEnabled:isEnabled];
	
	// Easy wake button
	[easyWakeButton setEnabled:isEnabled];
	
	// Shuffle button
	BOOL isPlaylist = [alarm isPlaylist];
	
	[shuffleButton setEnabled:(isEnabled && isPlaylist)];
}

/**
 * Updates the image next to the time field.
 * If it's AM, sets the image to a sun.
 * If it's PM, sets the image to a moon.
**/
- (void)updateTimeImage
{
	NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
	[df setFormatterBehavior:NSDateFormatterBehavior10_4];
	[df setDateStyle:NSDateFormatterNoStyle];
	[df setTimeStyle:NSDateFormatterShortStyle];
	
	NSRange range = [[df dateFormat] rangeOfString:@"a"];
	
	if(range.length == 0)
	{
		// The user is using a 24 hour clock
		[sunMoonImage setHidden:YES];
	}
	else
	{
		[sunMoonImage setHidden:NO];
		
        NSInteger hourOfDay = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[alarm time]];
		
		if(hourOfDay >= 6 && hourOfDay < 18)
			[sunMoonImage setImage:[NSImage imageNamed:@"sun.png"]];
		else
			[sunMoonImage setImage:[NSImage imageNamed:@"moon.png"]];
	}
}

/**
 * Updates the search label to reflect the number of songs currently in the table.
**/
- (void)updateSearchLabel
{
	NSInteger tableCount = [[data table] count];
	
	if(tableCount == 1)
	{
		NSString *format = NSLocalizedStringFromTable(@"1 song", @"AlarmEditor", @"Label next to search field");
		[searchLabel setStringValue:format];
	}
	else
	{
		NSString *format = NSLocalizedStringFromTable(@"%i songs", @"AlarmEditor", @"Label next to search field");
		[searchLabel setStringValue:[NSString stringWithFormat:format, tableCount]];
	}
}

/**
 Updates the song label and properly enables/disables the shuffleButton.
 The song label reflects the currently selected song or playlist.
 If nothing is selected (or an invalid trackID/playlistID is set) then "Default Alarm" is displayed.
 The shuffle button is disabled unles a playlist is selected.
**/
- (void)updateSongLabelAndShuffleButton
{
	// Check to make sure data isn't nil
	// If it is, then iTunes hasn't been fully parsed yet, and we don't even need to bother
	if(data == nil) return;
	
	NSString *defaultStr = NSLocalizedStringFromTable(@"Default Alarm", @"AlarmEditor", @"Song label when no track/playlist is selected.");
	
	if([alarm isPlaylist])
	{
		NSString *playlistName = [[data playlistForID:[alarm playlistID]] name];
		if(playlistName != nil)
		{
			NSString *format  = NSLocalizedStringFromTable(@"Playlist: %@", @"AlarmEditor", @"Song label when using a playlist");
			[songLabel setStringValue:[NSString stringWithFormat:format, playlistName]];
			
			// We can enable the shuffle button in this scenario
			// But remember, only if the alarm is enabled
			[shuffleButton setEnabled:[alarm isEnabled]];
		}
		else
		{
			[songLabel setStringValue:defaultStr];
			[shuffleButton setEnabled:NO];
		}
	}
	else if([alarm isTrack])
	{
		NSString *songName = [[data trackForID:[alarm trackID]] title];
		if(songName != nil)
		{
			NSString *format = NSLocalizedStringFromTable(@"Song: %@", @"AlarmEditor", @"Song label when using a song");
			[songLabel setStringValue:[NSString stringWithFormat:format, songName]];
			[shuffleButton setEnabled:NO];
		}
		else
		{
			[songLabel setStringValue:defaultStr];
			[shuffleButton setEnabled:NO];
		}
	}
	else
	{
		[songLabel setStringValue:defaultStr];
		[shuffleButton setEnabled:NO];
	}
}

- (void)updateWindowStatus
{
	// If the alarm has changed, put the little dot in the red close button
	[[self window] setDocumentEdited:![alarm isEqualToAlarm:alarmReference]];
}

@end
