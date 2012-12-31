#LXReceiptStore#

Built on top of CargoBay, LXReceiptStore provides a simpler interface aims at helping you make sense out of your In-App Purchase receipts.

The design of `LXReceiptStore` is base on block based callback.

Receipt is store in sqlite database, unencrypted.

The reason this setup is possible is because receipt are:

1. Cryptographically signed by Apple
2. Contains device specific information (UUID, UUID for vendor)

The sqlite database is stored in cache directory. (Not suppose to be backup-able because of point 2)

The framework check that this receipt and accompanying data in sqlite database is not compromised and make attempts to verify with apple verification server. (Possible to make the latter optional but users could mess with the framework by tweaking the clock.)

This is still in development, code are available for review. Use it at your own risk.

Interfaces may drastically change over time. Need serious reviewers and users to push it to mature stage.

Not unit tested yet but must be unit tested before it reach mature stage.

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
            
[theReceiptStore
 addPayment:thePayment
 succcess:^(LXReceiptStore *theReceiptStore, SKPaymentTransaction *thePaymentTransaction) {
     NSLog(@"Purchase Succeed.");
 }
 failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
     NSLog(@"Purchase failed with error: %@", theError);
 }];
````

##Restore Purchase##
````Objective-C
[theReceiptStore
 restoreCompletedTransactionsWithSuccess:^(LXReceiptStore *theReceiptStore) {
     NSLog(@"Restore succeed.");
 }
 failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
     NSLog(@"Restore failed with error: %@", theError);
 }];
````

##Query for Latest Active Subscription (Will attempts to fetch and store renewed receipt)##
````Objective-C
NSString *theProductFamily = @"com.example.iap.ars.best-internet-tv-eva.%"; // The syntax of SQL LIKE command.
[theReceiptStore
 latestActiveSubscriptionForProductFamily:theProductFamily
 success:^(LXReceiptStore *theReceiptStore, NSDictionary *theReceiptTableRow, NSDictionary *PurchaseInfo) {
	 // BEST INTERNET TV EVA TIME!
     MPMoviePlayerViewController *theMoviePlayerViewController = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL URLWithString:[SettingsManager sharedManager].link]];
     [self presentMoviePlayerViewControllerAnimated:theMoviePlayerViewController];
 } failure:^(LXReceiptStore *theReceiptStore, NSError *theError) {
	 NSLog(@"No TV for you. :( ");
	 NSLog(@"Restore or subscribe.");
	 NSLog(@"Error: %@", theError);
 }];
````