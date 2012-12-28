#LXReceiptStore#

Built on top of CargoBay, LXReceiptStore provides a simpler interface aims at helping you make sense out of your In-App Purchase receipts.

The design of `LXReceiptStore` is base on block based callback.

Receipt is store in sqlite database, unencrypted.

The reason this setup is possible is because receipt are cryptographically signed by Apple. The framework check that this receipt and accompanying data in sqlite is not compromised and make attempts to verify with apple verification receipt server. (Possible to make the latter optional but users could mess with the framework by tweaking the clock.)

This is still in development, code are available for review. Use it at your own risk.

Interfaces may drastically change over time. Need serious reviewers and users to push it to mature stage.

#Getting Started#
##Initialization##
````Objective-C
// Singleton (Uses [CargoBay defaultManager] and [SKPaymentQueue defaultQueue])
LXReceiptStore *theReceiptStore = [LXReceiptStore defaultStore];

// Instances
SKPaymentQueue *thePaymentQueue = [[SKPaymentQueue alloc] init];
CargoBay *theCargoBay = [[CargoBay alloc] init];
LXReceiptStore *theReceiptStore = [[LXReceiptStore alloc] initWithCargoBay:theCargoBay paymentQueue:thePaymentQueue];

// Setting shared secret (password) - Required for verifying auto-renewable subscription.
theReceiptStore.password = @"password";
````

##Make Purchase##
````Objective-C
SKPayment *thePayment = [SKPayment paymentWithProduct:theProduct];
            
[theReceiptStore addPayment:thePayment completionHandler:^(LXReceiptStore *theReceiptStore, SKPaymentTransaction *thePaymentTransaction, NSError *theError) {
    if (theError) {
        NSLog(@"Error: %@", theError);
        return;
    }
                
    switch (thePaymentTransaction.transactionState) {
        case SKPaymentTransactionStatePurchased: {
            NSLog(@"Succeed %@.", thePaymentTransaction.transactionIdentifier);
        } break;
		default: {
            [NSException raise:NSInternalInconsistencyException format:@"Unexpected execution path."];
        } break;
    }
}];
````

##Restore Purchase##
````Objective-C
[theReceiptStore restoreCompletedTransactionsWithCompletionHandler:^(LXReceiptStore *theReceiptStore, NSError *theError) {
    if (theError) { 
        NSLog(@"Error: %@", theError);
		return;
    }
	
	NSLog(@"Restore success.");
}];
````

##Query for Latest Active Subscription (Will attempts to fetch and store renewed receipt)##
````Objective-C
NSString *theProductFamily = @"com.example.iap.ars.best-internet-tv-ever.%"; // The syntax of SQL LIKE command.
[theReceiptStore latestActiveSubscriptionForProductFamily:theProductFamily completionHandler:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo, NSError *theError) {
    if (theError) {
        NSLog(@"Error: %@", theError);
		NSLog(@"No TV for you. :(");
		return;
    }
		
    MPMoviePlayerViewController *theMoviePlayerViewController = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL URLWithString:@"http://example.com/best-internet-tv-ever"]];
    [self presentMoviePlayerViewControllerAnimated:theMoviePlayerViewController];
}];
````
