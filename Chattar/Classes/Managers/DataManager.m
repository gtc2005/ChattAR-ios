//
//  DataManager.m
//  ChattAR for Facebook
//
//  Created by QuickBlox developers on 04.05.12.
//  Copyright (c) 2012 QuickBlox. All rights reserved.
//

#import "DataManager.h"
#import "UserAnnotation.h"

#import "QBCheckinModel.h"
#import "QBChatMessageModel.h"
#import "FBCheckinModel.h"
#import "PhotoWithLocationModel.h"
#import "ARMarkerView.h"
#import "ARGeoCoordinate.h"

#define kFavoritiesFriends [NSString stringWithFormat:@"kFavoritiesFriends_%@", [DataManager shared].currentFBUserId]
#define kFavoritiesFriendsIds [NSString stringWithFormat:@"kFavoritiesFriendsIds_%@", [DataManager shared].currentFBUserId]

#define kFirstSwitchAllFriends [NSString stringWithFormat:@"kFirstSwitchAllFriends_%@", [DataManager shared].currentFBUserId]

#define qbCheckinsFetchLimit 150
#define fbCheckinsFetchLimit 50
#define qbChatMessagesFetchLimit 40

#define FBCheckinModelEntity @"FBCheckinModel"
#define QBCheckinModelEntity @"QBCheckinModel"
#define QBChatMessageModelEntity @"QBChatMessageModel"
#define PhotoWithLocationEntity @"PhotoWithLocationModel"

#define MAX_PHOTOS 5

@implementation DataManager

static DataManager *instance = nil;

@synthesize accessToken, expirationDate;

@synthesize currentQBUser;
@synthesize currentFBUser;
@synthesize currentFBUserId;

@synthesize myFriends, myFriendsAsDictionary, myPopularFriends;
@synthesize historyConversation, historyConversationAsArray;

@synthesize allChatPoints;
@synthesize allCheckins;
@synthesize allmapPoints;

@synthesize chatPoints;
@synthesize mapPoints;
@synthesize coordinates;
@synthesize coordinateViews;
@synthesize chatMessagesIDs;
@synthesize mapPointsIDs;

@synthesize currentRequestingDataControllerTitle;
@synthesize qbChatRooms;
@synthesize roomsWithAdditionalInfo;
@synthesize nearbyRooms;
@synthesize trendingRooms;
@synthesize currentChatRoom;

+ (DataManager *)shared {
	@synchronized (self) {
		if (instance == nil){ 
            instance = [[self alloc] init];
        }
	}
	
	return instance;
}

- (id)init
{
    self = [super init];
    if (self) {
        historyConversation = [[NSMutableDictionary alloc] init];
        
        // logout
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(logoutDone) name:kNotificationLogout object:nil];
    }
    return self;
}


-(void) setCurrentQBUser:(QBUUser *)aCurrentQBUser
{
    [currentQBUser release];
    currentQBUser = [aCurrentQBUser retain];
   // NSLog(@"//=// set current user");
}
-(void) dealloc 
{
    [accessToken release];
	[expirationDate release];
    
	[currentFBUser release];
	[currentQBUser release];
    [currentFBUserId release];
    
	[myFriends release];
	[myFriendsAsDictionary release];
    [myPopularFriends release];
    
	[historyConversation release];
    [historyConversationAsArray release];
    
    
    [managedObjectContext release];
    [managedObjectModel release];
    [persistentStoreCoordinator release];
    [photosWithLocations release];

    [coordinates release];
    [chatPoints release];
    [allChatPoints release];
    [mapPoints release];
    [allCheckins release];
    [allmapPoints release];
    [mapPointsIDs release];
    [chatMessagesIDs release];
    
    [qbChatRooms release];
    [roomsWithAdditionalInfo release];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotificationLogout object:nil];
    [currentRequestingDataControllerTitle release];
	
	[super dealloc];
}

- (void)logoutDone{
    // clear defaults
    [self clearFBAccess];

    
    // reset user
    self.currentFBUser = nil;
    self.currentQBUser = nil;
    self.currentFBUserId = nil;
    
    // reset Friends
    self.myFriends = nil;
    self.myFriendsAsDictionary = nil;
    self.myPopularFriends = nil;
    
    // reset Dialogs
    [historyConversation removeAllObjects];
    [historyConversationAsArray removeAllObjects];
}


#pragma mark -
#pragma mark FB access

