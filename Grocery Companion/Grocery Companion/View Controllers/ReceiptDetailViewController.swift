//
//  ReceiptDetailViewController.swift
//  Grocery Companion
//
//  Created by Andrew Dhan on 10/31/18.
//  Copyright © 2018 Andrew Dhan. All rights reserved.
//

import UIKit
import Vision

private var baseURL = URL(string: "https://vision.googleapis.com/v1/images:annotate")!

class ReceiptDetailViewController: UIViewController, CameraPreviewViewControllerDelegate, UITableViewDataSource,  UITableViewDelegate, UITextFieldDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
        
        //set textfieldDelegates
        storeTextField.delegate = self
        totalTextField.delegate = self
        dateTextField.delegate = self
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        transactionID = UUID()
        transactionController.clearLoadedItems()
    }

    //MARK: - CameraPreviewViewControllerDelegate method
    func didFinishProcessingImage(image: UIImage) {
        //test
        let testImage = UIImage(named: "test-receipt")!
        //
       
        sendCloudVisionRequest(image: image) { (results, error) in
            if let error = error {
                NSLog("Error with cloud vision:\(error)")
                return
            }
            guard let results = results else {
                NSLog("Results were nil")
                return
            }
            self.detectedLines = self.buildLines(with: results)
        }
    }
    

    //MARK: - IBActions

    
    //TODO: change for auto population of nearby stores
    //TODO: present alert if receipt header fields are not filled
    @IBAction func addItem(_ sender: Any) {

        guard let store = self.store,
            let dateString = dateTextField.text,
            let newItemName = addItemNameField.text,
            let newItemCostString = addItemCostField.text,
            let newItemCost = Double(newItemCostString),
            let date = dateString.toDate(withFormat: .short),
            let transactionID = transactionID else {return}
        
        transactionController.loadItems(name: newItemName, cost: newItemCost, store: store, date: date, transactionID: transactionID)
        addItemCostField.text = ""
        addItemNameField.text = ""
        tableView.reloadData()
    }
    
    //Submits receipt by creating transaction model given that header info are filled out
    @IBAction func submitReceipt(_ sender: Any) {
        guard let store = self.store,
            let dateString = dateTextField.text,
            let totalString = totalTextField.text,
            let total = Double(totalString),
            let date = dateString.toDate(withFormat: .short),
            let transactionID = transactionID else {return}
        
        transactionController.create(store: store, date: date, total: total, identifier: transactionID)
        
        let alertController = UIAlertController(title: "Success", message: "Your receipt has been successfully submitted", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (_) in
            self.clearViewText()
            self.transactionID = UUID()
        }
        
        alertController.addAction(okAction)
        present(alertController,animated: true, completion: nil)
    }
    
    //MARK: - UITableViewDelegate MEthods
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactionController.loadedItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ReceiptItemCell", for: indexPath) as! ReceiptItemTableViewCell
        cell.transactionID = transactionID
        cell.groceryItem = transactionController.loadedItems[indexPath.row]
        
        return cell
    }
    
    //MARK: - UITextFieldDelegate functions
    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
       
        //update store property when textField is updated
        if textField.tag == TextFieldID.store.rawValue {
            
            guard let storeText = storeTextField.text?.lowercased() else {return}
            self.store = storeText.contains("trader")
                ? StoreController.stores[StoreName.traderJoes.rawValue]
                : StoreController.stores[StoreName.wholeFoods.rawValue]
        }
    }
    
    //MARK: - Networking Functions
    
    //Sends image data to Google Cloud Vision API to perform OCR
    private func sendCloudVisionRequest(image: UIImage, completion:@escaping ([TextAnnotation]?,Error?)->Void){
        
        //Use URLComponents to add API Key to base URL
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        let authenticationItem = URLQueryItem(name: "key", value: GoogleAPIKey)
        
        urlComponents.queryItems = [authenticationItem]
        
        guard let authenticatedURL = urlComponents.url else {
            NSLog("Trouble building url")
            return
            
        }
        
        //Build URL Request
        var request = URLRequest(url: authenticatedURL)
        request.httpMethod = "POST"
        
        //although request.httpBody is optional, we want to make sure that the method did work
        guard let httpBody = buildHTTPBody(image: image) else {
            NSLog("buildHTTPBody failed")
            return
        }
        request.httpBody = httpBody
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        //Send URLRequest
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            if let error = error {
                completion(nil,error)
                return
            }
            guard let data = data else {
                completion(nil,error)
                return
            }
            //print data for testing
            print(String(data: data, encoding: String.Encoding.utf8)!)
            //decode data
            let decoder = JSONDecoder()
            do{
                let imageResponse = try decoder.decode(AnnotatedImageResponse.self, from: data)
                let textAnnotations = imageResponse.responses.first!.textAnnotations
                
                completion(textAnnotations, nil)
            } catch{
               completion(nil, error)
            }
            
            }.resume()
    }
    
    //Initializes AnnotatedImageRequest from UIImage and build Json for body of http request
    private func buildHTTPBody(image:UIImage, maxResults:Int? = nil) -> Data?{
        //convert UIImage to base64encodedstring as required for POST
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {return nil}
        let imageString = imageData.base64EncodedString(options: .endLineWithCarriageReturn)
        let contentImage = Image(content: imageString)
        
        //set feature to OCR option
        let feature = Feature(type: "DOCUMENT_TEXT_DETECTION",maxResults: 200)
        //create ocrRequest since more than one request can be sent to Cloud Vision
        let ocrRequest = Request(image: contentImage, features: [feature])
        
        //Create AnnotatedImageRequest and encode to json
        let imageRequest = AnnotatedImageRequest(requests: [ocrRequest])
        let encoder = JSONEncoder()
        do{
            let data = try encoder.encode(imageRequest)
            return data
        } catch {
            NSLog("Error encoding image to json: \(error)")
            return nil
        }
    }
    
    //MARK: - Private Methods
    private func clearViewText(){
        totalTextField.text = ""
        storeTextField.text = ""
        dateTextField.text = ""
        addItemNameField.text = ""
        addItemCostField.text = ""
        transactionController.clearLoadedItems()
        tableView.reloadData()
    }
    
    //Accepts textAnnotation decoded from AnnotatedImageResponse as a parameter and returns detected grocery items as an array of tuples
    private func buildLines(with textAnnotations: [TextAnnotation])->[(String, Double)]{
        var items = [(Int,String)]()
        var prices = [Int:String]()
        
        var line = -1
        var stringLine = ""
        
        //        let sorted = textAnnotations.sorted{$0.bottomY < $1.bottomY}
        
        for (i, annotation) in textAnnotations.enumerated(){
            //skips first annotation because it contains all text
            if i == 0 { continue }
            
            //            sets line to annotation.bottomY if not already set
            if line < 0 {
                line = annotation.bottomY
            }
            
            if isWithinRange(line: line, textAnnotation: annotation, range: 3){
                //if stringLine consists of texts then have spaces otherwise, no spaces
                let newText = annotation.text
                if stringLine.isDouble() &&
                    (newText.isDouble() || newText == "."){
                    stringLine += "\(annotation.text)"
                } else {
                    stringLine += " \(annotation.text)"
                }
                line = annotation.bottomY
            } else {
                if(stringLine.isDouble()){
                    prices[line] = stringLine
                } else {
                    items.append((line,stringLine))
                }
                stringLine = annotation.text
                line = annotation.bottomY
                continue
            }
            
        }
//      Matches items with prices and set results to detected Lines
        var result = [(String,Double)]()
        
        for value in items {
            let price = valueWithinRange(dictionary: prices, key: value.0, range: 5)
            
            if let price = price {
                result.append((value.1,Double(price)!))
                print(value.1 + " " + price)
            }
        }
        
        return result
    }
    
