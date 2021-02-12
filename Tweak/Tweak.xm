#import "Tweak.h"
#import "FlynnsArcade.h"

// Lightmann
// Made during COVID-19
// Quorra

// Check for SpringBoard and act accordingly -- CPDistributedMessagingCenter isn't always necessary  
static void sendThroughPortal(NSString *type, NSDictionary *info){
	if([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]){
		if([type isEqualToString:@"activity"]) [[FlynnsArcade sharedInstance] handleActivity:type ofType:info];
		else [[FlynnsArcade sharedInstance] prepNotif:type WithInfo:info];
	}
	else{
		CPDistributedMessagingCenter *portal = [%c(CPDistributedMessagingCenter) centerNamed:@"me.lightmann.quorra-portal"];
		rocketbootstrap_distributedmessagingcenter_apply(portal);
		[portal sendMessageName:type userInfo:info];
	}
}

%group General
// Initalize FlynnsArcade and TheGrid
%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application{
	%orig;
	
	[[[FlynnsArcade sharedInstance] grid] gridPowerOn];
}
%end
%end


%group Camera
// Determine when camera is active by checking availability of the flashlight; if flash isn't available, cam is active 
// *Won't work for devices w/o a flashlight*
%hook SBUIFlashlightController 
-(void)_updateStateWithAvailable:(BOOL)arg1 level:(unsigned long long)arg2 overheated:(BOOL)arg3{
	%orig;

	if(!arg1){
		sendThroughPortal(@"activity", @{@"type" : @"camActive"});
	
		if(usageLog) sendThroughPortal(@"usage", @{@"type" : @"Camera", @"process" : [[NSProcessInfo processInfo] processName]}); 
	}
	else if(arg1){
		sendThroughPortal(@"activity", @{@"type" : @"camInactive"});
	}
}
%end
%end


%group Microphone 

