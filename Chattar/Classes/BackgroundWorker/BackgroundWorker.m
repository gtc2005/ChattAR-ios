//
//  BackgroundWorker.m
//  Chattar
//
//  Created by kirill on 2/4/13.
//
//

#import "BackgroundWorker.h"

@implementation BackgroundWorker
@synthesize mapDelegate;
@synthesize chatDelegate;

#define mapSearch @"mapSearch"
#define chatSearch @"chatSearch"
#define mapFBUsers @"mapFBUsers"
#define chatFBUsers @"chatFBUsers"

#define kGetGeoDataCount 100

static BackgroundWorker* instance = nil;

+ (BackgroundWorker *)instance {
	@synchronized (self) {
		if (instance == nil){
            instance = [[self alloc] init];
        }
	}
	return instance;
}

#pragma mark -
#pragma mark Data Requests

- (void)retrieveQBGeodatas
{
    // get chat messages from cash
    NSDate *lastMessageDate = nil;
    NSArray *cashedChatMessages = [[DataManager shared] chatMessagesFromStorage];
    
    NSMutableArray* chatPoints = [[NSMutableArray alloc] init];
    NSMutableArray* chatMessagesIDs = [[NSMutableArray alloc] init];
    
    if([cashedChatMessages count] > 0){
        for(QBChatMessageModel *chatCashedMessage in cashedChatMessages){
            if(lastMessageDate == nil){
                lastMessageDate = ((UserAnnotation *)chatCashedMessage.body).createdAt;
            }
            [chatPoints addObject:chatCashedMessage.body];
            [chatMessagesIDs addObject:[NSString stringWithFormat:@"%d", ((UserAnnotation *)chatCashedMessage.body).geoDataID]];
        }
    }
    
    if ([chatDelegate respondsToSelector:@selector(didReceiveCachedChatPoints:)]) {
        [chatDelegate didReceiveCachedChatPoints:chatPoints];
    }
    [chatPoints release];
    
    if ([chatDelegate respondsToSelector:@selector(didReceiveCachedChatMessagesIDs:)]) {
        [chatDelegate didReceiveCachedChatMessagesIDs:chatMessagesIDs];
    }
    [chatMessagesIDs release];
    
    
    NSMutableArray* mapPoints = [[NSMutableArray alloc] init];
    NSMutableArray* mapPointsIds = [[NSMutableArray alloc] init];
    
    // get map/ar points from cash
    NSDate *lastPointDate = nil;
    NSArray *cashedMapARPoints = [[DataManager shared] mapARPointsFromStorage];
    if([cashedMapARPoints count] > 0){
        for(QBCheckinModel *mapARCashedPoint in cashedMapARPoints){
            if(lastPointDate == nil){
                lastPointDate = ((UserAnnotation *)mapARCashedPoint.body).createdAt;
            }
            [mapPoints addObject:mapARCashedPoint.body];
            [mapPointsIds addObject:[NSString stringWithFormat:@"%d", ((UserAnnotation *)mapARCashedPoint.body).geoDataID]];
        }
    }
    
    if ([mapDelegate respondsToSelector:@selector(didReceiveCachedMapPoints:)]) {
        [mapDelegate didReceiveCachedMapPoints:mapPoints];
    }
    [mapPoints release];
    
    if ([mapDelegate respondsToSelector:@selector(didReceiveCachedMapPointsIDs:)]) {
        [mapDelegate didReceiveCachedMapPointsIDs:mapPointsIds];
    }
    [mapPointsIds release];
    
    if(updateTimer){
        [updateTimer invalidate];
        [updateTimer release];
    }
                    // request new data every 15 seconds
    updateTimer = [[NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(checkForNewPoints:) userInfo:nil repeats:YES] retain];
    
    // get points for map
	QBLGeoDataGetRequest *searchMapARPointsRequest = [[QBLGeoDataGetRequest alloc] init];
	searchMapARPointsRequest.lastOnly = YES; // Only last location
	searchMapARPointsRequest.perPage = kGetGeoDataCount; // Pins limit for each page
	searchMapARPointsRequest.sortBy = GeoDataSortByKindCreatedAt;
    if(lastPointDate){
        searchMapARPointsRequest.minCreatedAt = lastPointDate;
    }
	[QBLocation geoDataWithRequest:searchMapARPointsRequest delegate:self context:mapSearch];
	[searchMapARPointsRequest release];
	
	// get points for chat
	QBLGeoDataGetRequest *searchChatMessagesRequest = [[QBLGeoDataGetRequest alloc] init];
	searchChatMessagesRequest.perPage = kGetGeoDataCount; // Pins limit for each page
	searchChatMessagesRequest.status = YES;
	searchChatMessagesRequest.sortBy = GeoDataSortByKindCreatedAt;
    
    if(lastMessageDate){
        searchChatMessagesRequest.minCreatedAt = lastMessageDate;
    }
    
	[QBLocation geoDataWithRequest:searchChatMessagesRequest delegate:self context:chatSearch];
	[searchChatMessagesRequest release];
}

