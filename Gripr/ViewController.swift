//
//  ViewController.swift
//  Gripr
//
//  Created by Matt Gaidica on 11/7/22.
//
import Charts
import UIKit
import CoreBluetooth

class ViewController: UIViewController, ChartViewDelegate, UITextFieldDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    @IBOutlet weak var lineChart: LineChartView!
    @IBOutlet weak var timeTextView: UITextView!
    @IBOutlet weak var maxLoadTextView: UITextView!
    @IBOutlet weak var statsTextView: UITextView!
    @IBOutlet weak var copyLogLabel: UILabel!
    @IBOutlet weak var threshSlider: UISlider!
    @IBOutlet weak var threshSliderLabel: UILabel!
    @IBOutlet weak var connectedLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var loadValDisplayLabel: UILabel!
    
    // BLE
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    var timeoutConnTimer = Timer()
    var timeOutSec: Double = 60*2
    private var loadChar: CBCharacteristic?
    
    // Graph Vars
    var data = LineChartData()
    var lineChartEntry = [ChartDataEntry]()
    let textColor = UIColor.white
    // line colors, see: http://0xrgb.com/#material
    let color1 = UIColor(red: 255/255, green: 87/255, blue: 34/255, alpha: 1) // deep orange
    let color2 = UIColor(red: 205/255, green: 220/255, blue: 57/255, alpha: 1) // lime
    let colorThresh = UIColor(red: 255/255, green: 0, blue: 0, alpha: 0.25) // lime
    
    // Data vars
    var loadBuffer: Array<Int32> = Array(repeating: 0, count: 32)
    var loadChartData: Array<Int32> = Array(repeating: 0, count: 128)
    var loadThreshData: Array<Int32> = Array(repeating: 0, count: 128)
    var threshActive: Bool = false
    var maxLoadVal: Int32 = 0
    let maxLoadLog: Int = 10
    
    override func viewDidLoad() {
        super.viewDidLoad()
        timeTextView.backgroundColor = UIColor.white
        maxLoadTextView.backgroundColor = UIColor.white
        statsTextView.backgroundColor = UIColor.white
        lineChart.delegate = self
        lineChart.data = nil
        updateChart()
        
        //Looks for single or multiple taps.
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIInputViewController.dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // If we're powered on, start scanning
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanBLE()
            connectedLabel.text = "Searching..."
        }
    }
    
    func scanBLE() {
        centralManager.scanForPeripherals(withServices: [GriprPeripheral.GriprServiceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
//        timeoutConnTimer = Timer.scheduledTimer(withTimeInterval: timeOutSec, repeats: false) { timer in
//            self.cancelScan()
//        }
    }
    
    // Handles the result of the scan
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Found peripheral, connectig...")
        // We've found it so stop scan
        self.centralManager.stopScan()
        // Copy the peripheral instance
        self.peripheral = peripheral
        self.peripheral.delegate = self
        self.centralManager.connect(self.peripheral, options: nil)
    }
    
//    func cancelScan() {
//        centralManager?.stopScan()
//        connectedLabel.text = "Scan Timeout"
//    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
//        updateRSSI(RSSI: RSSI)
    }
    
    // The handler if we do connect succesfully
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == self.peripheral {
//            timeoutConnTimer.invalidate()
            connectedLabel.text = peripheral.name
            peripheral.discoverServices([GriprPeripheral.GriprServiceUUID])
        }
    }
    
    // discovery event
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == GriprPeripheral.GriprServiceUUID {
                    peripheral.discoverCharacteristics([GriprPeripheral.LoadCharacteristicUUID], for: service)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == GriprPeripheral.LoadCharacteristicUUID {
                    loadChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    // attempt made to notify
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("Enabling notify ", characteristic.uuid)
        if error != nil {
            print("Enable notify error")
        }
    }
    
    // notification recieved
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if characteristic == loadChar {
            let charData:Data = characteristic.value!
            loadChartData.rotateLeft(positions: 1)
            
            let _ = charData.withUnsafeBytes { pointer in
                let dataPoint = pointer.load(fromByteOffset: 0, as: Int32.self)
                loadChartData[loadChartData.count - 1] = dataPoint
            }
            
            // below is for sending bigger data streams
//            EEG2Plot.replaceSubrange(0..<EEG2Data.count, with: EEG2Data)
//            EEG2Plot.rotateLeft(positions: EEG2Data.count)
//            let _ = data.withUnsafeBytes { pointer in
//                for n in 0..<loadBuffer.count {
//                    let dataPoint = pointer.load(fromByteOffset:n*4, as: Int32.self)
//                    loadBuffer[n] = dataPoint
//                }
//            }
            updateChart()
            checkThreshold()
        }
    }
    
    // disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == self.peripheral {
