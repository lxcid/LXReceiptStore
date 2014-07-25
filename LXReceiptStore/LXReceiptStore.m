//
//  LXReceiptStore.m
//  CTN
//
//  Created by Stan Chang Khin Boon on 26/12/12.
//  Copyright (c) 2012 d--buzz. All rights reserved.
//

#import "LXReceiptStore.h"
#import "FMDatabase.h"
#import "FMDatabaseQueue.h"
#import "CargoBay.h"
#import <StoreKit/StoreKit.h>

extern NSDictionary * CBPurchaseInfoFromTransactionReceipt(NSData *transactionReceiptData, NSError * __autoreleasing *error);
extern NSData * CBDataFromBase64EncodedString(NSString *base64EncodedString);

// Enforces restoration to 1 at a time.

NSString * const LXReceiptStoreErrorDomain = @"com.lxcid.LXReceiptStore.ErrorDomain";


static NSString *LXReceiptStoreDropReceiptTableSQL = @"DROP TABLE IF EXISTS `receipt`;";
static NSString *LXReceiptStoreCreateReceiptTableSQL = @"CREATE TABLE IF NOT EXISTS `receipt` (`transaction_receipt` BLOB NOT NULL, `product_id` TEXT NOT NULL, `expires_date` INTEGER, `transaction_id` TEXT PRIMARY KEY NOT NULL UNIQUE, `purchase_date` INTEGER NOT NULL, `original_transaction_id` TEXT NOT NULL);";
static NSString *LXReceiptStoreInsertIntoReceiptTableSQL = @"INSERT OR IGNORE INTO `receipt` (`transaction_id`, `original_transaction_id`, `product_id`, `purchase_date`, `expires_date`, `transaction_receipt`) VALUES (?, ?, ?, ?, ?, ?);";
static NSString *LXReceiptStoreSelectFromReceiptTableWithProductIDSQL = @"SELECT * FROM `receipt` WHERE `product_id` LIKE ? ORDER BY `expires_date` DESC LIMIT 1;";
static NSString *LXReceiptStoreSelectFromReceiptTableWithProductIDBetweenDateSQL = @"SELECT * FROM `receipt` WHERE `product_id` LIKE ? AND ? BETWEEN `purchase_date` AND `expires_date` ORDER BY `expires_date` DESC;";
static NSString *LXReceiptStoreSelectFromReceiptTableSQL = @"SELECT * FROM `receipt`;";


@interface LXReceiptStore ()

@property (strong, nonatomic, readwrite) NSString *databasePath;
@property (strong, nonatomic, readwrite) FMDatabaseQueue *databaseQueue;
@property (strong, nonatomic, readwrite) CargoBay *cargoBay;
@property (strong, nonatomic, readwrite) SKPaymentQueue *paymentQueue;

@property (strong, nonatomic) NSMutableArray *paymentDictionaries;

@property (assign, nonatomic, getter = isRestorationInProgress) BOOL restorationInProgress;

@end


@implementation LXReceiptStore


#pragma mark - Class Methods


// Fetch database path.
// Database path is stored in cache directory (As of current is is not designed to be backup-able and icloud-able)
// Database path is of the following format <cache directory>/com.lxcid.LXReceiptStore/receipt_store.db.
+ (NSString *)databasePathWithError:(NSError *__autoreleasing *)theError {
    NSArray *thePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([thePaths count] == 0) {
        if (theError != NULL) {
            NSDictionary *theUserInfo = @{
            NSLocalizedDescriptionKey : @"Fails to construct database path because no cache directory available.",
            NSLocalizedFailureReasonErrorKey : @"No cache directory available."
            };
            *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorUnableToConstructDatabasePath userInfo:theUserInfo];
        }
        return nil;
    }
    
    NSString *theCachePath = thePaths[0];
    NSString *theLXReceiptStorePath = [theCachePath stringByAppendingPathComponent:@"com.lxcid.LXReceiptStore"];
    BOOL isDir = NO;
    NSFileManager *theFileManager = [NSFileManager defaultManager];
    if (![theFileManager fileExistsAtPath:theLXReceiptStorePath isDirectory:&isDir]) {
        if (![theFileManager createDirectoryAtPath:theLXReceiptStorePath withIntermediateDirectories:YES attributes:nil error:theError]) {
            return nil;
        }
        isDir = YES;
    }
    if (!isDir) {
        if (theError != NULL) {
            NSDictionary *theUserInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Fails to construct database path because %@ is not a directory.", theLXReceiptStorePath],
            NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"%@ is not a directory.", theLXReceiptStorePath]
            };
            *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorUnableToConstructDatabasePath userInfo:theUserInfo];
        }
        return nil;
    }
    NSString *theDatabasePath = [theLXReceiptStorePath stringByAppendingPathComponent:@"receipt_store.db"];
    return theDatabasePath;
}