- (void)retrieveFBCheckins{
    // get checkins from cash
    NSArray *cashedFBCheckins = [[DataManager shared] checkinsFromStorage];
    
    if([cashedFBCheckins count] > 0){
        NSMutableArray* cachedCheckins = [[NSMutableArray alloc] init];
        
        for(FBCheckinModel *checkinCashedPoint in cashedFBCheckins){
            [cachedCheckins addObject:checkinCashedPoint.body];
        }
        
        if ([mapDelegate respondsToSelector:@selector(didReceiveFBCheckins:)]) {
            [mapDelegate didReceiveFBCheckins:cachedCheckins];
        }
        [cachedCheckins release];
        
    }
    
    // retrieve new
    if(numberOfCheckinsRetrieved != 0){
        [[FBService shared] performSelector:@selector(friendsCheckinsWithDelegate:) withObject:self afterDelay:1];
    }
    
}

-(void)retrievePhotosWithLocations{
    NSArray* popularFriendsIds = [[[DataManager shared] myPopularFriends] allObjects];
    NSMutableArray* cachedPhotos = [[NSMutableArray alloc] init];

    if (popularFriendsIds.count != 0) {
        for (NSString* friendId in popularFriendsIds) {
            NSArray* friendPhotos = [[DataManager shared] photosWithLocationsFromStorageFromUserWithId:[NSDecimalNumber decimalNumberWithString:friendId]];
            [cachedPhotos addObjectsFromArray:friendPhotos];
        }
    }
    else [cachedPhotos release];
    
    if (cachedPhotos.count > 0) {
        
        NSMutableArray* photosWithLocations = [[NSMutableArray alloc] init];
        for (PhotoWithLocationModel* photo in cachedPhotos) {
            UserAnnotation* photoAnnotation = [[UserAnnotation alloc] init];
            [photoAnnotation setFullImageURL:photo.fullImageURL];
            [photoAnnotation setThumbnailURL:photo.thumbnailURL];
            [photoAnnotation setLocationId:photo.locationId];
            [photoAnnotation setCoordinate:CLLocationCoordinate2DMake(photo.locationLatitude.doubleValue, photo.locationLongitude.doubleValue)];
            [photoAnnotation setLocationName:photo.locationName];
            [photoAnnotation setOwnerId:photo.ownerId];
            [photoAnnotation setPhotoId:photo.photoId];
            [photoAnnotation setPhotoTimeStamp:photo.photoTimeStamp];
            [photosWithLocations addObject:photoAnnotation];
            [photoAnnotation release];
        }
        [cachedPhotos release];
        
        if ([mapDelegate respondsToSelector:@selector(didReceiveCachedPhotosWithLocations:)]) {
            [mapDelegate didReceiveCachedPhotosWithLocations:photosWithLocations];
        }
        
    }
                    // request new photos from FB
    [[FBService shared] performSelector:@selector(friendsPhotosWithLocationWithDelegate:) withObject:self];
}

- (void) checkForNewPoints:(NSTimer *) timer{
	QBLGeoDataGetRequest *searchRequest = [[QBLGeoDataGetRequest alloc] init];
	searchRequest.status = YES;
    searchRequest.sortBy = GeoDataSortByKindCreatedAt;
    searchRequest.sortAsc = 1;
    searchRequest.perPage = 50;
//    searchRequest.minCreatedAt = ((UserAnnotation *)[self lastChatMessage:YES]).createdAt;
	[QBLocation geoDataWithRequest:searchRequest delegate:self];
	[searchRequest release];
}


#pragma mark - 
#pragma mark Data processing methods

