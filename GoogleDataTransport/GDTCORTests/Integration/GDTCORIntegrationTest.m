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

#import <GoogleDataTransport/GDTCOREvent.h>
#import <GoogleDataTransport/GDTCOREventDataObject.h>
#import <GoogleDataTransport/GDTCOREventTransformer.h>
#import <GoogleDataTransport/GDTCORTransport.h>

#import "GDTCORTests/Common/Categories/GDTCORUploadCoordinator+Testing.h"

#import "GDTCORTests/Integration/Helpers/GDTCORIntegrationTestPrioritizer.h"
#import "GDTCORTests/Integration/Helpers/GDTCORIntegrationTestUploader.h"
#import "GDTCORTests/Integration/TestServer/GDTCORTestServer.h"

#import "GDTCORLibrary/Private/GDTCORReachability_Private.h"
#import "GDTCORLibrary/Private/GDTCORStorage_Private.h"
#import "GDTCORLibrary/Private/GDTCORTransformer_Private.h"

/** A test-only event data object used in this integration test. */
@interface GDTCORIntegrationTestEvent : NSObject <GDTCOREventDataObject>

@end

@implementation GDTCORIntegrationTestEvent

- (NSData *)transportBytes {
  // In real usage, protobuf's -data method or a custom implementation using nanopb are used.
  return [[NSString stringWithFormat:@"%@", [NSDate date]] dataUsingEncoding:NSUTF8StringEncoding];
}

@end

/** A test-only event transformer. */
@interface GDTCORIntegrationTestTransformer : NSObject <GDTCOREventTransformer>

@end

@implementation GDTCORIntegrationTestTransformer

- (GDTCOREvent *)transform:(GDTCOREvent *)event {
  // drop half the events during transforming.
  if (arc4random_uniform(2) == 0) {
    event = nil;
  }
  return event;
}

@end

@interface GDTCORIntegrationTest : XCTestCase

/** A test prioritizer. */
@property(nonatomic) GDTCORIntegrationTestPrioritizer *prioritizer;

/** A test uploader. */
@property(nonatomic) GDTCORIntegrationTestUploader *uploader;

/** The first test transport. */
@property(nonatomic) GDTCORTransport *transport1;

/** The second test transport. */
@property(nonatomic) GDTCORTransport *transport2;

@end

@implementation GDTCORIntegrationTest

- (void)tearDown {
  dispatch_sync([GDTCORStorage sharedInstance].storageQueue, ^{
    XCTAssertEqual([GDTCORStorage sharedInstance].storedEvents.count, 0);
  });
}

- (void)testEndToEndEvent {
  XCTestExpectation *expectation = [self expectationWithDescription:@"server got the request"];
  expectation.assertForOverFulfill = NO;

  // Manually set the reachability flag.
  [GDTCORReachability sharedInstance].flags = kSCNetworkReachabilityFlagsReachable;

  // Create the server.
  GDTCORTestServer *testServer = [[GDTCORTestServer alloc] init];
  [testServer setResponseCompletedBlock:^(GCDWebServerRequest *_Nonnull request,
                                          GCDWebServerResponse *_Nonnull response) {
    [expectation fulfill];
  }];
  [testServer registerTestPaths];
  [testServer start];

  // Create eventgers.
  self.transport1 = [[GDTCORTransport alloc] initWithMappingID:@"eventMap1"
                                                  transformers:nil
                                                        target:kGDTCORIntegrationTestTarget];

  self.transport2 = [[GDTCORTransport alloc]
      initWithMappingID:@"eventMap2"
           transformers:@[ [[GDTCORIntegrationTestTransformer alloc] init] ]
                 target:kGDTCORIntegrationTestTarget];

  // Create a prioritizer and uploader.
  self.prioritizer = [[GDTCORIntegrationTestPrioritizer alloc] init];
  self.uploader = [[GDTCORIntegrationTestUploader alloc] initWithServerURL:testServer.serverURL];

  // Set the interval to be much shorter than the standard timer.
  [GDTCORUploadCoordinator sharedInstance].timerInterval = NSEC_PER_SEC * 0.1;
  [GDTCORUploadCoordinator sharedInstance].timerLeeway = NSEC_PER_SEC * 0.01;

  // Confirm no events are in disk.
  XCTAssertEqual([GDTCORStorage sharedInstance].storedEvents.count, 0);
  XCTAssertEqual([GDTCORStorage sharedInstance].targetToEventSet.count, 0);

  // Generate some events data.
  [self generateEvents];

  // Flush the transformer queue.
  dispatch_sync([GDTCORTransformer sharedInstance].eventWritingQueue, ^{
                });

  // Confirm events are on disk.
  dispatch_sync([GDTCORStorage sharedInstance].storageQueue, ^{
    XCTAssertGreaterThan([GDTCORStorage sharedInstance].storedEvents.count, 0);
    XCTAssertGreaterThan([GDTCORStorage sharedInstance].targetToEventSet.count, 0);
  });

  // Confirm events were sent and received.
  [self waitForExpectations:@[ expectation ] timeout:10.0];

  // Generate events for a bit.
  NSUInteger lengthOfTestToRunInSeconds = 30;
  [GDTCORUploadCoordinator sharedInstance].timerInterval = NSEC_PER_SEC * 5;
  [GDTCORUploadCoordinator sharedInstance].timerLeeway = NSEC_PER_SEC * 1;
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
  dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
  dispatch_source_set_event_handler(timer, ^{
    static int numberOfTimesCalled = 0;
    numberOfTimesCalled++;
    if (numberOfTimesCalled < lengthOfTestToRunInSeconds) {
      [self generateEvents];
    } else {
      dispatch_source_cancel(timer);
    }
  });
  dispatch_resume(timer);

  // Run for a bit, several seconds longer than the previous bit.
  [[NSRunLoop currentRunLoop]
      runUntilDate:[NSDate dateWithTimeIntervalSinceNow:lengthOfTestToRunInSeconds + 5]];

  [testServer stop];
}

/** Generates a bunch of random events. */
- (void)generateEvents {
  for (int i = 0; i < arc4random_uniform(10) + 1; i++) {
    // Choose a random transport, and randomly choose if it's a telemetry event.
    GDTCORTransport *transport = arc4random_uniform(2) ? self.transport1 : self.transport2;
    BOOL isTelemetryEvent = arc4random_uniform(2);

    // Create an event.
    GDTCOREvent *event = [transport eventForTransport];
    event.dataObject = [[GDTCORIntegrationTestEvent alloc] init];

    if (isTelemetryEvent) {
      [transport sendTelemetryEvent:event];
    } else {
      [transport sendDataEvent:event];
    }
  }
}

@end