// Singleton
// Default store goes with default cargobay and default payment queue.
+ (LXReceiptStore *)defaultStore {
    static dispatch_once_t theOnceToken = 0;
    static LXReceiptStore *theReceiptStore = nil;
    
    dispatch_once(&theOnceToken, ^{
        theReceiptStore = [[LXReceiptStore alloc] initWithCargoBay:nil paymentQueue:nil];
    });
    
    return theReceiptStore;
}


#pragma mark - Initialization/Deallocation Methods


- (id)initWithCargoBay:(CargoBay *)theCargoBay paymentQueue:(SKPaymentQueue *)thePaymentQueue {
    self = [super init];
    if (self) {
        self.paymentDictionaries = [NSMutableArray array];
        
        if (theCargoBay == nil) {
            theCargoBay = [CargoBay sharedManager];
        }
        self.cargoBay = theCargoBay;
        
        if (thePaymentQueue == nil) {
            thePaymentQueue = [SKPaymentQueue defaultQueue];
        }
        self.paymentQueue = thePaymentQueue;
        
        [self setUpCargoBay:self.cargoBay paymentQueue:self.paymentQueue];
        
        NSError *theError = nil;
        self.databasePath = [LXReceiptStore databasePathWithError:&theError];
        if (self.databasePath == nil) {
            [NSException raise:NSInternalInconsistencyException format:@"[%@:%d] %@", theError.domain, theError.code, theError.localizedDescription];
            return nil;
        }
        
        self.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:self.databasePath];
        if (self.databaseQueue == nil) {
            [NSException raise:NSInternalInconsistencyException format:@"Fails to instantiate a database queue."];
            return nil;
        }
        
        [self.databaseQueue inTransaction:^(FMDatabase *theDatabase, BOOL *theRollback) {
            // `receipt` TABLE
            {
                if (![theDatabase executeUpdate:LXReceiptStoreCreateReceiptTableSQL]) {
                    NSError *theError = [theDatabase lastError];
                    [NSException raise:NSInternalInconsistencyException format:@"[%@:%d] %@", theError.domain, theError.code, theError.localizedDescription];
                    *theRollback = YES;
                    return;
                }
            }
        }];
    }
    return self;
}

- (void)dealloc {
    [self.paymentQueue removeTransactionObserver:self.cargoBay];
}


#pragma mark - Set Up Methods


