//
//  PaymentViewController.swift
//  QPayDemoObjC
//
//  Created by Kyle M on 3/25/21.
//

import UIKit

import QuantumSDK

import QuantumPayClient
import QuantumPayMobile
import QuantumPayPeripheral

/**
 The QuantumPaySDK are all Swift, so to interact with it, all functions need to be called within Swift file. You can create a wrapper and expose custom wrapper functions to ObjC if needed. Then pass in information for the PaymentEngine to process in Swift.
 */
class PaymentViewController: UIViewController {
    
    @IBOutlet weak var outputTextView: UITextView!
    
    var pEngine: PaymentEngine?
    var transaction: Transaction?
    var transactionResult: TransactionResult?
    
    /// Payment device
    var paymentDevice: QPR250?
    
    // Use unknown BLE device
    //var paymentDevice: QPR250?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        
        /// **To check payment related settings, please take a look at PaymentConfig.swift**
        
        
        /// ** INITIALIZE the QuantumPay SDK
        /// If you dont use the payment device outside of QuantumPay for barcode scanning, this call is needed here to set tenantKey prior to using the PaymentEngine.
        /// This project setup as a mix of Objective C and Swift. And there is a separate flow to only do scanning without the use of Quantum pay, until needed later on.
        /// So this method is currently called in ViewController
        
        //let tenant = Tenant(hostKey: PaymentConfig.hostKey, tenantKey: PaymentConfig.tenantKey)
        //InfinitePeripherals.initialize(developerKey: PaymentConfig.developerKey, tenant: tenant)
        
        
        /// ** A PAYMENT TRANSACTION FLOW
        /// 1. Create PaymentEngine and connect to payment device.
        /// 2. Setup callbacks to see transaction progress
        /// 3. Create Invoice (optional on EVO, required on FreedomPay)
        /// 4. Create Transaction with the Invoice created
        /// 5. Start Transaction
        
        
        /// Error and exception should be handled appropriately
        /// ********************************
        