// Determine when mic is active (*mediaserverd filter necessary)
%hookf(OSStatus, AudioUnitInitialize, AudioUnit inUnit){
	OSStatus orig = %orig;
	
		AudioComponentDescription desc = {0};
		AudioComponentGetDescription(AudioComponentInstanceGetComponent(inUnit), &desc);
		
		//attempt to filter out any inaccuracies with my check below
		if([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
			//description of a component preping for mic input 
			if(desc.componentType == kAudioUnitType_Output && desc.componentSubType == kAudioUnitSubType_RemoteIO && desc.componentFlags == 0 && desc.componentFlagsMask == 0){
				sendThroughPortal(@"activity", @{@"type" : @"micActive"});
				if(usageLog){
					//prevent spamming to the log
					static dispatch_once_t once;
					dispatch_once(&once, ^{
						sendThroughPortal(@"usage", @{@"type" : @"Microphone", @"process" : [[NSProcessInfo processInfo] processName]}); 
					});
				}
			}
		}
	
	return orig;
}

// Determine when mic is inactive (*mediaserverd filter necessary)
%hookf(OSStatus, AudioUnitUninitialize, AudioUnit inUnit){
	OSStatus orig = %orig;
	
		AudioComponentDescription desc = {0};
		AudioComponentGetDescription(AudioComponentInstanceGetComponent(inUnit), &desc);

		//matching description to unit(s) monitored above 
		if(desc.componentType == kAudioUnitType_Output && desc.componentSubType == kAudioUnitSubType_RemoteIO && desc.componentFlags == 0 && desc.componentFlagsMask == 0){
			sendThroughPortal(@"activity", @{@"type" : @"micInactive"});
		}
    
	return orig;
}

// Determine when a call is active -- taken from Laoyur's CallKiller (https://github.com/laoyur/CallKiller-iOS/blob/master/callkiller/callkiller.xm)
%hook SBTelephonyManager
-(void)callEventHandler:(NSNotification*)arg1{
    if(arg1 && arg1.object){
        TUProxyCall *call = arg1.object;
	    /*
            call.status:
            1 - call established
            3 - outgoing connecting
            4 - incoming ringing
            5 - disconnecting
            6 - disconnected
        */
		if(call.status == 1){
			sendThroughPortal(@"activity", @{@"type" : @"micActive"});
			
			if(usageLog) sendThroughPortal(@"usage", @{@"type" : @"Microphone", @"process" : [[NSProcessInfo processInfo] processName]});  
		}
        else if(call.status == 6){
			sendThroughPortal(@"activity", @{@"type" : @"micInactive"});
        }
    }
	
	%orig;
} 
%end

// Determine when dictation is active
%hook UIDictationController
-(void)startDictation{
	%orig;

	sendThroughPortal(@"activity", @{@"type" : @"micActive"});

	if(usageLog) sendThroughPortal(@"usage", @{@"type" : @"Microphone", @"process" : [[NSProcessInfo processInfo] processName]});  
}

-(void)stopDictation{ //normal end
	%orig;
	
	sendThroughPortal(@"activity", @{@"type" : @"micInactive"});
}

-(void)cancelDictation{ //any other type of end 
	%orig;
	
	sendThroughPortal(@"activity", @{@"type" : @"micInactive"});
}
%end

// Determine when Siri is active
%hook AFSiriClientStateManager 
-(void)beginListeningForClient:(void*)arg1 {
	%orig;

	sendThroughPortal(@"activity", @{@"type" : @"micActive"});

	if(usageLog) sendThroughPortal(@"usage", @{@"type" : @"Microphone", @"process" : [[NSProcessInfo processInfo] processName]});  
}

-(void)endListeningForClient:(void*)arg1 {
	%orig;

	sendThroughPortal(@"activity", @{@"type" : @"micInactive"});
}
%end
%end


%group GPS
// Determine when the GPS is active
// GPS Indicator will only appear while the location is actively being updated. 
// Occasioanlly, apps will grab it and store it (like the Weather app) in which case the indicator will appear briefly before disappearing. 
// This is NORMAL behavior!		
%hook CLLocationManagerStateTracker
-(void)setUpdatingLocation:(BOOL)updating{				    
	%orig;

	if(updating){
		sendThroughPortal(@"activity", @{@"type" : @"gpsActive"});
		
		if(usageLog) sendThroughPortal(@"usage", @{@"type" : @"GPS", @"process" : [[NSProcessInfo processInfo] processName]});  
	}
	else{
		sendThroughPortal(@"activity", @{@"type" : @"gpsInactive"});
	}	
}

// EOL method in the event ^ isn't called before the process suspends/terminates
-(void)dealloc{
	%orig;

	sendThroughPortal(@"activity", @{@"type" : @"gpsInactive"});
}
%end

// Backup EOL method in the event ^ isn't called (timely) either    
%hook UIApplication
-(void)applicationWillSuspend{
	%orig;
	
	// check that the app doesn't allow for background location updates
	if(!((CLLocationManager *)[CLLocationManager sharedManager]).allowsBackgroundLocationUpdates) sendThroughPortal(@"activity", @{@"type" : @"gpsInactive"});
}
%end
%end


//	PREFERENCES 
void preferencesChanged(){
	NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"me.lightmann.quorraprefs"];
	
	isEnabled = (prefs && [prefs objectForKey:@"isEnabled"] ? [[prefs valueForKey:@"isEnabled"] boolValue] : YES );
	camIndicator = (prefs && [prefs objectForKey:@"camIndicator"] ? [[prefs valueForKey:@"camIndicator"] boolValue] : YES );
	micIndicator = (prefs && [prefs objectForKey:@"micIndicator"] ? [[prefs valueForKey:@"micIndicator"] boolValue] : YES );
	gpsIndicator = (prefs && [prefs objectForKey:@"gpsIndicator"] ? [[prefs valueForKey:@"gpsIndicator"] boolValue] : YES );
	
	//NSUserDefaults doesn't return a value for usageLog in some processes (will default to NO), so we read the value directly from the .plist (which works, but isn't recommended)
	NSDictionary *directPrefs = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/me.lightmann.quorraprefs.plist"];
	usageLog = (directPrefs && [directPrefs objectForKey:@"usageLog"] ? [[directPrefs valueForKey:@"usageLog"] boolValue] : NO );
}

%ctor{
	if ([[[[NSProcessInfo processInfo] arguments] objectAtIndex:0] containsString:@"/Application"] || [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"] || [[NSProcessInfo processInfo].processName isEqualToString:@"mediaserverd"]) {
		preferencesChanged();

		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)preferencesChanged, CFSTR("me.lightmann.quorraprefs-updated"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

		if(isEnabled){					
			%init(General);

			if(camIndicator) %init(Camera);

			if(micIndicator) %init(Microphone);

			if(gpsIndicator) %init(GPS);
		}
	}
}