- (void)setUpCargoBay:(CargoBay *)theCargoBay paymentQueue:(SKPaymentQueue *)thePaymentQueue {
    __weak __typeof(self) theWeakSelf = self;
    
    [self.cargoBay setPaymentQueueUpdatedTransactionsBlock:^(SKPaymentQueue *theQueue, NSArray *theTransactions) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        
        if (!theStrongSelf) {
            return;
        }
        
        for (SKPaymentTransaction *theTransaction in theTransactions) {
            switch (theTransaction.transactionState) {
                case SKPaymentTransactionStatePurchased: {
                    NSMutableDictionary *theOrphanPaymentDictionary = [theStrongSelf anyOrphanPaymentDictionaryWithProductIdentifier:theTransaction.payment.productIdentifier quantity:theTransaction.payment.quantity];
                    if (theOrphanPaymentDictionary) {
                        theOrphanPaymentDictionary[@"transactionIdentifier"] = theTransaction.transactionIdentifier;
                    }
                    [theStrongSelf
                     insertTransactionReceipt:theTransaction.transactionReceipt
                     success:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo) {
                         [theQueue finishTransaction:theTransaction];
                     }
                     failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
                         if (theOrphanPaymentDictionary) {
                             theOrphanPaymentDictionary[@"error"] = theError;
                         }
                         [theQueue finishTransaction:theTransaction];
                     }];
                } break;
                case SKPaymentTransactionStateFailed: {
                    NSMutableDictionary *theOrphanPaymentDictionary = [theStrongSelf anyOrphanPaymentDictionaryWithProductIdentifier:theTransaction.payment.productIdentifier quantity:theTransaction.payment.quantity];
                    if (theOrphanPaymentDictionary) {
                        theOrphanPaymentDictionary[@"transactionIdentifier"] = theTransaction.transactionIdentifier;
                    }
                    [theQueue finishTransaction:theTransaction];
                } break;
                case SKPaymentTransactionStateRestored: {
                    [theStrongSelf
                     insertTransactionReceipt:theTransaction.transactionReceipt
                     success:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo) {
                         [theQueue finishTransaction:theTransaction];
                     }
                     failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
                         [theQueue finishTransaction:theTransaction];
                     }];
                } break;
            }
        }
    }];
    
    [self.cargoBay setPaymentQueueRemovedTransactionsBlock:^(SKPaymentQueue *theQueue, NSArray *theTransactions) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        
        if (!theStrongSelf) {
            return;
        }
        
        for (SKPaymentTransaction *theTransaction in theTransactions) {
            switch (theTransaction.transactionState) {
                case SKPaymentTransactionStateFailed: {
                    NSMutableDictionary *thePaymentDictionary = [theStrongSelf paymentDictionaryWithTransactionID:theTransaction.transactionIdentifier];
                    if (thePaymentDictionary) {
                        [theStrongSelf.paymentDictionaries removeObject:thePaymentDictionary];
                        LXReceiptStoreGenericFailureBlock theFailure = thePaymentDictionary[@"failure"];
                        theFailure(theStrongSelf, theTransaction.error);
                    }
                } break;
                case SKPaymentTransactionStatePurchased: {
                    NSMutableDictionary *thePaymentDictionary = [theStrongSelf paymentDictionaryWithTransactionID:theTransaction.transactionIdentifier];
                    if (thePaymentDictionary) {
                        [theStrongSelf.paymentDictionaries removeObject:thePaymentDictionary];
                        NSError *theError = thePaymentDictionary[@"error"];
                        if (theError) {
                            LXReceiptStoreGenericFailureBlock theFailure = thePaymentDictionary[@"failure"];
                            theFailure(theStrongSelf, theError);
                        } else {
                            LXReceiptStoreAddPaymentSuccessBlock theSuccess = thePaymentDictionary[@"success"];
                            theSuccess(theStrongSelf, theTransaction);
                        }
                    }
                } break;
            }
        }
    }];
    
    [self.paymentQueue addTransactionObserver:self.cargoBay];
}


#pragma mark - Helper Methods


- (NSMutableDictionary *)anyOrphanPaymentDictionaryWithProductIdentifier:(NSString *)theProductIdentifier quantity:(NSInteger)theQuantity {
    NSPredicate *thePredicate = [NSPredicate predicateWithFormat:@"productIdentifier = %@ AND quantity = %d AND transactionIdentifier = NIL", theProductIdentifier, theQuantity];
    NSArray *theOrphanPaymentDictionaries = [self.paymentDictionaries filteredArrayUsingPredicate:thePredicate];
    return [theOrphanPaymentDictionaries lastObject];
}


- (NSMutableDictionary *)paymentDictionaryWithTransactionID:(NSString *)theTransactionIndentifier {
    NSPredicate *thePredicate = [NSPredicate predicateWithFormat:@"transactionIdentifier = %@", theTransactionIndentifier];
    NSArray *thePaymentDictionaries = [self.paymentDictionaries filteredArrayUsingPredicate:thePredicate];
    return [thePaymentDictionaries lastObject];
}