- (void)saveFBToken:(NSString *)token andDate:(NSDate *)date{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:token forKey:FBAccessTokenKey];
    [defaults setObject:date forKey:FBExpirationDateKey];
	[defaults synchronize];
    
    self.accessToken = token;
}

- (void)clearFBAccess{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:FBAccessTokenKey];
    [defaults removeObjectForKey:FBExpirationDateKey];
	[defaults synchronize];

    self.accessToken = nil;
}

- (NSDictionary *)fbUserTokenAndDate
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults objectForKey:FBAccessTokenKey] && [defaults objectForKey:FBExpirationDateKey]){
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
		[dict setObject:[defaults objectForKey:FBAccessTokenKey] forKey:FBAccessTokenKey];
		[dict setObject:[defaults objectForKey:FBExpirationDateKey] forKey:FBExpirationDateKey];
        
		return dict;
    }
    
    return nil;
}


#pragma mark -
#pragma mark Messages

- (void)sortMessagesArray
{
    self.historyConversationAsArray =(NSMutableArray *)[[[historyConversationAsArray sortedArrayUsingComparator: ^(id conversation1, id conversation2) {
        NSString* date1 = [(NSMutableDictionary*)[((Conversation*)conversation1).messages lastObject] objectForKey:@"created_time"];
        NSDateFormatter *formatter1 = [[NSDateFormatter alloc] init];
        [formatter1 setLocale:[NSLocale currentLocale]];
        [formatter1 setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"];
        NSDate *timeStamp1 = [formatter1 dateFromString:date1];
        [formatter1 release];
        
        NSString* date2 = [(NSMutableDictionary*)[((Conversation*)conversation2).messages lastObject] objectForKey:@"created_time"];
        NSDateFormatter *formatter2 = [[NSDateFormatter alloc] init];
        [formatter2 setLocale:[NSLocale currentLocale]];
        [formatter2 setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"];
        NSDate *timeStamp2 = [formatter2 dateFromString:date2];
        [formatter2 release];
        
        return [timeStamp2 compare:timeStamp1];
    }] mutableCopy] autorelease];
}


#pragma mark -
#pragma mark Friends

- (void)makeFriendsDictionary{
    if(myFriendsAsDictionary == nil){
        myFriendsAsDictionary = [[NSMutableDictionary alloc] init];
    }
    for (NSDictionary* user in [DataManager shared].myFriends){
        [myFriendsAsDictionary setObject:user forKey:[user objectForKey:kId]];
    }
}

- (void)addPopularFriendID:(NSString *)friendID{
    if(myPopularFriends == nil){
        myPopularFriends =  [[NSMutableSet alloc] init];
    }
    
    [myPopularFriends addObject:friendID];
}


#pragma mark -
#pragma mark Favorities friends

-(NSMutableArray *) favoritiesFriends{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray *favoritiesFriends = [[NSMutableArray alloc] initWithArray:[defaults objectForKey:kFavoritiesFriends]];
    return [favoritiesFriends autorelease];
}

-(void) addFavoriteFriend:(NSString *)_friendID
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	//already exist
	NSMutableArray *favFriends = [[DataManager shared] favoritiesFriends];
	if (favFriends == nil){
		favFriends = [[[NSMutableArray alloc] init] autorelease];
	}

	[favFriends addObject:_friendID];
	[defaults setObject:favFriends forKey:kFavoritiesFriends];
	[defaults synchronize];
}

-(void) removeFavoriteFriend:(NSString *)_friendID
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray *favFriends = [[self favoritiesFriends] mutableCopy];
	
	if (favFriends == nil){
		return;
    }
	
	for (int i=0; i < [favFriends count]; i++)
	{
		if ([_friendID isEqual:[favFriends objectAtIndex:i]])
		{
			[favFriends removeObject:_friendID];
		}
	}
	[defaults setObject:favFriends forKey:kFavoritiesFriends];
	[favFriends release];
	[defaults synchronize];
}

-(BOOL) friendIDInFavorities:(NSString *)_friendID{
    NSMutableArray *favFriends = [self favoritiesFriends];
    if([favFriends containsObject:_friendID]){
        return YES;
    }
    
    return NO;
}


#pragma mark -
#pragma mark First switch All/Friends

- (BOOL)isFirstStartApp{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSNumber *firstStartApp = [defaults objectForKey:kFirstSwitchAllFriends];
    if(firstStartApp == nil){
        return YES;
    }
    return  [firstStartApp boolValue];
}

