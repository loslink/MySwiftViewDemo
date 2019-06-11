//
// SwiftyStoreKit.swift
// SwiftyStoreKit
//
// Copyright (c) 2015 Andrea Bizzotto (bizz84@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import StoreKit

public class SwiftyStoreKit {

    private let productsInfoController: ProductsInfoController

    private let paymentQueueController: PaymentQueueController

    fileprivate let receiptVerificator: InAppReceiptVerificator

    init(productsInfoController: ProductsInfoController = ProductsInfoController(),
         paymentQueueController: PaymentQueueController = PaymentQueueController(paymentQueue: SKPaymentQueue.default()),
         receiptVerificator: InAppReceiptVerificator = InAppReceiptVerificator()) {

        self.productsInfoController = productsInfoController
        self.paymentQueueController = paymentQueueController
        self.receiptVerificator = receiptVerificator
    }

    // MARK: Internal methods

    func retrieveProductsInfo(_ productIds: Set<String>, completion: @escaping (RetrieveResults) -> Void) {
        return productsInfoController.retrieveProductsInfo(productIds, completion: completion)
    }

    func purchaseProduct(_ productId: String, quantity: Int = 1, atomically: Bool = true, applicationUsername: String = "", completion: @escaping ( PurchaseResult) -> Void) {

        if let product = productsInfoController.products[productId] {
            purchase(product: product, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, completion: completion)
        } else {
            retrieveProductsInfo(Set([productId])) { result -> Void in
                if let product = result.retrievedProducts.first {
                    self.purchase(product: product, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, completion: completion)
                } else if let error = result.error {
                    completion(.error(error: SKError(_nsError: error as NSError)))
                } else if let invalidProductId = result.invalidProductIDs.first {
                    let userInfo = [ NSLocalizedDescriptionKey: "Invalid product id: \(invalidProductId)" ]
                    let error = NSError(domain: SKErrorDomain, code: SKError.paymentInvalid.rawValue, userInfo: userInfo)
                    completion(.error(error: SKError(_nsError: error)))
                }
            }
        }
    }

    func restorePurchases(atomically: Bool = true, applicationUsername: String = "", completion: @escaping (RestoreResults) -> Void) {

        paymentQueueController.restorePurchases(RestorePurchases(atomically: atomically, applicationUsername: applicationUsername) { results in

            let results = self.processRestoreResults(results)
            completion(results)
        })
    }

    func completeTransactions(atomically: Bool = true, completion: @escaping ([Purchase]) -> Void) {

        paymentQueueController.completeTransactions(CompleteTransactions(atomically: atomically, callback: completion))
    }

    func finishTransaction(_ transaction: PaymentTransaction) {

        paymentQueueController.finishTransaction(transaction)
    }

    // MARK: private methods
    private func purchase(product: SKProduct, quantity: Int, atomically: Bool, applicationUsername: String = "", completion: @escaping (PurchaseResult) -> Void) {
        guard SwiftyStoreKit.canMakePayments else {
            let error = NSError(domain: SKErrorDomain, code: SKError.paymentNotAllowed.rawValue, userInfo: nil)
            completion(.error(error: SKError(_nsError: error)))
            return
        }

        paymentQueueController.startPayment(Payment(product: product, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername) { result in

            completion(self.processPurchaseResult(result))
        })
    }

    private func processPurchaseResult(_ result: TransactionResult) -> PurchaseResult {
        switch result {
        case .purchased(let purchase):
            return .success(purchase: purchase)
        case .failed(let error):
            return .error(error: error)
        case .restored(let purchase):
            return .error(error: storeInternalError(description: "Cannot restore product \(purchase.productId) from purchase path"))
        }
    }

    private func processRestoreResults(_ results: [TransactionResult]) -> RestoreResults {
        var restoredPurchases: [Purchase] = []
        var restoreFailedPurchases: [(SKError, String?)] = []
        for result in results {
            switch result {
            case .purchased(let purchase):
                let error = storeInternalError(description: "Cannot purchase product \(purchase.productId) from restore purchases path")
                restoreFailedPurchases.append((error, purchase.productId))
            case .failed(let error):
                restoreFailedPurchases.append((error, nil))
            case .restored(let purchase):
                restoredPurchases.append(purchase)
            }
        }
        return RestoreResults(restoredPurchases: restoredPurchases, restoreFailedPurchases: restoreFailedPurchases)
    }

    private func storeInternalError(code: SKError.Code = SKError.unknown, description: String = "") -> SKError {
        let error = NSError(domain: SKErrorDomain, code: code.rawValue, userInfo: [ NSLocalizedDescriptionKey: description ])
        return SKError(_nsError: error)
    }
}

extension SwiftyStoreKit {