- (NSDictionary *)purchaseInfoFromReceiptTableRow:(NSDictionary *)theReceiptTableRow error:(NSError *__autoreleasing *)theError {
    NSData *theTransactionReceipt = theReceiptTableRow[@"transaction_receipt"];
    
    NSDictionary *thePurchaseInfo = CBPurchaseInfoFromTransactionReceipt(theTransactionReceipt, theError);
    if (!thePurchaseInfo) {
        return nil;
    }
    
    // Checks that purchase info's bundle ID matches app bundle ID
    {
        NSString *thePurchaseInfoBundleID = thePurchaseInfo[@"bid"];
        NSString *theAppBundleID = [NSBundle mainBundle].bundleIdentifier;
        if (![thePurchaseInfoBundleID isEqual:theAppBundleID]) {
            if (theError != NULL) {
                NSDictionary *theUserInfo =
                [NSDictionary dictionaryWithObjectsAndKeys:
                 [NSString stringWithFormat:@"Transaction does not match purchase info because purchase info's bundle ID (%@) does not match the app bundle ID (%@).", thePurchaseInfoBundleID, theAppBundleID], NSLocalizedDescriptionKey,
                 [NSString stringWithFormat:@"Purchase info's bundle ID (%@) does not match the app bundle ID (%@).", thePurchaseInfoBundleID, theAppBundleID], NSLocalizedFailureReasonErrorKey,
                 nil];
                *theError = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:theUserInfo];
            }
            return nil;
        }
    }
    
    // Checks the purchase info's unique identifier matches the device unique identifier
    {
        if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"identifierForVendor")]) {
#if (__IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1)
            NSString *theDeviceUniqueVendorIdentifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            NSString *thePurchaseInfoUniqueVendorIdentifier = [thePurchaseInfo objectForKey:@"unique-vendor-identifier"];
            
            if (![theDeviceUniqueVendorIdentifier isEqual:thePurchaseInfoUniqueVendorIdentifier]) {
#if !TARGET_IPHONE_SIMULATOR
                if (theError != NULL) {
                    NSDictionary *theUserInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because device's unique vendor identifier (%@) does not match purchase info's unique vendor identifier (%@).", theDeviceUniqueVendorIdentifier, thePurchaseInfoUniqueVendorIdentifier],
                    NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Device's unique vendor identifier (%@) does not match purchase info's unique vendor identifier (%@).", theDeviceUniqueVendorIdentifier, thePurchaseInfoUniqueVendorIdentifier]
                    };
                    *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
                }
                return nil;
#endif
            }
#endif
        } else if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"uniqueIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            NSString *theDeviceUniqueIdentifier = [[UIDevice currentDevice] uniqueIdentifier];