- (void)processFBCheckins:(NSArray *)rawCheckins{
    if([rawCheckins isKindOfClass:NSString.class]){
        NSLog(@"rawCheckins=%@", rawCheckins);
#ifdef DEBUG
        id exc = [NSException exceptionWithName:NSInvalidArchiveOperationException
                                         reason:@"rawCheckins = NSString"
                                       userInfo:nil];
        @throw exc;
#endif
        return;
    }
    for(NSDictionary *checkinsResult in rawCheckins){
        if([checkinsResult isKindOfClass:NSNull.class]){
            continue;
        }
        
        SBJsonParser *parser = [[SBJsonParser alloc] init];
        NSArray *checkins = [[parser objectWithString:(NSString *)([checkinsResult objectForKey:kBody])] objectForKey:kData];
        [parser release];
        
        if ([checkins count]){
            
            //
            
            CLLocationCoordinate2D coordinate;
            //
            NSString *previousPlaceID = nil;
            NSString *previousFBUserID = nil;
            
            // Collect checkins
            for(NSDictionary *checkin in checkins){
                
                NSString *ID = [checkin objectForKey:kId];
                
                NSDictionary *place = [checkin objectForKey:kPlace];
                if(place == nil){
                    continue;
                }
                
                id location = [place objectForKey:kLocation];
                if(![location isKindOfClass:NSDictionary.class]){
                    continue;
                }
                
                
                // get checkin's owner
                NSString *fbUserID = [[checkin objectForKey:kFrom] objectForKey:kId];
                
                NSDictionary *fbUser;
                if([fbUserID isEqualToString:[DataManager shared].currentFBUserId]){
                    fbUser = [DataManager shared].currentFBUser;
                }else{
                    fbUser = [[DataManager shared].myFriendsAsDictionary objectForKey:fbUserID];
                }
                
                // skip if not friend or own
                if(!fbUser){
                    continue;
                }
                
                // coordinate
                coordinate.latitude = [[[place objectForKey:kLocation] objectForKey:kLatitude] floatValue];
                coordinate.longitude = [[[place objectForKey:kLocation] objectForKey:kLongitude] floatValue];
                
                
                // if this is checkin on the same location
                if([previousPlaceID isEqualToString:[place objectForKey:kId]] && [previousFBUserID isEqualToString:fbUserID]){
                    continue;
                }
                
                
                // status
                NSString *status = nil;
                NSString* country = [location objectForKey:kCountry];
                
                
                NSString* city = [location objectForKey:kCity];
                
                NSString* name = [[checkin objectForKey:kPlace] objectForKey:kName];
                if ([country length]){
                    status = [NSString stringWithFormat:@"I'm at %@ in %@, %@.", name, country, city];
                }else {
                    status = [NSString stringWithFormat:@"I'm at %@", name];
                }
                
                // datetime
                NSString* time = [checkin objectForKey:kCreatedTime];
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                [df setLocale:[NSLocale currentLocale]];
                [df setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"];
                NSDate *createdAt = [df dateFromString:time];
                [df release];
                
                UserAnnotation *checkinAnnotation = [[UserAnnotation alloc] init];
                checkinAnnotation.geoDataID = -1;
                checkinAnnotation.coordinate = coordinate;
                checkinAnnotation.userStatus = status;
                checkinAnnotation.userName = [[checkin objectForKey:kFrom] objectForKey:kName];
                checkinAnnotation.userPhotoUrl = [fbUser objectForKey:kPicture];
                checkinAnnotation.fbUserId = [fbUser objectForKey:kId];
                checkinAnnotation.fbUser = fbUser;
                checkinAnnotation.fbCheckinID = ID;
                checkinAnnotation.fbPlaceID = [place objectForKey:kId];
                checkinAnnotation.createdAt = createdAt;
                
                                
                // add to Storage
                BOOL isAdded = [[DataManager shared] addCheckinToStorage:checkinAnnotation];
                if(!isAdded){
                    [checkinAnnotation release];
                    continue;
                }
                
                // show Point on Map/AR
                dispatch_async( dispatch_get_main_queue(), ^{
                    
                    if ([mapDelegate respondsToSelector:@selector(willAddNewPoint:isFBCheckin:)]) {
                        [mapDelegate willAddNewPoint:checkinAnnotation isFBCheckin:YES];
                    }
                    
                });
                
                // show Message on Chat
                UserAnnotation *chatAnnotation = [checkinAnnotation copy];
                
                if ([chatDelegate respondsToSelector:@selector(willAddNewMessageToChat:addToTop:isFBCheckin:)]) {
                    [chatDelegate willAddNewMessageToChat:chatAnnotation addToTop:NO isFBCheckin:YES];
                }
                
                previousPlaceID = [place objectForKey:kId];
                previousFBUserID = fbUserID;
                
                if ([mapDelegate respondsToSelector:@selector(willAddFBCheckin:)]) {
                    [mapDelegate willAddFBCheckin:chatAnnotation];
                }
                [checkinAnnotation release];
                [chatAnnotation release];
            }
        }
    }
    
    if(numberOfCheckinsRetrieved == 0){
        NSLog(@"Checkins have procceced");
    }
    
    // refresh chat
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([chatDelegate respondsToSelector:@selector(willUpdate)]) {
            [chatDelegate willUpdate];
        }
    });
}