- (void)setFirstStartApp:(BOOL)firstStartApp{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSNumber numberWithBool:firstStartApp] forKey:kFirstSwitchAllFriends];
    [defaults synchronize];
}


#pragma mark -
#pragma mark QuickBlox Quote

- (NSString *)originMessageFromQuote:(NSString *)quote{
    if([quote length] > 6){
        if ([[quote substringToIndex:6] isEqualToString:fbidIdentifier])
		{
            return [quote substringFromIndex:[quote rangeOfString:quoteDelimiter].location+1];
        }
    }
    
    return quote;
}

- (NSString *)messageFromQuote:(NSString *)quote{
    if([quote length] > 6){
        if ([[quote substringToIndex:6] isEqualToString:fbidIdentifier]){
            return [quote substringFromIndex:[quote rangeOfString:quoteDelimiter].location+1];
        }
    }
    
    return quote;
}


#pragma mark -
#pragma mark Core Data core

/**
 Returns the managed object context for the application.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
 */
- (NSManagedObjectContext *)managedObjectContext {
	
    if (managedObjectContext != nil) {
        return managedObjectContext;
    }
	
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        managedObjectContext = [NSManagedObjectContext new];
        [managedObjectContext setPersistentStoreCoordinator: coordinator];
        [managedObjectContext setMergePolicy:NSOverwriteMergePolicy];
        [managedObjectContext setUndoManager:nil];
    }
    return managedObjectContext;
}


/**
 Returns the thread safe managed object context for the application.
 */
- (NSManagedObjectContext *)threadSafeContext {
    NSManagedObjectContext * context = nil;
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    
    if (coordinator != nil) {
        context = [[[NSManagedObjectContext alloc] init] autorelease];
        [context setPersistentStoreCoordinator:coordinator];
        [context setMergePolicy:NSOverwriteMergePolicy];
        [context setUndoManager:nil];
    }
    
    return context;
}


/**
 Returns the managed object model for the application.
 If the model doesn't already exist, it is created by merging all of the models found in the application bundle.
 */
- (NSManagedObjectModel *)managedObjectModel {
	
    if (managedObjectModel != nil) {
        return managedObjectModel;
    }
    managedObjectModel = [[NSManagedObjectModel mergedModelFromBundles:nil] retain];
    return managedObjectModel;
}


/**
 Returns the persistent store coordinator for the application.
 If the coordinator doesn't already exist, it is created and the application's store added to it.
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
	
    if (persistentStoreCoordinator != nil) {
        return persistentStoreCoordinator;
    }
    
	/*
	 Set up the store.
	 */
	NSURL *storeUrl = [NSURL fileURLWithPath: [[self applicationDocumentsDirectory] stringByAppendingPathComponent: @"chattardata.bin"]];
    
	NSError *error;
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: [self managedObjectModel]];
                            // set options for automating migration
    NSMutableDictionary* options = [[[NSMutableDictionary alloc] init] autorelease];
    [options setValue:[NSNumber numberWithBool:YES] forKey:NSMigratePersistentStoresAutomaticallyOption];
    [options setValue:[NSNumber numberWithBool:YES] forKey:NSInferMappingModelAutomaticallyOption];
    
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:options error:&error]) {
		/*
		 Replace this implementation with code to handle the error appropriately.
		 
		 abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. If it is not possible to recover from the error, display an alert panel that instructs the user to quit the application by pressing the Home button.
		 
		 Typical reasons for an error here include:
		 * The persistent store is not accessible
		 * The schema for the persistent store is incompatible with current managed object model
		 Check the error message to determine what the actual problem was.
		 */
		NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        return nil;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"persistentStorageInitSuccess" object:self];
    return persistentStoreCoordinator;
}


#pragma mark -
#pragma mark Core Data: general

- (void) deleteAllObjects: (NSString *) entityDescription  context:(NSManagedObjectContext *)ctx {
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityDescription inManagedObjectContext:ctx];
    [fetchRequest setEntity:entity];
    
    if([entityDescription isEqualToString:FBCheckinModelEntity]){
        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"accountFBUserID == %@", currentFBUserId]];
    }
    
    NSError *error;
    NSArray *items = [ctx executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    
    
    for (NSManagedObject *managedObject in items) {
        [ctx deleteObject:managedObject];
    }
    if (![ctx save:&error]) {
        NSLog(@"CoreData: deleting %@ - error:%@",entityDescription,error);
    }
}