#pragma clang diagnostic pop
            NSString *thePurchaseInfoUniqueIdentifier = [thePurchaseInfo objectForKey:@"unique-identifier"];
            
            if (![theDeviceUniqueIdentifier isEqual:thePurchaseInfoUniqueIdentifier]) {
                if (theError != NULL) {
                    NSDictionary *theUserInfo = @{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because device's unique identifier (%@) does not match purchase info's unique identifier (%@).", theDeviceUniqueIdentifier, thePurchaseInfoUniqueIdentifier],
                    NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Device's unique identifier (%@) does not match purchase info's unique identifier (%@).", theDeviceUniqueIdentifier, thePurchaseInfoUniqueIdentifier]
                    };
                    *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
                }
                return nil;
            }
        }
    }
    
    // Makes sure that receipt table row is not compromised.
    {
        NSString *theReceiptTableRowTransactionID = [theReceiptTableRow objectForKey:@"transaction_id"];
        NSString *thePurchaseInfoTransactionID = [thePurchaseInfo objectForKey:@"transaction-id"];
        if (![theReceiptTableRowTransactionID isEqual:thePurchaseInfoTransactionID]) {
            if (theError != NULL) {
                NSDictionary *theUserInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because receipt table row's transaction ID (%@) does not match purchase info's transaction ID (%@).", theReceiptTableRowTransactionID, thePurchaseInfoTransactionID],
                NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Receipt table row's transaction ID (%@) does not match purchase info's transaction ID (%@).", theReceiptTableRowTransactionID, thePurchaseInfoTransactionID]
                };
                *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
            }
            return nil;
        }
    }
    {
        NSString *theReceiptTableRowOriginalTransactionID = [theReceiptTableRow objectForKey:@"original_transaction_id"];
        NSString *thePurchaseInfoOriginalTransactionID = [thePurchaseInfo objectForKey:@"original-transaction-id"];
        if (![theReceiptTableRowOriginalTransactionID isEqual:thePurchaseInfoOriginalTransactionID]) {
            if (theError != NULL) {
                NSDictionary *theUserInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because receipt table row's original transaction ID (%@) does not match purchase info's original transaction ID (%@).", theReceiptTableRowOriginalTransactionID, thePurchaseInfoOriginalTransactionID],
                NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Receipt table row's original transaction ID (%@) does not match purchase info's original transaction ID (%@).", theReceiptTableRowOriginalTransactionID, thePurchaseInfoOriginalTransactionID]
                };
                *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
            }
            return nil;
        }
    }
    {
        NSString *theReceiptTableRowProductID = [theReceiptTableRow objectForKey:@"product_id"];
        NSString *thePurchaseInfoProductID = [thePurchaseInfo objectForKey:@"product-id"];
        if (![theReceiptTableRowProductID isEqual:thePurchaseInfoProductID]) {
            if (theError != NULL) {
                NSDictionary *theUserInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because receipt table row's product ID (%@) does not match purchase info's product ID (%@).", theReceiptTableRowProductID, thePurchaseInfoProductID],
                NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Receipt table row's product ID (%@) does not match purchase info's product ID (%@).", theReceiptTableRowProductID, thePurchaseInfoProductID]
                };
                *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
            }
            return nil;
        }
    }
    {
        long long theReceiptTableRowPurchaseDateUnixTime = [theReceiptTableRow[@"purchase_date"] longLongValue];
        NSString *thePurchaseInfoPurchaseDate = thePurchaseInfo[@"purchase-date-ms"];
        long long thePurchaseInfoPurchaseDateUnixTime = [thePurchaseInfoPurchaseDate longLongValue] / 1000LL;
        if (theReceiptTableRowPurchaseDateUnixTime != thePurchaseInfoPurchaseDateUnixTime) {
            if (theError != NULL) {
                NSDictionary *theUserInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because receipt table row's purchase date (%@) does not match purchase info's purchase date (%@).", [NSDate dateWithTimeIntervalSince1970:theReceiptTableRowPurchaseDateUnixTime], [NSDate dateWithTimeIntervalSince1970:thePurchaseInfoPurchaseDateUnixTime]],
                NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Receipt table row's purchase date (%@) does not match purchase info's purchase date (%@).", [NSDate dateWithTimeIntervalSince1970:theReceiptTableRowPurchaseDateUnixTime], [NSDate dateWithTimeIntervalSince1970:thePurchaseInfoPurchaseDateUnixTime]]
                };
                *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
            }
            return nil;
        }
    }
    {
        long long theReceiptTableRowExpiresDateUnixTime = [theReceiptTableRow[@"expires_date"] longLongValue];
        NSString *thePurchaseInfoExpiresDate = thePurchaseInfo[@"expires-date"];
        long long thePurchaseInfoExpiresDateUnixTime = [thePurchaseInfoExpiresDate longLongValue] / 1000LL;
        if (theReceiptTableRowExpiresDateUnixTime != thePurchaseInfoExpiresDateUnixTime) {
            if (theError != NULL) {
                NSDictionary *theUserInfo = @{
                NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Invalid receipt table row because receipt table row's expires date (%@) does not match purchase info's expires date (%@).", [NSDate dateWithTimeIntervalSince1970:theReceiptTableRowExpiresDateUnixTime], [NSDate dateWithTimeIntervalSince1970:thePurchaseInfoExpiresDateUnixTime]],
                NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:@"Receipt table row's expires date (%@) does not match purchase info's expires date (%@).", [NSDate dateWithTimeIntervalSince1970:theReceiptTableRowExpiresDateUnixTime], [NSDate dateWithTimeIntervalSince1970:thePurchaseInfoExpiresDateUnixTime]]
                };
                *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorInvalidReceiptTableRow userInfo:theUserInfo];
            }
            return nil;
        }
    }
    
    return thePurchaseInfo;
}


#pragma mark - Payment Related Methods


- (void)addPayment:(SKPayment *)thePayment succcess:(LXReceiptStoreAddPaymentSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    if (![SKPaymentQueue canMakePayments]) {
        NSDictionary *theUserInfo = @{
        NSLocalizedDescriptionKey : @"Fails to add payment because user is not allowed to authorize payment.",
        NSLocalizedFailureReasonErrorKey : @"User is not allowed to authorize payment."
        };
        NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorFailsToAddPayment userInfo:theUserInfo];
        
        theFailure(self, theError);
        return;
    }
    
    NSMutableDictionary *thePaymentDictionary =
    [@{
     @"productIdentifier" : thePayment.productIdentifier,
     @"quantity" : @(thePayment.quantity)
     } mutableCopy];
    thePaymentDictionary[@"success"] = [theSuccess copy];
    thePaymentDictionary[@"failure"] = [theFailure copy];
    [self.paymentDictionaries addObject:thePaymentDictionary];
    [self.paymentQueue addPayment:thePayment];
}


