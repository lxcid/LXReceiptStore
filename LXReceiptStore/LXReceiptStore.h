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

typedef void (^LXReceiptStoreGenericCompletionBlock)(NSError *theError);
typedef void (^LXReceiptStorePaymentCompletionBlock)(LXReceiptStore *theReceiptStore, SKPaymentTransaction *thePaymentTransaction, NSError *theError);
typedef void (^LXReceiptStoreRestoreCompletionBlock)(LXReceiptStore *theReceiptStore, NSError *theError);
typedef void (^LXReceiptStoreSubscriptionsCompletionBlock)(LXReceiptStore *theReceiptStore, NSArray *theReceiptTableRows, NSError *theError);
typedef void (^LXReceiptStoreActiveSubscriptionCompletionBlock)(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo, NSError *theError);

@interface LXReceiptStore : NSObject

@property (strong, nonatomic, readonly) NSString *databasePath;
@property (strong, nonatomic, readonly) FMDatabaseQueue *databaseQueue;
@property (strong, nonatomic, readonly) CargoBay *cargoBay;
@property (strong, nonatomic, readonly) SKPaymentQueue *paymentQueue;

@property (strong, nonatomic) NSString *password;

+ (LXReceiptStore *)defaultStore;

- (id)initWithCargoBay:(CargoBay *)theCargoBay paymentQueue:(SKPaymentQueue *)thePaymentQueue;

#pragma mark - Payment Related Methods

- (void)addPayment:(SKPayment *)thePayment completionHandler:(LXReceiptStorePaymentCompletionBlock)theCompletionHandler;
- (void)restoreCompletedTransactionsWithCompletionHandler:(LXReceiptStoreRestoreCompletionBlock)theCompletionHandler;

- (void)insertTransactionReceipt:(NSData *)theTransactionReceipt completionHandler:(LXReceiptStoreActiveSubscriptionCompletionBlock)theCompletionHandler;

- (void)latestActiveSubscriptionForProductFamily:(NSString *)theProductFamily completionHandler:(LXReceiptStoreActiveSubscriptionCompletionBlock)theCompletionHandler;

@end