- (void)clearCache{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    
    [self deleteAllObjects:FBCheckinModelEntity context:ctx];
    [self deleteAllObjects:QBCheckinModelEntity context:ctx];
    [self deleteAllObjects:QBChatMessageModelEntity context:ctx];
    
    [[DataManager shared].chatMessagesIDs removeAllObjects];
    [[DataManager shared].chatPoints removeAllObjects];
    [[DataManager shared].allChatPoints removeAllObjects];
    
    [[DataManager shared].mapPoints removeAllObjects];
    [[DataManager shared].mapPointsIDs removeAllObjects];
    [[DataManager shared].allmapPoints removeAllObjects];
    
    [[DataManager shared].coordinates removeAllObjects];
    [[DataManager shared].coordinateViews removeAllObjects];
    
    [[DataManager shared].allCheckins removeAllObjects];
    
    [[DataManager shared].qbChatRooms removeAllObjects];
    [[DataManager shared].roomsWithAdditionalInfo removeAllObjects];
    [[DataManager shared].nearbyRooms removeAllObjects];
    [[DataManager shared].trendingRooms removeAllObjects];
        
}


#pragma mark -
#pragma mark Core Data: QB Messages


/**
 Chat messages: save, get
 */
-(void)addChatMessagesToStorage:(NSArray *)messages{
    
    NSManagedObjectContext *ctx = [self threadSafeContext];
    for(UserAnnotation *message in messages){
        [self addChatMessageToStorage:message context:ctx];
    }
}
//
-(void)addChatMessageToStorage:(UserAnnotation *)message{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    [self addChatMessageToStorage:message context:ctx];
    
}
-(void)addChatMessageToStorage:(UserAnnotation *)message context:(NSManagedObjectContext *)ctx{
    if(message.fbUser == nil){
#ifdef DEBUG
        id exc = [NSException exceptionWithName:NSInvalidArchiveOperationException
                                         reason:@"addChatMessageToStorage, fbUser=nil"
                                       userInfo:nil];
        @throw exc;
#endif
        return;
    }
    
    // Check if exist
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:QBChatMessageModelEntity
											  inManagedObjectContext:ctx];
    [fetchRequest setEntity:entity];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"geoDataID == %i",message.geoDataID]];
	NSArray *results = [ctx executeFetchRequest:fetchRequest error:nil];
    [fetchRequest release];
    
    if(nil != results && [results count] > 0){
        return;
    }
    
    
    // Insert
    QBChatMessageModel *messageObject = (QBChatMessageModel *)[NSEntityDescription insertNewObjectForEntityForName:QBChatMessageModelEntity
                                                                                            inManagedObjectContext:ctx];
    messageObject.body = message;
    messageObject.geoDataID = [NSNumber numberWithInt:message.geoDataID];
    messageObject.timestamp = [NSNumber numberWithInt:[message.createdAt timeIntervalSince1970]];
    messageObject.fbUserID = message.fbUserId;
    
    NSError *error = nil;
    [ctx save:&error];
    if(error){
        NSLog(@"CoreData: addChatMessageToStorage error=%@", error);
    }
}
//
-(NSArray *)chatMessagesFromStorage{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:QBChatMessageModelEntity
                                                         inManagedObjectContext:ctx];
    
    [fetchRequest setEntity:entityDescription];
    [fetchRequest setFetchLimit:qbChatMessagesFetchLimit];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
    NSError *error;
    NSArray* results = [ctx executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    return results;
}



#pragma mark -
#pragma mark Core Data: QB Checkins