- (void)restoreCompletedTransactionsWithSuccess:(LXReceiptStoreGenericSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    if (self.isRestorationInProgress) {
        NSDictionary *theUserInfo = @{
        NSLocalizedDescriptionKey : @"Fails to restore completed transaction because another restoration is already in progress.",
        NSLocalizedFailureReasonErrorKey : @"Another restoration is already in progress."
        };
        NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorFailsToRestoreCompletedTransactions userInfo:theUserInfo];
        theFailure(self, theError);
        return;
    }
    self.restorationInProgress = YES;
    
    [self
     truncateReceiptTableWithSuccess:^(LXReceiptStore *theReceiptStore) {
         __weak LXReceiptStore *theWeakReceiptStore = theReceiptStore;
         
         [theReceiptStore.cargoBay
          setPaymentQueueRestoreCompletedTransactionsWithSuccess:^(SKPaymentQueue *theQueue) {
              __strong LXReceiptStore *theStrongReceiptStore = theWeakReceiptStore;
              if (theStrongReceiptStore == nil) {
                  return;
              }
              
              theSuccess(theStrongReceiptStore);
              [theStrongReceiptStore.cargoBay setPaymentQueueRestoreCompletedTransactionsWithSuccess:nil failure:nil];
              theStrongReceiptStore.restorationInProgress = NO;
          }
          failure:^(SKPaymentQueue *theQueue, NSError *theError) {
              __strong LXReceiptStore *theStrongReceiptStore = theWeakReceiptStore;
              if (theStrongReceiptStore == nil) {
                  return;
              }
              
              theFailure(theStrongReceiptStore, theError);
              [theStrongReceiptStore.cargoBay setPaymentQueueRestoreCompletedTransactionsWithSuccess:nil failure:nil];
              theStrongReceiptStore.restorationInProgress = NO;
          }];
         
         
         [theReceiptStore.paymentQueue restoreCompletedTransactions];
     }
     failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
         theFailure(theReceiptStore, theError);
     }];
}


#pragma mark - Database Queries and Updates Methods


- (void)insertTransactionReceipt:(NSData *)theTransactionReceipt success:(LXReceiptStoreInsertTransactionDataSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    NSDictionary *thePurchaseInfo = nil;
    
    {
        NSError *theError = nil;
        thePurchaseInfo = CBPurchaseInfoFromTransactionReceipt(theTransactionReceipt, &theError);
        if (thePurchaseInfo == nil) {
            theFailure(self, theError);
            return;
        }
    }
    
    __weak __typeof(self) theWeakSelf = self;
    
    [self.databaseQueue inTransaction:^(FMDatabase *theDatabase, BOOL *theRollback) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        if (theStrongSelf == nil) {
            return;
        }
        
        
        NSString *theProductID = thePurchaseInfo[@"product-id"];
        NSString *theTransactionID = thePurchaseInfo[@"transaction-id"];
        NSString *theOriginalTransactionID = thePurchaseInfo[@"original-transaction-id"];
        NSString *thePurchaseDate = thePurchaseInfo[@"purchase-date-ms"];
        long long thePurchaseDateUnixTime = [thePurchaseDate longLongValue] / 1000LL;
        NSString *theExpiresDate = thePurchaseInfo[@"expires-date"];
        long long theExpiresDateUnixTime = [theExpiresDate longLongValue] / 1000LL;
        
        if (![theDatabase executeUpdate:LXReceiptStoreInsertIntoReceiptTableSQL, theTransactionID, theOriginalTransactionID, theProductID, @(thePurchaseDateUnixTime), @(theExpiresDateUnixTime), theTransactionReceipt]) {
            NSError *theError = [theDatabase lastError];
            *theRollback = YES;
            theFailure(theStrongSelf, theError);
            return;
        }
        
        NSDictionary *theReceiptDictionary = @{
        @"transaction_id" : theTransactionID,
        @"original_transaction_id" : theOriginalTransactionID,
        @"product_id" : theProductID,
        @"purchase_date" : @(thePurchaseDateUnixTime),
        @"expires_date" : @(theExpiresDateUnixTime),
        @"transaction_receipt" : theTransactionReceipt
        };
        
        theSuccess(theStrongSelf, theReceiptDictionary, thePurchaseInfo);
    }];
}