//            stopReadRSSI()
            connectedLabel.text = "Not Connected"
            self.peripheral = nil
            loadChar = nil
            threshActive = false
            maxLoadVal = 0
            scanBLE()
        }
    }
    
    //Restores Central Manager delegate if something went wrong
    func restoreCentralManager() {
        centralManager?.delegate = self
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if error != nil {
            return
        }
        print("Write characteristic success")
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    //Calls this function when the tap is recognized.
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @IBAction func copyLog(_ sender: Any) {
        copyLogLabel.textColor = UIColor.black
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            self.copyLogLabel.textColor = UIColor.white
        }
    }
    
    @IBAction func threshChanged(_ sender: Any) {
        let inc = Int(50)
        let sliderVal = Int(threshSlider.value) / inc
        threshSliderLabel.text = String(sliderVal * inc) + "g"
        threshSlider.value = Float(sliderVal * inc)
    }
    
    func getTimeStr() -> String {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss (d MMM YY)"
        return dateFormatter.string(from: date)
    }
    
    @IBAction func startButtonTouch(_ sender: Any) {
        if startButton.isEnabled {
            startButton.isEnabled = false
            stopButton.isEnabled = true
        }
    }
    @IBAction func stopButtonTouch(_ sender: Any) {
        if stopButton.isEnabled {
            stopButton.isEnabled = false
            startButton.isEnabled = true
        }
    }
    
    @IBAction func resetButtonTouch(_ sender: Any) {
        timeTextView.text = ""
        maxLoadTextView.text = ""
        statsTextView.text = ""
    }
    
    func reportMaxLoad() {
        // update textfields, they serve as a database
        if maxLoadTextView.text == "" {
            maxLoadTextView.text = String(maxLoadVal)
            timeTextView.text = getTimeStr()
        } else {
            maxLoadTextView.text = String(maxLoadVal) + "\n" + maxLoadTextView.text
            timeTextView.text = getTimeStr() + "\n" + timeTextView.text
        }
        
        let loadComponents = maxLoadTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let timeComponents = timeTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var maxComponents = min(maxLoadLog, loadComponents.count)
        var maxLoadStr = ""
        var timeStr = ""

        var maxLoadStd: Double = 0
        var sumVals: Double = 0
        for i in 0..<maxComponents {
            timeStr += timeComponents[i] + "\n"
            maxLoadStr += loadComponents[i] + "\n"
            sumVals += Double(loadComponents[i])!
        }
        let maxLoadMean = sumVals / Double(maxComponents)
        if maxComponents > 1 { // do standard deviation
            sumVals = 0;
            for i in 0..<maxComponents {
                sumVals += pow(Double(loadComponents[i])! - maxLoadMean,2)
            }
            maxLoadStd = sqrt(sumVals / Double(maxComponents - 1))
        }
        
        timeTextView.text = timeStr
        maxLoadTextView.text = maxLoadStr
        statsTextView.text = String(format: "%1.0f", maxLoadMean) + " ± " + String(format: "%1.1f", maxLoadStd) + " (n = " + String(maxComponents) + ")"
    }
    
    func checkThreshold() {
        if stopButton.isEnabled {
            let lastLoadVal = loadChartData[loadChartData.count-1]
            loadValDisplayLabel.text = String(maxLoadVal)
            if threshActive {
                if lastLoadVal > maxLoadVal {
                    maxLoadVal = lastLoadVal
                }
                if lastLoadVal < Int(threshSlider.value) { // turn OFF
                    threshActive = false
                    reportMaxLoad()
                }
            } else {
                loadValDisplayLabel.text = String(maxLoadVal)
                if lastLoadVal > Int(threshSlider.value) { // turn ON
                    threshActive = true
                    maxLoadVal = lastLoadVal
                }
            }
        } else {
            loadValDisplayLabel.text = ""
            threshActive = false // force off
        }
    }
    
    func updateChart() {
        data = LineChartData()
        lineChartEntry = [ChartDataEntry]()
        for i in 0..<loadChartData.count {
            let value = ChartDataEntry(x: Double(i), y: Double(loadChartData[i]))
            lineChartEntry.append(value)
        }
        let line1 = LineChartDataSet(entries: lineChartEntry, label: "Load (g)")
        line1.colors = [color2]
        line1.drawCirclesEnabled = false
        line1.drawValuesEnabled = false
        data.addDataSet(line1)
        
        loadThreshData = Array(repeating: Int32(threshSlider.value), count: loadThreshData.count)
        lineChartEntry = [ChartDataEntry]()
        for i in 0..<loadThreshData.count {
            let value = ChartDataEntry(x: Double(i), y: Double(loadThreshData[i]))
            lineChartEntry.append(value)
        }
        let line2 = LineChartDataSet(entries: lineChartEntry, label: "thresh")
        line2.colors = [colorThresh]
        line2.drawCirclesEnabled = false
        line2.drawValuesEnabled = false
        data.addDataSet(line2)
        
        let l = lineChart.legend
        l.form = .line
        l.font = UIFont(name: "HelveticaNeue-Light", size: 11)!
        l.textColor = textColor
        l.horizontalAlignment = .left
        l.verticalAlignment = .bottom
        l.orientation = .horizontal
        l.drawInside = false
        
        let xAxis = lineChart.xAxis
        xAxis.labelFont = .systemFont(ofSize: 11)
        xAxis.labelTextColor = textColor
        xAxis.drawAxisLineEnabled = true
        
        let leftAxis = lineChart.leftAxis
        leftAxis.labelTextColor = textColor
        leftAxis.drawGridLinesEnabled = true
        leftAxis.granularityEnabled = false
        if threshSlider.value > 0 {
            leftAxis.axisMinimum = -Double(threshSlider.value / 10.0)
            leftAxis.axisMaximum = Double(threshSlider.value * 5.0)
        } else {
            leftAxis.axisMinimum = 500
            leftAxis.axisMaximum = -50
        }

        lineChart.rightAxis.enabled = false
        lineChart.legend.enabled = true
        
        lineChart.chartDescription?.enabled = false
        lineChart.dragEnabled = false
        lineChart.setScaleEnabled(false)
        lineChart.pinchZoomEnabled = false
        lineChart.data = data // add and update
    }

}