-(void)addMapARPointsToStorage:(NSArray *)points{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    for(UserAnnotation *point in points){
        [self addMapARPointToStorage:point context:ctx];
    }
}
//
-(void)addMapARPointToStorage:(UserAnnotation *)point{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    [self addMapARPointToStorage:point context:ctx];
}
-(void)addMapARPointToStorage:(UserAnnotation *)point context:(NSManagedObjectContext *)ctx{

    if(point.fbUser == nil){
#ifdef DEBUG
        id exc = [NSException exceptionWithName:NSInvalidArchiveOperationException
                                     reason:@"addMapARPointToStorage, fbUser=nil"
                                   userInfo:nil];
        @throw exc;
#endif
        return;
    }

    
    
    // Check if exist
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:QBCheckinModelEntity
											  inManagedObjectContext:ctx];
    [fetchRequest setEntity:entity];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"qbUserID == %i",point.qbUserID]];
	NSArray *results = [ctx executeFetchRequest:fetchRequest error:nil];
    [fetchRequest release];
    
    QBCheckinModel *pointObject = nil;
    
    // Update
    if(nil != results && [results count] > 0){
        pointObject = (QBCheckinModel *)[results objectAtIndex:0];
        pointObject.body = point;
        pointObject.timestamp = [NSNumber numberWithInt:[point.createdAt timeIntervalSince1970]];
        
        // Insert
    }else{
        pointObject = (QBCheckinModel *)[NSEntityDescription insertNewObjectForEntityForName:QBCheckinModelEntity
                                                                      inManagedObjectContext:ctx];
        pointObject.body = point;
        pointObject.qbUserID = [NSNumber numberWithInt:point.qbUserID];
        pointObject.timestamp = [NSNumber numberWithInt:[point.createdAt timeIntervalSince1970]];
        pointObject.fbUserID = point.fbUserId;
    }
    
    NSError *error = nil;
    [ctx save:&error];
    if(error){
        NSLog(@"CoreData: addMapARPointToStorage error=%@", error);
    }
}
//
-(NSArray *)mapARPointsFromStorage{
     NSManagedObjectContext *ctx = [self threadSafeContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:QBCheckinModelEntity
                                                         inManagedObjectContext:ctx];
    
    [fetchRequest setEntity:entityDescription];
    [fetchRequest setFetchLimit:qbCheckinsFetchLimit];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    
    NSError *error;
    NSArray* results = [ctx executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    
    //select users with nonzero coordinates
    NSMutableArray *result = [NSMutableArray array];
    for(QBCheckinModel *model in results){
        if(((UserAnnotation *)model.body).coordinate.latitude != 0 && ((UserAnnotation *)model.body).coordinate.longitude != 0){
            [result addObject:model];
        }
    }
    
    //select only 50 last users
    while([result count] > 50){
            [result removeLastObject];
    }
    
    return result;
}


#pragma mark -
#pragma mark Core Data: FB Checkins

-(void)addCheckinsToStorage:(NSArray *)checkins{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    for(UserAnnotation *message in checkins){
        [self addCheckinToStorage:message context:ctx];
    }
}
//
-(BOOL)addCheckinToStorage:(UserAnnotation *)checkin{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    return [self addCheckinToStorage:checkin context:ctx];
}
-(BOOL)addCheckinToStorage:(UserAnnotation *)checkin context:(NSManagedObjectContext *)ctx{

    // Check if exist
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:FBCheckinModelEntity
											  inManagedObjectContext:ctx];
    [fetchRequest setEntity:entity];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"accountFBUserID like %@ AND (checkinID like %@ OR (fbUserID like %@ AND placeID like %@))", currentFBUserId, checkin.fbCheckinID, checkin.fbUserId, checkin.fbPlaceID]];
    
	NSArray *results = [ctx executeFetchRequest:fetchRequest error:nil];
    [fetchRequest release];
    
    
    FBCheckinModel *pointObject = nil;
    if([results count] > 0){
        pointObject = [results objectAtIndex:0];
    }
    
    // Update
    if(pointObject && [checkin.createdAt compare:((UserAnnotation *) pointObject.body).createdAt] == NSOrderedDescending){
        pointObject.body = checkin;
        pointObject.timestamp = [NSNumber numberWithInt:[checkin.createdAt timeIntervalSince1970]];
        
        NSError *error = nil;
        [ctx save:&error];
        if(error){
            NSLog(@"CoreData: addCheckinToStorage error=%@", error);
            return NO;
        }else{
            return YES;
        }

    // Add new
    }else if(nil == results || [results count] == 0){
        pointObject = (FBCheckinModel *)[NSEntityDescription insertNewObjectForEntityForName:FBCheckinModelEntity
                                                                      inManagedObjectContext:ctx];
        
        pointObject.checkinID = checkin.fbCheckinID;
        pointObject.placeID = checkin.fbPlaceID;
        pointObject.fbUserID = checkin.fbUserId;
        pointObject.body = checkin;
        pointObject.accountFBUserID = currentFBUserId;
        pointObject.timestamp = [NSNumber numberWithInt:[checkin.createdAt timeIntervalSince1970]];

        NSError *error = nil;
        [ctx save:&error];
        if(error){
            NSLog(@"CoreData: addCheckinToStorage error=%@", error);
            return NO;
        }else{
            return YES;
        }
    }
    
    return NO;
}
//
-(NSArray *)checkinsFromStorage{
    NSManagedObjectContext *ctx = [self threadSafeContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:FBCheckinModelEntity
                                                         inManagedObjectContext:ctx];
    
    [fetchRequest setEntity:entityDescription];
    [fetchRequest setFetchLimit:fbCheckinsFetchLimit];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"accountFBUserID == %@", currentFBUserId]];
    
    NSError *error;
    NSArray* results = [ctx executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    return results;
}