- (void)truncateReceiptTableWithSuccess:(LXReceiptStoreGenericSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    __weak __typeof(self) theWeakSelf = self;
    
    [self.databaseQueue inTransaction:^(FMDatabase *theDatabase, BOOL *theRollback) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        if (theStrongSelf == nil) {
            return;
        }
        
        if (![theDatabase executeUpdate:LXReceiptStoreDropReceiptTableSQL]) {
            NSError *theError = [theDatabase lastError];
            *theRollback = YES;
            theFailure(theStrongSelf, theError);
            return;
        }
        
        if (![theDatabase executeUpdate:LXReceiptStoreCreateReceiptTableSQL]) {
            NSError *theError = [theDatabase lastError];
            *theRollback = YES;
            theFailure(theStrongSelf, theError);
            return;
        }
        
        theSuccess(theStrongSelf);
    }];
}


- (void)subscriptionsForProductFamily:(NSString *)theProductFamily date:(NSDate *)theDate completionHandler:(LXReceiptStoreSubscriptionsSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    __weak __typeof(self) theWeakSelf = self;
    
    [self.databaseQueue inDatabase:^(FMDatabase *theDatabase) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        if (theStrongSelf == nil) {
            return;
        }
        
        FMResultSet *theResultSet = [theDatabase executeQuery:LXReceiptStoreSelectFromReceiptTableWithProductIDBetweenDateSQL, theProductFamily, (long long)[theDate timeIntervalSince1970]];
        
        if (!theResultSet) {
            NSError *theError = [theDatabase lastError];
            theFailure(theStrongSelf, theError);
            [theResultSet close];
            return;
        }
        
        NSMutableArray *theReceiptTableRows = [NSMutableArray array];
        while ([theResultSet next]) {
            NSDictionary *theReceiptTableRow = [theResultSet resultDictionary];
            [theReceiptTableRows addObject:theReceiptTableRow];
        }
        
        theSuccess(theStrongSelf, theReceiptTableRows);
        [theResultSet close];
    }];
}

- (void)latestSubscriptionForProductFamily:(NSString *)theProductFamily success:(LXReceiptStoreLatestSubscriptionSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    __weak __typeof(self) theWeakSelf = self;
    
    [self.databaseQueue inDatabase:^(FMDatabase *theDatabase) {
        __strong __typeof(self) theStrongSelf = theWeakSelf;
        if (theStrongSelf == nil) {
            return;
        }
        
        FMResultSet *theResultSet = [theDatabase executeQuery:LXReceiptStoreSelectFromReceiptTableWithProductIDSQL, theProductFamily];
        
        if (!theResultSet) {
            NSError *theError = [theDatabase lastError];
            theFailure(theStrongSelf, theError);
            [theResultSet close];
            return;
        }
        
        if (![theResultSet next]) {
            NSDictionary *theUserInfo = @{
            NSLocalizedDescriptionKey : @"No subscription available because no receipt is found.",
            NSLocalizedFailureReasonErrorKey : @"No receipt is found."
            };
            NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorNoSubscriptionAvailable userInfo:theUserInfo];
            theFailure(theStrongSelf, theError);
            [theResultSet close];
            return;
        }
        
        NSDictionary *theReceiptTableRow = [theResultSet resultDictionary];
        
        theSuccess(theStrongSelf, theReceiptTableRow);
        [theResultSet close];
    }];
}