-(void)processPhotosWithLocations:(NSDictionary*)responseData{
    NSLog(@"%@",responseData);
    
    
    NSArray* fqlResults = [responseData objectForKey:kData];
    
    NSArray* firstFqlResults = [(NSDictionary*)[fqlResults objectAtIndex:0] objectForKey:@"fql_result_set"];
    NSArray* secondFqlResults = [(NSDictionary*)[fqlResults objectAtIndex:1] objectForKey:@"fql_result_set"];
    NSArray* thirdFqlResults = [(NSDictionary*)[fqlResults objectAtIndex:2] objectForKey:@"fql_result_set"];
    
    NSMutableArray* photosWithLocations = [[NSMutableArray alloc] init];
    
    for (NSDictionary*fqlResult in firstFqlResults) {
        UserAnnotation* photoObject = [[UserAnnotation alloc] init];
        
        NSDecimalNumber* placeId = [fqlResult objectForKey:@"place_id"];
        NSString* thumbnailUrl = [fqlResult objectForKey:@"src_small"];
        
        [photoObject setThumbnailURL:thumbnailUrl];
        
        [photoObject setLocationId:placeId];
        
        NSString* fullPhotoUrl = [fqlResult objectForKey:@"src"];
        
        [photoObject setFullImageURL:fullPhotoUrl];
        
        NSString* photoId = [fqlResult objectForKey:@"pid"];
        [photoObject setPhotoId:photoId];
        
        NSDecimalNumber* photoTimeStamp = [fqlResult objectForKey:@"created"];
        [photoObject setPhotoTimeStamp:photoTimeStamp];
        
        NSDecimalNumber* ownerId = [fqlResult objectForKey:@"created"];
        [photoObject setOwnerId:ownerId];
        
        [photosWithLocations addObject:photoObject];
        [photoObject release];
    }
    
    NSLog(@"%@",photosWithLocations);
    
    for (NSDictionary* fqlResult in secondFqlResults) {
        NSDecimalNumber* pageID = [fqlResult objectForKey:@"page_id"];
        NSDecimalNumber* latitude = [fqlResult objectForKey:@"latitude"];
        NSDecimalNumber* longitude = [fqlResult objectForKey:@"longitude"];
        NSString* locationName = [fqlResult objectForKey:@"name"];
        
        for (UserAnnotation* photo in photosWithLocations) {
            if (fabs(photo.locationId.doubleValue - pageID.doubleValue) < EPSILON ) {
                [photo setLocationName:locationName];
                [photo setLocationLatitude:latitude];
                [photo setLocationLongitude:longitude];
            }
        }
    }
    
    for (NSDictionary* fqlResult in thirdFqlResults) {
        NSDecimalNumber* ownerID = [fqlResult objectForKey:@"owner"];
        NSString* pid = [fqlResult objectForKey:@"pid"];
        
        for (UserAnnotation* photo in photosWithLocations) {
            if ([photo.photoId isEqualToString:pid]) {
                [photo setOwnerId:ownerID];
            }
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([mapDelegate respondsToSelector:@selector(willShowMap)]) {
            [mapDelegate willShowMap];
        }
    });
    
    [[DataManager shared] addPhotosWithLocationsToStorage:photosWithLocations];
    
    
    [photosWithLocations release];
}