#pragma mark -
#pragma mark Core Data: Photos with locations

-(NSArray*)photosWithLocationsFromStorage{
    NSManagedObjectContext* ctx = [self threadSafeContext];
    
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    
    NSEntityDescription* photoEntityDescription = [NSEntityDescription entityForName:PhotoWithLocationEntity inManagedObjectContext:ctx];
    
    [fetchRequest setEntity:photoEntityDescription];
                                                        // photos will be sorted according to place name
    NSSortDescriptor* sortingOrder = [NSSortDescriptor sortDescriptorWithKey:@"locationName" ascending:YES];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sortingOrder]];
    [fetchRequest setPredicate:nil];        // choose ALL photos
    
    NSError* fetchError = nil;
    NSArray* fetchResults = [ctx executeFetchRequest:fetchRequest error:&fetchError];
    [fetchRequest release];
    if (fetchError) {
        NSLog(@"ERROR FETCHING PHOTOS %@",fetchError.domain);
        return nil;
    }
    return fetchResults;
}

-(BOOL)addPhotoWithLocationsToStorage:(UserAnnotation*)photo{
    NSManagedObjectContext* context = [self threadSafeContext];
    return [self addPhotoWithLocationToStorage:photo withContext:context];
}

-(BOOL)addPhotoWithLocationToStorage:(UserAnnotation*)photo withContext:(NSManagedObjectContext*)context{
    // construct query for checking is photo already added
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* photoEntityDescription = [NSEntityDescription entityForName:PhotoWithLocationEntity inManagedObjectContext:context];
    
    [fetchRequest setEntity:photoEntityDescription];
        
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"photoId LIKE (%@)",
                                photo.photoId]];
    
    NSError* error = nil;
    NSArray* fetchResult = [context executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    if (error) {
        NSLog(@"ERROR ADDDING PHOTO WITH LOCATION %@",error);
    }
                        // if photo is not in DB
    if([fetchResult count] == 0 || fetchResult == nil){
         // insert new record into table
        PhotoWithLocationModel* photoToSave = [[PhotoWithLocationModel alloc] initWithEntity:photoEntityDescription insertIntoManagedObjectContext:context];
        [photoToSave setThumbnailURL:photo.thumbnailURL];
        [photoToSave setFullImageURL:photo.fullImageURL];
        [photoToSave setLocationId:photo.locationId];
        [photoToSave setLocationLongitude:photo.locationLongitude];
        [photoToSave setLocationLatitude:photo.locationLatitude];
        [photoToSave setLocationName:photo.locationName];
        [photoToSave setPhotoTimeStamp:photo.photoTimeStamp];
        [photoToSave setPhotoId:photo.photoId];
        [photoToSave setOwnerId:photo.ownerId];
        NSError* error = nil;
        [context save:&error];
        [photoToSave release];
        
        if (error) {
            NSLog(@"ERROR ADDING PHOTO %@",error.domain);
            return NO;
        }
        else return YES;
    }
    
    return NO;
}

-(NSArray*)photosWithLocationsFromStorageFromUserWithId:(NSDecimalNumber*)userId{
    NSManagedObjectContext* context = [self threadSafeContext];
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    
    NSEntityDescription* photoEntityDescription = [NSEntityDescription entityForName:PhotoWithLocationEntity inManagedObjectContext:context];
    
    [fetchRequest setEntity:photoEntityDescription];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"ownerId == %@",userId]];

    NSError* error = nil;
    NSArray* fetchResult = [context executeFetchRequest:fetchRequest error:&error];
    [fetchRequest release];
    if (error) {
        NSLog(@"ERROR ADDDING PHOTO WITH LOCATION %@",error);
    }
    
    if (fetchResult == nil || fetchResult.count == 0) {
        return nil;
    }
                    // sort array
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:@"photoTimeStamp" ascending:NO];
    
    fetchResult = [fetchResult sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortOrder]];

                    // get 5 newest photos
    if (fetchResult.count > 5) {
        return [fetchResult subarrayWithRange:NSMakeRange(0, MAX_PHOTOS-1)];
    }
    return fetchResult;
}
-(void)addPhotosWithLocationsToStorage:(NSArray*)photos{
    for (UserAnnotation* photo in photos) {
        NSLog(@"%d",[self addPhotoWithLocationsToStorage:photo]);
    }
}