- (void)latestActiveSubscriptionForProductFamily:(NSString *)theProductFamily success:(LXReceiptStoreActiveSubscriptionSuccessBlock)theSuccess failure:(LXReceiptStoreGenericFailureBlock)theFailure {
    [self
     latestSubscriptionForProductFamily:theProductFamily
     success:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow) {
         NSNumber *theExpiresDate = theReceiptTableRow[@"expires_date"];
         if (!theExpiresDate || [theExpiresDate isEqual:[NSNull null]]) {
             NSDictionary *theUserInfo = @{
             NSLocalizedDescriptionKey : @"No subscription available because the receipt is not an auto-renewable subscription one.",
             NSLocalizedFailureReasonErrorKey : @"The receipt is not an auto-renewable subscription one."
             };
             NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorNoSubscriptionAvailable userInfo:theUserInfo];
             theFailure(theReceiptStore, theError);
             return;
         }
         
         if (theReceiptStore.password.length == 0) {
             NSDictionary *theUserInfo = @{
             NSLocalizedDescriptionKey : @"No subscription available because the shared secret (password) is required for verification.",
             NSLocalizedFailureReasonErrorKey : @"The shared secret (password) is required for verification."
             };
             NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorNoSubscriptionAvailable userInfo:theUserInfo];
             theFailure(theReceiptStore, theError);
             return;
         }
         
         NSData *theTransactionReceipt = theReceiptTableRow[@"transaction_receipt"];
         
         __weak LXReceiptStore *theWeakReceiptStore = theReceiptStore;
         
         
         [theReceiptStore.cargoBay
          verifyTransactionReceipt:theTransactionReceipt
          password:theReceiptStore.password
          success:^(NSDictionary *theResponseObject) {
              __strong LXReceiptStore *theStrongReceiptStore = theWeakReceiptStore;
              if (theStrongReceiptStore == nil) {
                  return;
              }
              
              CargoBayStatusCode theStatusCode = (CargoBayStatusCode)[theResponseObject[@"status"] integerValue];
              switch (theStatusCode) {
                  case CargoBayStatusOK: {
                      NSString *theLatestReceipt = theResponseObject[@"latest_receipt"];
                      if (!theLatestReceipt) {
                          NSDictionary *theUserInfo = @{
                          NSLocalizedDescriptionKey : @"No subscription available because the current receipt does not contains the latest receipt.",
                          NSLocalizedFailureReasonErrorKey : @"The current receipt does not contains the latest receipt."
                          };
                          NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorNoSubscriptionAvailable userInfo:theUserInfo];
                          theFailure(theStrongReceiptStore, theError);
                          return;
                      }
                      NSData *theLatestTransactionReceipt = CBDataFromBase64EncodedString(theLatestReceipt);
                      
                      [theStrongReceiptStore
                       insertTransactionReceipt:theLatestTransactionReceipt
                       success:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo) {
                           theSuccess(theReceiptStore, theReceiptTableRow, theReceiptTableRow);
                       }
                       failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
                           theFailure(theReceiptStore, theError);
                       }];
                  } break;
                  case CargoBayStatusReceiptValidButSubscriptionExpired: {
                      NSDictionary *theUserInfo = @{
                      NSLocalizedDescriptionKey : @"No subscription available because the subscription has expired.",
                      NSLocalizedFailureReasonErrorKey : @"The subscription has expired."
                      };
                      NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorNoSubscriptionAvailable userInfo:theUserInfo];
                      theFailure(theStrongReceiptStore, theError);
                  } break;
                  default: {
                      NSDictionary *theUserInfo = @{
                      NSLocalizedDescriptionKey : @"No subscription available because of unknown reason.",
                      NSLocalizedFailureReasonErrorKey : @"Of Unknown reason."
                      };
                      NSError *theError = [NSError errorWithDomain:LXReceiptStoreErrorDomain code:LXReceiptStoreErrorUnknown userInfo:theUserInfo];
                      theFailure(theStrongReceiptStore, theError);
                  } break;
              }
              
              
          }
          failure:^(NSError *theError) {
              __strong LXReceiptStore *theStrongReceiptStore = theWeakReceiptStore;
              if (theStrongReceiptStore == nil) {
                  return;
              }
              
              theFailure(theStrongReceiptStore, theError);
          }];
     }
     failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
         theFailure(theReceiptStore, theError);
     }];
}


- (NSArray *)dumpReceiptTable {
    NSMutableArray *theReceipts = [NSMutableArray array];
    
    [self.databaseQueue inDatabase:^(FMDatabase *theDatabase) {
        
        FMResultSet *theResultSet = [theDatabase executeQuery:LXReceiptStoreSelectFromReceiptTableSQL];
        
        if (!theResultSet) {
            __unused NSError *theError = [theDatabase lastError];
            [theResultSet close];
            return;
        }
        
        while ([theResultSet next]) {
            NSDictionary *theReceiptTableRow = [theResultSet resultDictionary];
            [theReceipts addObject:theReceiptTableRow];
        }
        
        [theResultSet close];
    }];
    
    return theReceipts;
}


@end
