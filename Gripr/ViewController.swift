//
//  ViewController.swift
//  Gripr
//
//  Created by Matt Gaidica on 11/7/22.
//
import Charts
import UIKit
import CoreBluetooth
import Accelerate

class ViewController: UIViewController, ChartViewDelegate, UITextFieldDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

    @IBOutlet weak var lineChart: LineChartView!
    @IBOutlet weak var timeTextView: UITextView!
    @IBOutlet weak var maxLoadTextView: UITextView!
    @IBOutlet weak var statsTextView: UITextView!
    @IBOutlet weak var copyLogLabel: UILabel!
    @IBOutlet weak var threshSlider: UISlider!
    @IBOutlet weak var threshSliderLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var loadValDisplayLabel: UILabel!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var dataLogView: UIView!
    @IBOutlet weak var rssiLabel: UILabel!
    @IBOutlet weak var connectedButton: UIButton!
    @IBOutlet weak var smoothSwitch: UISwitch!
    
    // BLE
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    var timeoutConnTimer = Timer()
    var timeOutSec: Double = 60*2
    private var loadChar: CBCharacteristic?
    var RSSITimer = Timer()
    var griprRSSI: NSNumber = 0
    
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
    let pasteboard = UIPasteboard.general
    
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
        }
    }
    
    func scanBLE() {
        connectedButton.setTitle("Searching...", for: .normal)
        centralManager.scanForPeripherals(withServices: [GriprPeripheral.GriprServiceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
        timeoutConnTimer = Timer.scheduledTimer(withTimeInterval: timeOutSec, repeats: false) { timer in
            self.cancelScan()
        }
    }
    
    // Handles the result of the scan
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Found peripheral, connecting...")
        // We've found it so stop scan
        self.centralManager.stopScan()
        // Copy the peripheral instance
        self.peripheral = peripheral
        self.peripheral.delegate = self
        self.centralManager.connect(self.peripheral, options: nil)
        self.griprRSSI = RSSI
    }
    
    func cancelScan() {
        centralManager?.stopScan()
        connectedButton.setTitle("BLE Timeout", for: .normal)
    }
    
    func delegateRSSI() {
        if self.peripheral != nil {
            self.peripheral.delegate = self
            self.peripheral.readRSSI()
        }
    }
    
    func updateRSSI(RSSI: NSNumber!) {
        rssiLabel.textColor = UIColor.white
        let str : String = RSSI.stringValue
        rssiLabel.text = str + "dB"
    }
    
    func startReadRSSI() {
        self.RSSITimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            self.delegateRSSI()
        }
    }
    
    func stopReadRSSI() {
        self.RSSITimer.invalidate()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        updateRSSI(RSSI: RSSI)
    }
    
    // The handler if we do connect succesfully
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == self.peripheral {
            timeoutConnTimer.invalidate()
            updateRSSI(RSSI: griprRSSI)
            self.startReadRSSI()
            connectedButton.setTitle(peripheral.name, for: .normal)
            peripheral.discoverServices([GriprPeripheral.GriprServiceUUID])
            startButton.isEnabled = true
            stopButton.isEnabled = false
            resetButton.isEnabled = true
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
            updateChart()
            checkThreshold()
        }
    }
    
    // disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == self.peripheral {
            stopReadRSSI()
            rssiLabel.text = ""
            connectedButton.setTitle("Not Connected", for: .normal)
            self.peripheral = nil
            loadChar = nil
            threshActive = false
            maxLoadVal = 0
            startButton.isEnabled = false
            stopButton.isEnabled = false
            resetButton.isEnabled = false
            dataLogView.alpha = 0.7
//            scanBLE() // auto scan
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
    
    @IBAction func connectedButtonTouch(_ sender: Any) {
        if peripheral != nil {
            centralManager?.cancelPeripheralConnection(peripheral)
        } else {
            scanBLE()
        }
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
        var logStr = ""
        let loadComponents = maxLoadTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let timeComponents = timeTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        
        for i in 0..<timeComponents.count {
            logStr += timeComponents[i].replacingOccurrences(of: " ", with: ",") + "," + loadComponents[i] + "\n"
        }
        pasteboard.string = logStr
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
        dateFormatter.dateFormat = "HH:mm:ss YYYYmmdd"
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
        loadValDisplayLabel.text = ""
        maxLoadVal = 0
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
        let maxComponents = min(maxLoadLog, loadComponents.count)
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
            dataLogView.alpha = 1
            let lastLoadVal = loadChartData[loadChartData.count-1]
            loadValDisplayLabel.text = String(maxLoadVal)
            if threshActive {
                if lastLoadVal > maxLoadVal {
                    maxLoadVal = lastLoadVal
                }
                if lastLoadVal < 40 { //Int(threshSlider.value) { // turn OFF
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
            dataLogView.alpha = 0.7
            loadValDisplayLabel.text = ""
            threshActive = false // force off
        }
    }
    
    func updateChart() {
        data = LineChartData()
        lineChartEntry = [ChartDataEntry]()
        if smoothSwitch.isOn {
            var doubleData = loadChartData.map { Double($0) }
            let nSmooth = 5
            for i in 0..<doubleData.count {
                var miniSum: Double = 0
                var nelem: Double = 0
                for j in 0..<min(nSmooth, i + 1, doubleData.count - i) {
                    miniSum += doubleData[i + j]
                    nelem += 1
                }
                doubleData[i] = miniSum / nelem
            }
            
            // for moving avg: nSMooth..<doubleData.count - nSmooth
            for i in 0..<doubleData.count {
                let value = ChartDataEntry(x: Double(i), y: doubleData[i])
                lineChartEntry.append(value)
            }
        } else {
            for i in 0..<loadChartData.count {
                let value = ChartDataEntry(x: Double(i), y: Double(loadChartData[i]))
                lineChartEntry.append(value)
            }
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