#pragma mark -
#pragma mark ChatRooms methods

- (QBChatRoom*)findQBRoomWithName:(NSString *)roomName{
    for (QBChatRoom* room in qbChatRooms) {
        NSString* nonXMPPName = [Helper createTitleFromXMPPTitle:room.roomName];
        if ([nonXMPPName isEqualToString:roomName]) {
            return room;
        }
    }
    return nil;
}

- (ChatRoom*)findRoomWithAdditionalInfo:(NSString *)roomName{
    for (ChatRoom* room in roomsWithAdditionalInfo) {
        if ([room.roomName isEqualToString:roomName]) {
            return room;
        }
    }
    
    return nil;
}
- (BOOL)roomWithNameHasAdditionalInfo:(NSString*)roomName{
    for (ChatRoom* room in [DataManager shared].roomsWithAdditionalInfo) {
        
        NSString* nonXMPPName = [Helper createTitleFromXMPPTitle:roomName];
        if ([room.roomName isEqualToString:nonXMPPName]) {
            return YES;
        }
    }
    return NO;
}

- (void)sortChatRooms{
    NSArray* sortedNearbyRooms = [Helper sortArray:nearbyRooms dependingOnField:@"distanceFromUser" inAscendingOrder:YES];
    NSArray* sortedTrendingRooms = [Helper sortArray:trendingRooms dependingOnField:@"roomRating" inAscendingOrder:NO];
    
    [trendingRooms removeAllObjects];
    [trendingRooms addObjectsFromArray:sortedTrendingRooms];
    
    [nearbyRooms removeAllObjects];
    [nearbyRooms addObjectsFromArray:sortedNearbyRooms];    
}

- (void)saveOnlineUsers:(NSArray*)onlineUsers{
    if (![DataManager shared].currentChatRoom.roomOnlineQBUsers) {
        [DataManager shared].currentChatRoom.roomOnlineQBUsers = [[NSMutableArray alloc] init];
    }
    
    [onlineUsers enumerateObjectsUsingBlock:^(QBUUser* user, NSUInteger idx, BOOL *stop) {
        if (![[DataManager shared].currentChatRoom.roomOnlineQBUsers containsObject:user]) {
            [[DataManager shared].currentChatRoom.roomOnlineQBUsers addObject:user];
        }
    }];
}


- (void)saveAllUsers:(NSArray*)allUsers{
    if (![DataManager shared].currentChatRoom.allRoomUsers) {
        [DataManager shared].currentChatRoom.allRoomUsers = [[NSMutableArray alloc] init];
    }
    
    [allUsers enumerateObjectsUsingBlock:^(QBUUser* user, NSUInteger idx, BOOL *stop) {
        if (![[DataManager shared].currentChatRoom.allRoomUsers containsObject:user]) {
            [[DataManager shared].currentChatRoom.allRoomUsers addObject:user];
        }
    }];
}

#pragma mark -
#pragma mark Application's documents directory

/**
 Returns the path to the application's documents directory.
 */
- (NSString *)applicationDocumentsDirectory {
	return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}

#pragma mark -
#pragma mark Convertation methods

