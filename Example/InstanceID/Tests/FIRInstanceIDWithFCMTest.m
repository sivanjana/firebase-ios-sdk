/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import <FirebaseCore/FIRAppInternal.h>
#import <OCMock/OCMock.h>
#import "Firebase/InstanceID/Public/FIRInstanceID.h"
#import "third_party/firebase/ios/Source/FirebaseMessaging/Library/FIRMessaging_Private.h"
#import "third_party/firebase/ios/Source/FirebaseMessaging/Library/Public/FIRMessaging.h"

@interface FIRInstanceID (ExposedForTest)
- (BOOL)isFCMAutoInitEnabled;
+ (FIRInstanceID *)instanceIDForTests;
@end

@interface FIRMessaging ()
+ (FIRMessaging *)messagingForTests;
@end

@interface FIRInstanceIDTest : XCTestCase

@property(nonatomic, readwrite, strong) FIRInstanceID *instanceID;
@property(nonatomic, readwrite, strong) id mockFirebaseApp;

@end

@implementation FIRInstanceIDTest

- (void)setUp {
  [super setUp];
  _instanceID = [FIRInstanceID instanceIDForTests];
  _mockFirebaseApp = OCMClassMock([FIRApp class]);
  OCMStub([_mockFirebaseApp defaultApp]).andReturn(_mockFirebaseApp);
}

- (void)tearDown {
  self.instanceID = nil;
  [_mockFirebaseApp stopMocking];
  [super tearDown];
}

- (void)testFCMAutoInitEnabled {
  FIRMessaging *messaging = [FIRMessaging messagingForTests];
  OCMStub([_mockFirebaseApp isDataCollectionDefaultEnabled]).andReturn(YES);
  XCTAssertTrue(
      [_instanceID isFCMAutoInitEnabled],
      @"When FCM is available, FCM Auto Init Enabled should be FCM's autoInitEnable property.");

  messaging.autoInitEnabled = NO;
  XCTAssertFalse(
      [_instanceID isFCMAutoInitEnabled],
      @"When FCM is available, FCM Auto Init Enabled should be FCM's autoInitEnable property.");

  messaging.autoInitEnabled = YES;
  XCTAssertTrue([_instanceID isFCMAutoInitEnabled]);
}

@end