- (void)processQBChatMessages:(NSArray *)data{
    
    NSArray *fbUsers = [data objectAtIndex:0];
    NSArray *qbMessages = [data objectAtIndex:1];
    
    CLLocationCoordinate2D coordinate;
    int index = 0;
    
    NSMutableArray *qbMessagesMutable = [qbMessages mutableCopy];
    
    for (QBLGeoData *geodata in qbMessages){
        NSDictionary *fbUser = nil;
        for(NSDictionary *user in fbUsers){
            NSString *ID = [user objectForKey:kId];
            if([geodata.user.facebookID isEqualToString:ID]){
                fbUser = user;
                break;
            }
        }
        
        coordinate.latitude = geodata.latitude;
        coordinate.longitude = geodata.longitude;
        UserAnnotation *chatAnnotation = [[UserAnnotation alloc] init];
        chatAnnotation.geoDataID = geodata.ID;
        chatAnnotation.coordinate = coordinate;
        
        if ([geodata.status length] >= 6){
            if ([[geodata.status substringToIndex:6] isEqualToString:fbidIdentifier]){
                // add Quote
                [self addQuoteDataToAnnotation:chatAnnotation geoData:geodata];
                
            }else {
                chatAnnotation.userStatus = geodata.status;
            }
        }else {
            chatAnnotation.userStatus = geodata.status;
        }
        
        chatAnnotation.userName = [NSString stringWithFormat:@"%@ %@",
                                   [fbUser objectForKey:kFirstName], [fbUser objectForKey:kLastName]];
        chatAnnotation.userPhotoUrl = [fbUser objectForKey:kPicture];
        chatAnnotation.fbUserId = [fbUser objectForKey:kId];
        chatAnnotation.fbUser = fbUser;
        chatAnnotation.qbUserID = geodata.user.ID;
        chatAnnotation.createdAt = geodata.createdAt;
        
        
        if(chatAnnotation.coordinate.latitude == 0.0f && chatAnnotation.coordinate.longitude == 0.0f)
        {
            chatAnnotation.distance = 0;
        }
        
        [qbMessagesMutable replaceObjectAtIndex:index withObject:chatAnnotation];
        [chatAnnotation release];
        
        ++index;
        
        // show Message on Chat
        if ([chatDelegate respondsToSelector:@selector(willAddNewMessageToChat:addToTop:withReloadTable:isFBCheckin:)]) {
            [chatDelegate willAddNewMessageToChat:chatAnnotation addToTop:NO withReloadTable:NO isFBCheckin:NO];
        }
    }
    
    NSLog(@"CHAT INIT reloadData");
    dispatch_async(dispatch_get_main_queue(), ^{       
        if ([chatDelegate respondsToSelector:@selector(willUpdate)]) {
            [chatDelegate willUpdate];
        }
    });
    
    
    [qbMessagesMutable release];
    
    
    // all data was retrieved
    ++initState;
    NSLog(@"CHAT INIT OK");
    if(initState == 2){
        dispatch_async( dispatch_get_main_queue(), ^{
            [self endOfRetrieveInitialData];
        });
    }
}


- (void)processQBCheckins:(NSArray *)data{
    
    NSArray *fbUsers = [data objectAtIndex:0];
    NSArray *qbPoints = [data objectAtIndex:1];
    
    CLLocationCoordinate2D coordinate;
    int index = 0;
    
    NSMutableArray *mapPointsMutable = [qbPoints mutableCopy];
    
    // look through array for geodatas
    for (QBLGeoData *geodata in qbPoints)
    {
        NSDictionary *fbUser = nil;
        for(NSDictionary *user in fbUsers){
            NSString *ID = [user objectForKey:kId];
            if([geodata.user.facebookID isEqualToString:ID]){
                fbUser = user;
                break;
            }
        }
        
        if ([geodata.user.facebookID isEqualToString:[DataManager shared].currentFBUserId])
        {
            
            CLLocationManager* locationManager = [[CLLocationManager alloc] init];
            [locationManager startMonitoringSignificantLocationChanges];
            
            coordinate.latitude = locationManager.location.coordinate.latitude;
            coordinate.longitude = locationManager.location.coordinate.longitude;
            [locationManager stopUpdatingLocation];
            [locationManager release];
        }
        else
        {
            coordinate.latitude = geodata.latitude;
            coordinate.longitude = geodata.longitude;
        }
        
        UserAnnotation *mapAnnotation = [[UserAnnotation alloc] init];
        mapAnnotation.geoDataID = geodata.ID;
        mapAnnotation.coordinate = coordinate;
        mapAnnotation.userStatus = geodata.status;
        mapAnnotation.userName = [fbUser objectForKey:kName];
        mapAnnotation.userPhotoUrl = [fbUser objectForKey:kPicture];
        mapAnnotation.fbUserId = [fbUser objectForKey:kId];
        mapAnnotation.fbUser = fbUser;
        mapAnnotation.qbUserID = geodata.user.ID;
        mapAnnotation.createdAt = geodata.createdAt;
        [mapPointsMutable replaceObjectAtIndex:index withObject:mapAnnotation];
        [mapAnnotation release];
        
        ++index;
        
        // show Point on Map/AR
        dispatch_async( dispatch_get_main_queue(), ^{
            if ([mapDelegate respondsToSelector:@selector(willAddNewPoint:isFBCheckin:)]) {
                [mapDelegate willAddNewPoint:mapAnnotation isFBCheckin:NO];
            }
        });
    }
    
    // update AR
    dispatch_async( dispatch_get_main_queue(), ^{
//        [arViewController updateMarkersPositionsForCenterLocation:arViewController.centerLocation];
    });
    
    //
    // add to Storage
    [[DataManager shared] addMapARPointsToStorage:mapPointsMutable];
    
    [mapPointsMutable release];
    
    // all data was retrieved
    ++initState;
    NSLog(@"MAP INIT OK");
    if(initState == 2){
        dispatch_async( dispatch_get_main_queue(), ^{
            [self endOfRetrieveInitialData];
        });
    }
}