-(UserAnnotation*)convertQBMessageToUserAnnotation:(QBChatMessage*)message{
    UserAnnotation* userAnnotation = [[[UserAnnotation alloc] init] autorelease];
    
    [userAnnotation setCreatedAt:message.datetime];
    
    if (currentQBUser.ID == message.senderID) {
        [userAnnotation setFbUser:currentFBUser];
        userAnnotation.fbUserId = currentFBUserId;
        [userAnnotation setUserName:[currentFBUser objectForKey:kName]];
        
        NSDictionary* picture = [currentFBUser objectForKey:kPicture];
        NSDictionary* data = [picture objectForKey:kData];
        NSString* userPhotoURL = [data objectForKey:kUrl];
        
        [userAnnotation setUserPhotoUrl:userPhotoURL];
        [userAnnotation setQbUserID:currentQBUser.ID];
    }
    
    else{
        QBUUser* user = [self findQBUserByID:message.senderID];
        
        if (user) {
            NSString* qbUserFBID = user.facebookID;
            
            [userAnnotation setFbUserId:qbUserFBID];
            [userAnnotation setQbUserID:user.ID];
            
            [self.currentChatRoom.fbRoomUsers enumerateObjectsUsingBlock:^(NSDictionary* fbUser, NSUInteger idx, BOOL *stop) {
                NSString* fbID = [fbUser objectForKey:kId];
                if ([qbUserFBID isEqualToString:fbID]) {
                    [userAnnotation setUserName:[fbUser objectForKey:kName]];
                    
                    NSDictionary* picture = [fbUser objectForKey:kPicture];
                    NSDictionary* data = [picture objectForKey:kData];
                    NSString* userPhotoURL = [data objectForKey:kUrl];
                    
                    [userAnnotation setUserPhotoUrl:userPhotoURL];
                    [userAnnotation setFbUser:fbUser];
                    
                    *stop = YES;
                }
            }];        
        }
    }
    
    userAnnotation.distance = (int)([self.currentChatRoom distanceFromUser]);
    
                // if message has quotation
    if ([message.text rangeOfString:QUOTE_IDENTIFIER].location != NSNotFound) {
        NSString* newMessageText = message.text;
                                    // remove message identifier
        newMessageText = [newMessageText stringByReplacingOccurrencesOfString:QUOTE_IDENTIFIER withString:@""];
        
        [Helper addQuoteDataToAnnotation:userAnnotation quotationText:newMessageText];
        
        NSRange quoteEnd = [newMessageText rangeOfString:quoteDelimiter];
        
            // delete quote marker from string
        newMessageText = [newMessageText substringFromIndex:quoteEnd.location + 1];
        
        [userAnnotation setUserStatus:newMessageText];
    }
    else{
        [userAnnotation setUserStatus:message.text];
    }
        
    return userAnnotation;
}

- (QBUUser*)findQBUserByID:(NSInteger)qbID{
    for (QBUUser* user in self.currentChatRoom.allRoomUsers) {
        if (user.ID == qbID) {
            return user;
        }
    }
    return nil;
}

-(QBChatMessage*)convertUserAnnotationToQBChatMessage:(UserAnnotation*)annotation{
    QBChatMessage* returnMessage = [[[QBChatMessage alloc] init] autorelease];
    [returnMessage setDatetime:annotation.createdAt];
    [returnMessage setText:annotation.userStatus];
        
    return returnMessage;
}

#pragma mark -
#pragma mark Data Manipulation methods

- (void)insertDataToAllChatPoints:(UserAnnotation*)object AtIndex:(NSInteger)index {
    if (![DataManager shared].allChatPoints) {
        [DataManager shared].allChatPoints = [[NSMutableArray alloc] init];
    }
    
    NSString* objectID = [NSString stringWithFormat:@"%d",object.geoDataID];
   
    if (self.allChatPoints.count == 0 && index == 0 && ![[DataManager shared].chatMessagesIDs containsObject:objectID]) {
        [[DataManager shared].allChatPoints addObject:object];
    }
    
    if (((index >= 0 && index < [DataManager shared].allChatPoints.count)) && ![[DataManager shared].chatMessagesIDs containsObject:objectID]) {
        [[DataManager shared].allChatPoints insertObject:object atIndex:index];
    }
}

- (void)insertDataToChatPoints:(UserAnnotation *)object AtIndex:(NSInteger)index {
    if (![DataManager shared].chatPoints) {
        [DataManager shared].chatPoints = [[NSMutableArray alloc] init];
    }
    
    NSString* objectID = [NSString stringWithFormat:@"%d",object.geoDataID];
    
    if (self.chatPoints.count == 0 && index == 0 && ![[DataManager shared].chatMessagesIDs containsObject:objectID]) {
        [[DataManager shared].chatPoints addObject:object];
    }

    if ( (index >= 0 && index < [DataManager shared].chatPoints.count)  &&  ![[DataManager shared].chatMessagesIDs containsObject:objectID]  ) {
        [[DataManager shared].chatPoints insertObject:object atIndex:index];
    }
}



#pragma mark -
#pragma mark Helpers

- (BOOL)isFbUserOnlineInCurrentChatRoom:(NSString*)fbID {
    __block BOOL isOnline = NO;
    [self.currentChatRoom.roomOnlineQBUsers enumerateObjectsUsingBlock:^(QBUUser* user, NSUInteger idx, BOOL *stop) {
        if ([user.facebookID isEqualToString:fbID]) {
            isOnline = YES;
        }
    }];
    return isOnline;
}

@end
