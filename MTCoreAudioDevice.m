//
//  MTCoreAudioDevice.m
//  MTCoreAudio.framework
//
//  Created by Michael Thornburgh on Sun Dec 16 2001.
//  Copyright (c) 2001 Michael Thornburgh. All rights reserved.
//

#import "MTCoreAudioDevice.h"
#import <AudioToolbox/AudioServices.h>

@implementation MTCoreAudioDevice

+ (MTCoreAudioDevice *) deviceWithID:(AudioDeviceID)theID
{
	return [[[[self class] alloc] initWithDeviceID:theID] autorelease];
}

+ (MTCoreAudioDevice *) _defaultDevice:(int)whichDevice
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioDeviceID theID;
	
	theSize = sizeof(AudioDeviceID);
	
	AudioObjectPropertyAddress propertyAddress;
	propertyAddress.mSelector = whichDevice;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyDataSize( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize );
	theStatus = AudioObjectGetPropertyData( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize, &theID );

	if (theStatus == 0)
		return [[self class] deviceWithID:theID];
	return nil;
}

+ (MTCoreAudioDevice *) defaultOutputDevice
{
	return [[self class] _defaultDevice:kAudioHardwarePropertyDefaultOutputDevice];
}

+ (MTCoreAudioDevice *) defaultSystemOutputDevice
{
	return [[self class] _defaultDevice:kAudioHardwarePropertyDefaultSystemOutputDevice];
}

- (MTCoreAudioDevice *) initWithDeviceID:(AudioDeviceID)theID
{
	if(self = [super init])
	{
		myDevice = theID;
	}
	return self;
}

- (Float32) volumeForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	Float32 theVolumeScalar;
	
	theSize = sizeof(Float32);
	AudioObjectPropertyAddress propertyAddress;
	propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
	propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theVolumeScalar );
	if (theStatus == 0)
		return theVolumeScalar;
	else
		return 0.0;
}

- (void) setVolume:(Float32)theVolume forDirection:(MTCoreAudioDirection)theDirection
{
	UInt32 theSize;
	
	theSize = sizeof(Float32);
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theVolume );
}

- (void) setMute:(BOOL)isMuted forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	UInt32 theSize;
	UInt32 theMuteVal;
	
	theSize = sizeof(UInt32);
	if (isMuted) theMuteVal = 1; else theMuteVal = 0;
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyMute;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theMuteVal );
}

@end