#pragma mark -
#pragma mark QB QBActionStatusDelegate

- (void)completedWithResult:(Result *)result context:(void *)contextInfo{
    // get points result
	if([result isKindOfClass:[QBLGeoDataPagedResult class]])
	{
        NSLog(@"QB completedWithResult, contextInfo=%@, class=%@", contextInfo, [result class]);
        
        if (result.success){
            QBLGeoDataPagedResult *geoDataSearchResult = (QBLGeoDataPagedResult *)result;
            
            // update map
            if([((NSString *)contextInfo) isEqualToString:mapSearch]){
                
                // get string of fb users ids
                NSMutableArray *fbMapUsersIds = [[NSMutableArray alloc] init];
                NSMutableArray *geodataProcessed = [NSMutableArray array];
                
                for (QBLGeoData *geodata in geoDataSearchResult.geodata){

                    //add users with only nonzero coordinates
                    if(geodata.latitude != 0 && geodata.longitude != 0){
                        [fbMapUsersIds addObject:geodata.user.facebookID];
                        
                        [geodataProcessed addObject:geodata];
                    }
                }
                if([fbMapUsersIds count] == 0){
                    [fbMapUsersIds release];
                    return;
                }
                
                //
				NSMutableString* ids = [[NSMutableString alloc] init];
				for (NSString* userID in fbMapUsersIds)
				{
					[ids appendFormat:[NSString stringWithFormat:@"%@,", userID]];
				}
				
                NSLog(@"ids=%@", ids);
                
                NSArray *context = [NSArray arrayWithObjects:mapFBUsers, geodataProcessed, nil];
                
                
				// get FB info for obtained QB locations
				[[FBService shared] usersProfilesWithIds:[ids substringToIndex:[ids length]-1]
                                                delegate:self
                                                 context:context];
                
                [fbMapUsersIds release];
				[ids release];
                
                // update chat
            }else if([((NSString *)contextInfo) isEqualToString:chatSearch]){
                
                // get fb users info
                NSMutableSet *fbChatUsersIds = [[NSMutableSet alloc] init];
                
                NSMutableArray *geodataProcessed = [NSMutableArray array];
                
                for (QBLGeoData *geodata in geoDataSearchResult.geodata){
                    // skip if already exist
                    [fbChatUsersIds addObject:geodata.user.facebookID];
                    
                    [geodataProcessed addObject:geodata];
                }
                if([fbChatUsersIds count] == 0){
                    [fbChatUsersIds release];
                    return;
                }
                
                //
                NSMutableString* ids = [[NSMutableString alloc] init];
				for (NSString* userID in fbChatUsersIds)
				{
					[ids appendFormat:[NSString stringWithFormat:@"%@,", userID]];
				}
                
                
                NSArray *context = [NSArray arrayWithObjects:chatFBUsers, geodataProcessed, nil];
                
                
                // get FB info for obtained QB chat messages
				[[FBService shared] usersProfilesWithIds:[ids substringToIndex:[ids length]-1]
                                                delegate:self
                                                 context:context];
                [fbChatUsersIds release];
                [ids release];
            }
            
            // errors
        }else{
            if ([chatDelegate respondsToSelector:@selector(didReceiveError)]) {
                [chatDelegate didReceiveError];
            }
        }
    }
}

- (void)completedWithResult:(Result *)result {
    NSLog(@"completedWithResult");
    
    // get points result - check for new one
	if([result isKindOfClass:[QBLGeoDataPagedResult class]])
	{
        
        if (result.success){
            QBLGeoDataPagedResult *geoDataSearchResult = (QBLGeoDataPagedResult *)result;
            
            if([geoDataSearchResult.geodata count] == 0){
                return;
            }
            
            // get fb users info
            NSMutableArray *fbChatUsersIds = nil;
            NSMutableArray *geodataProcessed = [NSMutableArray array];
            
            for (QBLGeoData *geodata in geoDataSearchResult.geodata){
                
                // skip own;
                if([DataManager shared].currentQBUser.ID == geodata.user.ID){
                    continue;
                }
                
                // collect users ids
                if(fbChatUsersIds == nil){
                    fbChatUsersIds = [[NSMutableArray alloc] init];
                }
                [fbChatUsersIds addObject:geodata.user.facebookID];
                
                [geodataProcessed addObject:geodata];
            }
            
            if(fbChatUsersIds == nil){
                return;
            }
            
            //
            [[FBService shared] usersProfilesWithIds:[fbChatUsersIds stringComaSeparatedValue] delegate:self context:geodataProcessed];
            //
            [fbChatUsersIds release];
        }
    }
}