//    Load items from detectedLines to tableview
    private func loadItems(){
        guard let detectedLines = detectedLines,
            let store = self.store,
            let dateString = dateTextField.text,
            let date = dateString.toDate(withFormat: .short),
            let transactionID = transactionID else {return}
        for (item, price) in detectedLines{
            transactionController.loadItems(name: item, cost: price, store: store, date: date, transactionID: transactionID)
        }
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    //checks if line is within given range of textAnnotation
    //this function is valuable because texts might be have different Y values even though they are on the same line visually
    private func isWithinRange(line: Int, textAnnotation: TextAnnotation, range: Int = 2) -> Bool{
        let bottomY = textAnnotation.bottomY
        if bottomY - range < line && line < bottomY + range {
            return true
        } else {
            return false
        }
    }
    
    //Checks dictionary to see if there is a value associated with a key within a certain range
    private func valueWithinRange(dictionary: [Int: String], key: Int, range: Int = 2) -> String?{
        var result:String? = nil
        
        for i in key-range...key+range{
            result = dictionary[i]
            if result != nil {
                return result
            }
        }
        
        return result
    }
    
    //MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ScanReceipt" {
            //presents alert if store, total and date are empty otherwise proceeds to CameraPreviewVC
            if (storeTextField.text?.isEmpty ?? true ||
                totalTextField.text?.isEmpty ?? true ||
                dateTextField.text?.isEmpty ?? true){
                let alertController = UIAlertController(title: "", message: "Please enter a store name, receipt total, and receipt date to upload your receipt", preferredStyle: .alert)
                let okAction = UIAlertAction(title: "OK", style: .default) { (_) in
                    return
                }
                
                alertController.addAction(okAction)
                present(alertController,animated: true, completion: nil)
            } else {
                let destinationVC = segue.destination as! CameraPreviewViewController
                destinationVC.delegate = self
            }
        }
    }
    
    
    
    //MARK: - Properties
    private var store: Store?
    private var transactionID: UUID?
    
    private let transactionController = TransactionController.shared
    private let groceryItemController = GroceryItemController.shared
    
    @IBOutlet weak var addItemNameField: UITextField!
    @IBOutlet weak var addItemCostField: UITextField!
    
    @IBOutlet weak var totalTextField: UITextField!
    @IBOutlet weak var storeTextField: UITextField!
    @IBOutlet weak var dateTextField: UITextField!
    @IBOutlet weak var tableView: UITableView!
    
    private var detectedLines: [(String,Double)]?{
        didSet{
            loadItems()
        }
    }
}
