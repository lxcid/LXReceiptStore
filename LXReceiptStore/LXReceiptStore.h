//
//  LXReceiptStore.h
//  CTN
//
//  Created by Stan Chang Khin Boon on 26/12/12.
//  Copyright (c) 2012 d--buzz. All rights reserved.
//

#import <Foundation/Foundation.h>

@class FMDatabaseQueue;
@class CargoBay;
@class SKPaymentQueue;
@class SKPayment;
@class SKPaymentTransaction;

extern NSString * const LXReceiptStoreErrorDomain;

typedef NS_ENUM(NSInteger, LXReceiptStoreErrorCode) {
    LXReceiptStoreErrorUnknown = -1,
    
    LXReceiptStoreErrorUnableToConstructDatabasePath = 1,
    LXReceiptStoreErrorFailsToRestoreCompletedTransactions = 2,
    LXReceiptStoreErrorFailsToAddPayment = 3,
    LXReceiptStoreErrorInvalidReceiptTableRow = 4,
    LXReceiptStoreErrorNoSubscriptionAvailable = 5
};

@class LXReceiptStore;

typedef void (^LXReceiptStoreGenericSuccessBlock)(LXReceiptStore *theReceiptStore);
typedef void (^LXReceiptStoreGenericFailureBlock)(LXReceiptStore *theReceiptStore, NSError *theError);
typedef void (^LXReceiptStoreAddPaymentSuccessBlock)(LXReceiptStore *theReceiptStore, SKPaymentTransaction *thePaymentTransaction);
typedef void (^LXReceiptStoreInsertTransactionDataSuccessBlock)(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo);
typedef void (^LXReceiptStoreLatestSubscriptionSuccessBlock)(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow);
typedef void (^LXReceiptStoreActiveSubscriptionSuccessBlock)(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo);

typedef void (^LXReceiptStoreSubscriptionsSuccessBlock)(LXReceiptStore *theReceiptStore, NSArray *theReceiptTableRows);

@interface LXReceiptStore : NSObject

@property (strong, nonatomic, readonly) NSString *databasePath;
@property (strong, nonatomic, readonly) FMDatabaseQueue *databaseQueue;
@property (strong, nonatomic, readonly) CargoBay *cargoBay;
@property (strong, nonatomic, readonly) SKPaymentQueue *paymentQueue;

@property (strong, nonatomic) NSString *password;

+ (LXReceiptStore *)defaultStore;

- (id)initWithCargoBay:(CargoBay *)theCargoBay paymentQueue:(SKPaymentQueue *)thePaymentQueue;

#pragma mark - Payment Related Methods

- (void)addPayment:(SKPayment *)thePayment succcess:(LXReceiptStoreAddPaymentSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure;
- (void)restoreCompletedTransactionsWithSuccess:(LXReceiptStoreGenericSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure;

- (void)insertTransactionReceipt:(NSData *)theTransactionReceipt success:(LXReceiptStoreInsertTransactionDataSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure;

- (void)latestActiveSubscriptionForProductFamily:(NSString *)theProductFamily success:(LXReceiptStoreActiveSubscriptionSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure;

@end