- (void)endOfRetrieveInitialData{

    if ([mapDelegate respondsToSelector:@selector(endRetrievingData)]) {
        [mapDelegate endRetrievingData];
    }
    
    if ([chatDelegate respondsToSelector:@selector(endRetrievingData)]) {
        [chatDelegate endRetrievingData];
    }
}


#pragma mark -
#pragma mark FBServiceResultDelegate

-(void)completedWithFBResult:(FBServiceResult *)result context:(id)context{
    
    switch (result.queryType) {
            
            // get Users profiles
        case FBQueriesTypesUsersProfiles:{
            
            NSArray *contextArray = nil;
            NSString *contextType = nil;
            NSArray *points = nil;
            if([context isKindOfClass:NSArray.class]){
                contextArray = (NSArray *)context;
                
                // basic
                if(![[contextArray lastObject] isKindOfClass:QBLGeoData.class] && [contextArray count]){
                    contextType = [contextArray objectAtIndex:0];
                    points = [contextArray objectAtIndex:1];
                }// else{
                // this is check new one
                //}
            }
            
            // Map init
            if([contextType isKindOfClass:NSString.class] && [contextType isEqualToString:mapFBUsers]){
                
                if([result.body isKindOfClass:NSDictionary.class]){
                    NSDictionary *resultError = [result.body objectForKey:kError];
                    if(resultError != nil){
                        // all data was retrieved
                        ++initState;
                        NSLog(@"MAP INIT FB ERROR");
                        if(initState == 2){
                            [self endOfRetrieveInitialData];
                        }
                        return;
                    }
                    
                    // conversation
                    NSArray *data = [NSArray arrayWithObjects:[result.body allValues], points, nil];
                    //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    if(processCheckinsQueue == NULL){
                        processCheckinsQueue = dispatch_queue_create("com.quickblox.chattar.process.checkins.queue", NULL);
                    }
                    // convert checkins
                    dispatch_async(processCheckinsQueue, ^{
                        [self processQBCheckins:data];
                    });
                    
                    // Undefined format
                }else{
                    ++initState;
                    NSLog(@"MAP INIT FB Undefined format");
                    if(initState == 2){
                        [self endOfRetrieveInitialData];
                    }
                }
                
                // Chat init
            }else if([contextType isKindOfClass:NSString.class] && [contextType isEqualToString:chatFBUsers]){
                
                if([result.body isKindOfClass:NSDictionary.class]){
                    NSDictionary *resultError = [result.body objectForKey:kError];
                    if(resultError != nil){
                        // all data was retrieved
                        ++initState;
                        NSLog(@"CHAT INIT FB ERROR");
                        if(initState == 2){
                            [self endOfRetrieveInitialData];
                        }
                        return;
                    }
                    
                    // conversation
                    NSArray *data = [NSArray arrayWithObjects:[result.body allValues], points, nil];
                    //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    if(processCheckinsQueue == NULL){
                        processCheckinsQueue = dispatch_queue_create("com.quickblox.chattar.process.checkins.queue", NULL);
                    }
                    // convert checkins
                    dispatch_async(processCheckinsQueue, ^{
                        [self processQBChatMessages:data];
                    });
                    
                    // Undefined format
                }else{
                    ++initState;
                    NSLog(@"CHAT INIT FB Undefined format");
                    if(initState == 2){
                        [self endOfRetrieveInitialData];
                    }
                }
                
                // check new one
            }else{
                
                if([result.body isKindOfClass:NSDictionary.class]){
                    NSDictionary *resultError = [result.body objectForKey:kError];
                    if(resultError != nil){
                        NSLog(@"check new one FB ERROR");
                        return;
                    }
                    
                    for (QBLGeoData *geoData in context) {
                        
                        // get vk user
                        NSDictionary *fbUser = nil;
                        for(NSDictionary *user in [result.body allValues]){
                            if([geoData.user.facebookID isEqualToString:[[user objectForKey:kId] description]]){
                                fbUser = user;
                                break;
                            }
                        }
                        
                        // add new Annotation to map/chat/ar
//                        [self createAndAddNewAnnotationToMapChatARForFBUser:fbUser withGeoData:geoData addToTop:YES withReloadTable:YES];
                    }
                    
                    // Undefined format
                }else{
                    // ...
                }
            }
            
            break;
        }
        default:
            break;
    }
}

