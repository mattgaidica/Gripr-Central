//
//  ViewController.swift
//  Gripr
//
//  Created by Matt Gaidica on 11/7/22.
//
import Charts
import UIKit
import CoreBluetooth

class ViewController: UIViewController, ChartViewDelegate {

    @IBOutlet weak var lineChart: LineChartView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        lineChart.delegate = self
//        data = LineChartData()
        lineChart.data = nil
    }

}