        var idleTimeout: TimeInterval = 0
        var disconnectTimeout: TimeInterval = 0
        do {
            try IPCDTDevices.sharedDevice().getAutoOff(whenIdle: &idleTimeout, whenDisconnected: &disconnectTimeout)
            print("Idle timeout: \(idleTimeout)")
            print("Disconnect: \(disconnectTimeout)")
        }
        catch {
            print(error)
        }
    }
    
    /// Example on capturing the BLE payment device using camera
    @IBAction func actionCaptureSerial(sender: UIButton) {
        do {
            try InfinitePeripherals.captureDeviceSerial { serial in
                // Set payment device
                self.paymentDevice = QPR250(serial: serial)
                // Then can start build the payment engine
                self.actionStartEngine(sender: sender)
            }
        }
        catch {
            print(error)
        }
    }
    
    /// Discover all the BLE payment devices around.
    @IBAction func actionDiscoverDevices(sender: UIButton) {
        InfinitePeripherals.discoverDevices { devices, error in
            if let device = devices?.first {
                // Set payment device using serial
                self.paymentDevice = QPR250(serial: device)
                // Build the payment engine.
                self.actionStartEngine(sender: sender)
            }
        }
    }
    
    /// **1: Before any interaction with the payment engine, we need to first create the PaymentEngine instance**
    /// - Note: It is important to set the **posID** with a persistent value, so the database can find offline transactions that generated by the engine on next launch.
    @IBAction func actionStartEngine(sender: UIButton) {
        
        /// ** NOTE:
        /// Currently there is only 1 PaymentEngine supported at any given time.
        
        
        do {
            /// ** If you want to generate a new PaymentEngine with different configuration, first, run:
            //PaymentEngine.builder().reset()
            /// **Then run the code below with different input.
            
            
            // Create new PaymentEngine
            try PaymentEngine.builder()
            /// The server where the payment is sent to for processing
                .server(server: .test)
            /// Specify the username and password that will be used for authentication while registering peripheral devices with the Quantum Pay server. The provided credentials must have Device Administrator permissions. Optional.
                .registrationCredentials(username: PaymentConfig.username, password: PaymentConfig.password)
            /// Add a supported peripheral for taking payment, and specify the available capabilities
            /// If you want to auto connect the payment device, set the autoConnect to true,
            /// otherwise set to false and manually call paymentEngine.connect() where approriate in your workflow.
                .addPeripheral(peripheral: self.paymentDevice!, capabilities: self.paymentDevice!.availableCapabilities, autoConnect: false)
            /// Specify the unique POS ID for identifying transactions from a particular phone or tablet. Any string value
            /// can be used, but it should be unique for the instance of the application installation. A persistent GUID is
            /// recommended if the application does not already have persistent unique identifiers for app installs.
            /// Required.
                .posID(posID: PaymentConfig.posId)
            /// Specify the Mobile.EmvApplicationSelectionStrategy to use when a presented payment card supports multiple EMV applications and the user or customer must select one of them to be able to complete the transaction. Optional.
                .emvApplicationSelectionStrategy(strategy: .defaultStrategy)
            /// Specify the time interval that the Peripheral will wait for a card to be presented when a transaction is
            /// started. Optional. The default value is 1 minute when not specified.
                .transactionTimeout(timeoutInSeconds: 30)
            /// Specify the storing and queueing mode.
            /// If you dont need offline capability, you can set this to neverQueue() and all transactions will require internet
            /// If you operate in the environment where internet might drop, then queueWhenOffline() will switch between storing transactions when there is no internet
                .queueWhenOffline(autoUploadInterval: 60)
            /// Add location to each transactions.
            /// Make sure to add the required Privacy - Locations in plist
                .assignLocationsToTransactions()
            /// When there is an exception that the SDK doesnt handle, this handler will get called
            /// The app should decide what to do in this situation. You can either restart the transaction or reupload stored transactions
                .unhandledExceptionHandler(handler: { transactions, errors, warnings in
                    // Handle the unexpected exception here.
                    // Show user a message to redo the transaction?
                    self.addText("Unhandled exception: \(errors?.first?.message ?? "No message")")
                })
            /// Builds the PaymentEngine instance with all of the specified options and the specified handler will receive the instance when completed.
                .build(handler: { (engine) in

                    // Continue set up engine in here
                    self.addText("Engine created - posID: \(PaymentConfig.posId)")
                    
                    // Save the engine for operation
                    self.pEngine = engine
                    
                    /// **2. Set up callbacks
                    self.setupCallbacks(paymentEngine: self.pEngine!)
                })
        }
        catch {
            self.addText("Payment engine error: \(error.localizedDescription)")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if self.pEngine != nil {
            PaymentEngine.builder().reset()
            return
        }
    }
    
    /// **1 (part of step 1). Manual connecting the payment device where approriate, or set autoConnect: true when addingPeripheral to PaymentEngine builder**
    @IBAction func actionConnect(sender: UIButton) {
        self.pEngine!.connect()
    }
    
    /// **2. Setup callbacks**
    func setupCallbacks(paymentEngine: PaymentEngine) {
        /// The connection state handler that will return status of the peripheral (Conneted, connecting, or disconnected)
        paymentEngine.setConnectionStateHandler(handler: { (peripheral, connectionState) in
            self.addText("Connection state: \(connectionState)")
        })
        
        /// The transaction result notify when transaction is completed. Once the transaction is completed and approved, the receipt URL will be avaiable.
        paymentEngine.setTransactionResultHandler(handler: { (transactionResult) in
            self.addText("Transaction result: \(transactionResult.status)")
            self.addText("Receipt: \(transactionResult.receipt?.customerReceiptUrl ?? "")")
            
            // This object contains the result of the transaction
            self.transactionResult = transactionResult
            
            // Check KSN
            if let ksn = transactionResult.transaction.properties.ksn {
                let ksnData = ksn.map { String(format: "%02x", $0) }.joined()
                self.addText("KSN: \(ksnData)")
            }
            
            // If you are using EVO and want to get the payment tokenization when the transaction finished:
            if let evoTokenized = transactionResult.paymentToken {
                // Process or save the token for future use
                // Please handle this token with care!
                print("EVO Tokenized: \(evoTokenized)")
            }
        })
        
        /// The state of transaction throughout the process
        paymentEngine.setTransactionStateHandler(handler: { (peripheral, transaction, transactionState) in
            self.addText("Transaction state: \(transactionState)")
            
            // The transaction object saved for receipt printing purposes.
            self.transaction = transaction
        })
        
        /// Represents the current state of the peripheral, as reported by the peripheral device itself.
        paymentEngine.setPeripheralStateHandler(handler: { (peripheral, state) in
            self.addText("Peripheral state: \(state)")
        })
        
        /// Represents a User Interface message that should be displayed within the application, as reported by the peripheral device.
        paymentEngine.setPeripheralMessageHandler(handler: { (peripheral, message) in
            self.addText("Peripheral message: \(message)")
        })
        
        /// Set a signsture handler when the transaction requires signature.
        paymentEngine.setSignatureVerificationHandler { peripheral, transaction, verification in
            
            // Present a signature capture screen here
            self.addText("Signature: Required.")
            
            // For example, we just show a popup here
            let alert = UIAlertController(title: "Signature", message: "Please sign here...", preferredStyle: .alert)
            let actionAccept = UIAlertAction(title: "Accept", style: .default) { action in
                // If we are satisfied and accept the signature
                verification.signatureAccepted()
            }
            let actionRefuse = UIAlertAction(title: "Reject", style: .default) { action in
                // If we are not satisfied with the signature and want to reject the transaction
                verification.signatureRejected()
            }
            alert.addAction(actionRefuse)
            alert.addAction(actionAccept)
            self.present(alert, animated: true, completion: nil)
        }
        
        /// Set a barcode handler when a barcode is scanned
        paymentEngine.setBarcodeHandler { peripheral, barcode in
            self.addText("Barcode: \(barcode)")
        }
    }
    
    /// **3: Create the invoice for the transaction**
    func createInvoice(amount: Decimal) -> Invoice? {
        do {
            let invoiceRef = "\(arc4random() % 99999)"
            
            let invoice = try self.pEngine!.buildInvoice(reference: invoiceRef)
            /// Specify the full Company Name that appears on the invoice. Required.
                .companyName(companyName: "ACME SUPPLIES INC.")
            /// Specify a Purchase Order reference code for this invoice. Optional.
                .purchaseOrderReference(reference: "P01234")
            /// Add a new InvoiceItem to the invoice with fluent access for specifying the invoice item details. Required.
                .addItem(productCode: "SKU1", description: "Discount Voucher for Return Visit", price: 0)
            /// Another way of creating an item
                .addItem { (itemBuilder) -> InvoiceItemBuilder in
                    return itemBuilder
                    /// Specify the product or service code or SKU for the invoice item. Required.
                        .productCode("SKU2")
                    /// Describe the product or service on the invoice item. Required.
                        .productDescription("In Store Item")
                    /// Specify the SaleCode for the product or service on the invoice item.
                    /// Optional. The default value is "Sale" when not provided.
                        .saleCode(SaleCode.S)
                    /// Specify the unit price of the invoice item in the currency of the Transaction. Required.
                        .unitPrice(amount)
                    /// Set the gross amount for the item
                        .setGrossTotal(amount)
                    /// Set the net total for the item
                    /// Gross, net, tax, discount should all be manually calculated, bc each region utilize different ways to calculate.
                        .setNetTotal(amount)
                        .setTaxTotal(0)
                        .setDiscountTotal(0)
                    /// Specify the quantity sold of the invoice item. Optional. The default value is 1 when not provided.
                        .quantity(1)
                    /// Specify the UnitOfMeasure for the quantity of the invoice item.
                    /// Optional. The default value is UnitOfMeasure.Each when not provided.
                        .unitOfMeasureCode(.Each)
                }
            /// Calculates the totals on the invoice by summarizing the invoice item totals. Optionally control whether
            /// the net, discount, tax and gross totals should be calculated.
            /// The net total will be a summary of the net totals of invoice items.
            /// The discount total will be a summary of the discount totals of invoice items.
            /// The tax total will be a summary of the tax totals of invoice items.
            /// The gross total will add together the net total and the tax total, subtracting the discount total and adding the tip amount.
            /// It is important to enter gross, net, tax, and discount to each item before calling calculateTotals().
                .calculateTotals()
            /// Builds the Invoice instance with the provided values.
                .build()
            
            return invoice
        }
        catch {
            self.addText("Error creating invoice: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// **4. Create the transaction**
    func createTransaction(invoice: Invoice) -> Transaction? {
        do {
            let transactionRef = "\(arc4random() % 99999999)"
            
            /// **4: We create the transaction which contains the invoice**
            let transaction = try self.pEngine!
                .buildTransaction(invoice: invoice)
            /// Specify that the transaction will be processed as a Sale. i.e. "Auth" and "Capture" will be performed. The "Amount" must be provided.
                .sale()
            /// Specify the total amount to be paid by the customer (or refunded to the customer) for the transaction. The
            /// amount should be in major units of the specified currency
                .amount(invoice.gross, currency: .USD)
            /// Specify the Reference code for the transaction. This should be a value that represents a unique order or
            /// invoice within the application. Optional. The default value is automatically generated when not specified.
                .reference(transactionRef)
            /// Specify the Date() that the transaction will be recorded against. This can be any
            /// valid value with any time zone, but the value in UTC time zone will be used. Optional. The default value
            /// is the current date/time in UTC when not specified.
                .dateTime(Date())
            /// Specify the Service that will process the transaction. The Service is usually a merchant account.
            /// Optional, but must be provided if the tenant has more than one service set up on Quantum Pay Cloud.
                .service(PaymentConfig.service)
            /// Specify the "Format" to be used for handling the encrypted transaction data. Do not override
            /// unless advised to do so by the Quantum Pay Customer Support.
                .secureFormat(.pinpad)
            /// Attach a dictionary to the transaction. The keys of the dictionary will be presented on the receipt and
            /// can also be used to locate the transaction on the Quantum Pay Portal.
            /// Only one meta-data object can be associated with the transaction. Optional.
                .metaData(["orderNumber" : invoice.invoiceReference, "delivered" : "true"])
            /// Build the Transaction object
                .build()
            
            return transaction
        }
        catch {
            self.addText("Error creating transaction: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// **5. Start the transaction**
    func startNewTransaction(amount: Decimal) {
        do {
            guard let invoice = self.createInvoice(amount: amount) else {return}
            guard let txn = self.createTransaction(invoice: invoice) else {return}
            self.transaction = txn
            
            self.addText("Transaction ID: \(self.transaction?.ID)")
            
            // Check queue strategy (store forward mode)
            self.addText("Queue strategy: \(self.pEngine!.queueStrategy)")
            
            // Start processing the specified transaction with provided values
            try self.pEngine!.startTransaction(transaction: txn) { (result, tResponse) in
                // ********************* Transaction Result Response **********************
                self.addText("Transaction uploaded: \(result.isUploaded) - PAN: \(result.properties.maskedPAN ?? "") - Ref: \(result.transactionReference)")
                
                guard let response = tResponse
                else {
                    return
                }
                
                // ********************** Determine transaction error ********************
                if let error = response.errors?.first {
                    // There are errors with transaction if more than 1 error object in the array
                    
                    // Check to see what kind of error it is
                    // The error.message tells us what the error is about
                    // but sometime the error.message is not clear, like "transactionError"
                    // so we need to dig deeper to see what does it mean
                    switch (error.type) {
                    case .process:
                        // Error from server/processor
                        // Get the error enum
                        if let message = error.message, let enumMessage = ApiResponseErrorProcessMessage(rawValue: message) {
                            // Use this enumMessage for flow
                        }
                                                    
                        break
                    case .exception:
                        // Error from server/processor
                        // Get the error enum
                        if let message = error.message, let enumMessage = ApiResponseErrorExceptionMessage(rawValue: message) {
                            // Use this enumMessage for flow
                        }
                        break
                    case .validation:
                        // Error from server/processor
                        // Get the error enum
                        if let message = error.message, let enumMessage = ApiResponseErrorValidationMessage(rawValue: message) {
                            // Use this enumMessage for flow
                        }
                        break
                    case .preprocessException:
                        // This error is from the app/SDK
                        // Transaction is not yet uploaded to server
                        // Read error message. The message is from the error thrown by exception from within the SDK
                        if let message = error.message {
                            print("Preprocess exception: \(message)")
                        }
                        break
                    default:
                        // Some new error type that is undefined in the SDK
                        break
                    }
                    
                    // Find out more info on this error from the responseCode returned from processor, if there is one
                    if let result = response.results?.first {
                        // Check for responseCode
                        guard let responseCode = result.responseCode else {
                            return
                        }
                        print(responseCode)
                        
                        // Convert this to enum for flow processing
                        guard let enumResponseCode = EVOTransactionResultResponseCode(rawValue: responseCode) else {
                            return
                        }
                        // The detail message for this responseCode is included in the enumResponseCode.message
                        print(enumResponseCode.message)
                        
                        // Check for responseMessage
                        // This message is the same as the enumResponseCode variable value, not the code value
                        // So it is better to read enumResponseCode.message if detail is desired.
                        guard let responseMessage = result.responseMessage else {
                            return
                        }
                        print(responseMessage)
                    }
                    else {
                        // This is likely because the transaction is not yet sent to processor, and the error is within QuantumPay server.
                    }
                }
            }
        }
        catch {
            self.addText("EMV error: \(error.localizedDescription)")
        }
    }
    
    /// You can stop an active transaction, if the card has not presented yet. Once the card is read, transaction cannot be stopped anymore
    @IBAction func actionStopTransaction(sender: UIButton) {
        do {
            try self.pEngine!.stopActiveTransaction()
        }
        catch {
            self.addText("Stop transaction: \(error.localizedDescription)")
        }
    }
    
    /// Start a transaction with a custom amount popup
    @IBAction func actionStartTransaction(sender: UIButton) {
        if self.pEngine == nil {
            return
        }
        
        // Asking for amount
        let amountAlert = UIAlertController(title: "Item Amount", message: "Please enter an amount", preferredStyle: .alert)
        let doneAction = UIAlertAction(title: "Done", style: .default) { action in
            if let field = amountAlert.textFields?[0], let amountString = field.text, let amountDecimal = Decimal(string: amountString) {
                self.startNewTransaction(amount: amountDecimal)
            }
            else {
                let errorAlert = UIAlertController(title: "Invalid Amount", message: "Please enter a different amount.", preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                self.show(errorAlert, sender: nil)
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        amountAlert.addTextField { field in
            field.keyboardType = .numbersAndPunctuation
        }
        amountAlert.addAction(cancelAction)
        amountAlert.addAction(doneAction)
        self.show(amountAlert, sender: nil)
    }
    
    /// **Retrieve transactions stored in DB. If queueWhenOffline is used, there might be transactions saved in DB when there was bad network. Be sure to check and upload any saved transactions at the end of the day**
    @IBAction func actionCheckDatabaseTransactions(sender: UIButton) {
        try? self.pEngine?.getStoredTransactions(onLoadedStoredTransactions: { results in
            if let results = results {
                for result in results {
                    self.addText("Stored transaction: \(result.ID) - Ref: \(result.transactionReference)")
                }
            }
            else {
                self.addText("No trannsaction found in DB!")
            }
        })
    }
    
    /// **Manually upload stored transactions in DB**
    @IBAction func actionUploadStoredTransaction(sender: UIButton) {
        do {
            try self.pEngine?.uploadAllStoredTransactions(callback: { (transactionResults, errors) in
                self.addText("actionUploadStoredTransaction: \(transactionResults?.count ?? 0)")
                if let transactionResults = transactionResults, transactionResults.count > 0    {
                    for transaction in transactionResults {
                        self.addText("Uploaded: \(transaction.isUploaded) - Ref: \(transaction.transactionReference) - ID: \(transaction.ID)")
                    }
                }
                else {
                    self.addText("No transactions to upload!")
                }
            })
        }
        catch {
            self.addText("Error uploading all transactions: \(error.localizedDescription)")
        }
    }
    
    // Helper to add text on screen
    func addText(_ text: String) {
        // Also log to console
        print(text)
        
        // Add to screen
        DispatchQueue.main.async {
            self.outputTextView.text = "\(text)\n" + self.outputTextView.text
        }
    }
    
    /* ******************** RECEIPT ******************
     The transaction info is stored in the self.transaction object.
     You can use it to generate the receipt info.
     *********************************************** */

    func generateReceipt() -> String? {
        var receipt = ""
        
        // If we have a valid Transaction object, we can generate a receipt
        if let transaction = self.transaction {
            receipt += self.addToReceipt(self.textLine(center:transaction.invoice!.companyName!))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt("_______________________________")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(center: "SALE"))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(left: "Merchant", right: PaymentConfig.service))
            receipt += self.addToReceipt(self.textLine(left: String(describing: transaction.properties.scheme).uppercased(), right: transaction.properties.maskedPAN!))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(center: String(describing: self.transactionResult!.status).uppercased()))
            receipt += self.addToReceipt(self.textLine(left: "Date", right: "\(transaction.transactionDateTime)"))
            receipt += self.addToReceipt(self.textLine(left: "Order #", right: "\(transaction.transactionReference)"))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(left: "Total", right: "\(transaction.transactionAmount) \(transaction.currency.code)"))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(center: "I agree to pay the above total amount according to card issuer agreement."))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt("_______________________________")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(center: "Customer Signature"))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(self.textLine(center: "Thank You"))
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            receipt += self.addToReceipt(" ")
            
            return receipt
        }
        
        return nil
    }
    
    // Helpers
    func addToReceipt(_ text: String) -> String {
        return "\(text)\n"
    }
    
    func textLine(center: String) -> String {
        return "\(center)"
    }
    
    func textLine(left: String, right: String) -> String {
        // Total chars has to be 32
        if left.count + right.count > 32 {
            return ""
        }
        
        let spaces = String(repeating: " ", count: 32 - left.count - right.count)
        let printLine = "\(left)\(spaces)\(right)"
        return printLine
    }
    
    @IBAction func actionShowReceipt() {
        let receiptVC = UIViewController()
        receiptVC.view.backgroundColor = UIColor.white
        
        let receiptLabel = UILabel(frame: CGRect(x: 0, y: 0, width: receiptVC.view.frame.size.width, height: receiptVC.view.frame.size.height))
        receiptLabel.textAlignment = .center
        receiptLabel.numberOfLines = 0
        receiptVC.view.addSubview(receiptLabel)
        
        receiptLabel.text = self.generateReceipt()
        
        self.show(receiptVC, sender: self)
    }
}