-(void)completedWithFBResult:(FBServiceResult *)result
{
    NSLog(@"%d",result.queryType);
    switch (result.queryType)
    {
            // Get Friends checkins
        case FBQueriesTypesFriendsGetCheckins:{
            
            --numberOfCheckinsRetrieved;
            
            NSLog(@"numberOfCheckinsRetrieved=%d", numberOfCheckinsRetrieved);
            
            // if error, return.
            // for example:
            // {
            // "error": {
            //    "message": "Invalid OAuth access token.",
            //    "type": "OAuthException",
            //    "code": 190
            // }
            if([result.body isKindOfClass:NSDictionary.class]){
                NSDictionary *resultError = [result.body objectForKey:kError];
                if(resultError != nil){
                    NSLog(@"resultError=%@", resultError);
                    return;
                }
            }
            
            if([result.body isKindOfClass:NSArray.class]){
                if(processCheckinsQueue == NULL){
                    processCheckinsQueue = dispatch_queue_create("com.quickblox.chattar.process.checkins.queue", NULL);
                }
                // convert checkins
                dispatch_async(processCheckinsQueue, ^{
                    [self processFBCheckins:(NSArray *)result.body];
                });
            }
        }
            break;
        case FBQueriesTypesGetFriendsPhotosWithLocation:{
            if ([result.body isKindOfClass:[NSDictionary class]]) {
                NSDictionary* resultError = [result.body objectForKey:kError];
                if (resultError) {
                    NSLog(@"resultError=%@",resultError);
                    return;
                }
            }
            
            if (processPhotosWithLocationsQueue == NULL) {
                processPhotosWithLocationsQueue = dispatch_queue_create("com.quickblox.chattar.process.photos.queue", NULL);
            }
            dispatch_async(processPhotosWithLocationsQueue, ^{
                [self processPhotosWithLocations:(NSDictionary*)result.body];
            });
        }
        default:
            break;
    }
}

#pragma mark -
#pragma Adding Methods
// Add Quote data to annotation
- (void)addQuoteDataToAnnotation:(UserAnnotation *)annotation geoData:(QBLGeoData *)geoData{
    // get quoted geodata
    annotation.userStatus = [geoData.status substringFromIndex:[geoData.status rangeOfString:quoteDelimiter].location+1];
    
    // Author FB id
    NSString* authorFBId = [[geoData.status substringFromIndex:6] substringToIndex:[geoData.status rangeOfString:nameIdentifier].location-6];
    annotation.quotedUserFBId = authorFBId;
    
    // Author name
    NSString* authorName = [[geoData.status substringFromIndex:[geoData.status rangeOfString:nameIdentifier].location+6] substringToIndex:[[geoData.status substringFromIndex:[geoData.status rangeOfString:nameIdentifier].location+6] rangeOfString:dateIdentifier].location];
    annotation.quotedUserName = authorName;
    
    // origin Message date
    NSString* date = [[geoData.status substringFromIndex:[geoData.status rangeOfString:dateIdentifier].location+6] substringToIndex:[[geoData.status substringFromIndex:[geoData.status rangeOfString:dateIdentifier].location+6] rangeOfString:photoIdentifier].location];
    //
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:[NSLocale currentLocale]];
    [formatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss Z"];
    annotation.quotedMessageDate = [formatter dateFromString:date];
    [formatter release];
    
    // authore photo
    NSString* photoLink = [[geoData.status substringFromIndex:[geoData.status rangeOfString:photoIdentifier].location+7] substringToIndex:[[geoData.status substringFromIndex:[geoData.status rangeOfString:photoIdentifier].location+7] rangeOfString:qbidIdentifier].location];
    annotation.quotedUserPhotoURL = photoLink;
    
    // Authore QB id
    NSString* authorQBId = [[geoData.status substringFromIndex:[geoData.status rangeOfString:qbidIdentifier].location+6] substringToIndex:[[geoData.status substringFromIndex:[geoData.status rangeOfString:qbidIdentifier].location+6] rangeOfString:messageIdentifier].location];
    annotation.quotedUserQBId = authorQBId;
    
    // origin message
    NSString* message = [[geoData.status substringFromIndex:[geoData.status rangeOfString:messageIdentifier].location+5] substringToIndex:[[geoData.status substringFromIndex:[geoData.status rangeOfString:messageIdentifier].location+5] rangeOfString:quoteDelimiter].location];
    annotation.quotedMessageText = message;
}







@end