    // MARK: Singleton
    fileprivate static let sharedInstance = SwiftyStoreKit()

    // MARK: Public methods - Purchases
    
    public class var canMakePayments: Bool {
        return SKPaymentQueue.canMakePayments()
    }

    /**
     *  Retrieve products information
     *  - Parameter productIds: The set of product identifiers to retrieve corresponding products for
     *  - Parameter completion: handler for result
     */
    public class func retrieveProductsInfo(_ productIds: Set<String>, completion: @escaping (RetrieveResults) -> Void) {

        return sharedInstance.retrieveProductsInfo(productIds, completion: completion)
    }

    /**
     *  Purchase a product
     *  - Parameter productId: productId as specified in iTunes Connect
     *  - Parameter quantity: quantity of the product to be purchased
     *  - Parameter atomically: whether the product is purchased atomically (e.g. finishTransaction is called immediately)
     *  - Parameter applicationUsername: an opaque identifier for the user’s account on your system
     *  - Parameter completion: handler for result
     */
    public class func purchaseProduct(_ productId: String, quantity: Int = 1, atomically: Bool = true, applicationUsername: String = "", completion: @escaping ( PurchaseResult) -> Void) {

        sharedInstance.purchaseProduct(productId, quantity: quantity, atomically: atomically, applicationUsername: applicationUsername, completion: completion)
    }

    /**
     *  Restore purchases
     *  - Parameter atomically: whether the product is purchased atomically (e.g. finishTransaction is called immediately)
     *  - Parameter applicationUsername: an opaque identifier for the user’s account on your system
     *  - Parameter completion: handler for result
     */
    public class func restorePurchases(atomically: Bool = true, applicationUsername: String = "", completion: @escaping (RestoreResults) -> Void) {

        sharedInstance.restorePurchases(atomically: atomically, applicationUsername: applicationUsername, completion: completion)
    }

    /**
     *  Complete transactions
     *  - Parameter atomically: whether the product is purchased atomically (e.g. finishTransaction is called immediately)
     *  - Parameter completion: handler for result
     */
    public class func completeTransactions(atomically: Bool = true, completion: @escaping ([Purchase]) -> Void) {

        sharedInstance.completeTransactions(atomically: atomically, completion: completion)
    }

    /**
     *  Finish a transaction
     *  Once the content has been delivered, call this method to finish a transaction that was performed non-atomically
     *  - Parameter transaction: transaction to finish
     */
    public class func finishTransaction(_ transaction: PaymentTransaction) {

        sharedInstance.finishTransaction(transaction)
    }
}

extension SwiftyStoreKit {

    // MARK: Public methods - Receipt verification

    /**
     * Return receipt data from the application bundle. This is read from Bundle.main.appStoreReceiptURL
     */
    public static var localReceiptData: Data? {
        return sharedInstance.receiptVerificator.appStoreReceiptData
    }

    /**
     *  Verify application receipt
     *  - Parameter validator: receipt validator to use
     *  - Parameter password: Only used for receipts that contain auto-renewable subscriptions. Your app’s shared secret (a hexadecimal string).
     *  - Parameter completion: handler for result
     */
    public class func verifyReceipt(using validator: ReceiptValidator, password: String? = nil, completion: @escaping (VerifyReceiptResult) -> Void) {

        sharedInstance.receiptVerificator.verifyReceipt(using: validator, password: password, completion: completion)
    }
    
    /**
     *  Verify the purchase of a Consumable or NonConsumable product in a receipt
     *  - Parameter productId: the product id of the purchase to verify
     *  - Parameter inReceipt: the receipt to use for looking up the purchase
     *  - return: either notPurchased or purchased
     */
    public class func verifyPurchase(productId: String, inReceipt receipt: ReceiptInfo) -> VerifyPurchaseResult {

        return InAppReceipt.verifyPurchase(productId: productId, inReceipt: receipt)
    }

    /**
     *  Verify the purchase of a subscription (auto-renewable, free or non-renewing) in a receipt. This method extracts all transactions mathing the given productId and sorts them by date in descending order, then compares the first transaction expiry date against the validUntil value.
     *  - Parameter type: autoRenewable or nonRenewing
     *  - Parameter productId: the product id of the purchase to verify
     *  - Parameter inReceipt: the receipt to use for looking up the subscription
     *  - Parameter validUntil: date to check against the expiry date of the subscription. If nil, no verification
     *  - return: either .notPurchased or .purchased / .expired with the expiry date found in the receipt
     */
    public class func verifySubscription(type: SubscriptionType, productId: String, inReceipt receipt: ReceiptInfo, validUntil date: Date = Date()) -> VerifySubscriptionResult {

        return InAppReceipt.verifySubscription(type: type, productId: productId, inReceipt: receipt, validUntil: date)
    }
}