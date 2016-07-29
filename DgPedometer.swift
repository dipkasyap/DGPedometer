//
//  DgPedometerVC.swift
//  CoreMotnEg
//
//  Created by dip on 7/29/16.
//  Copyright © 2016 dip. All rights reserved.
//

import UIKit
import CoreMotion
extension Double {
    func roundTo(precision: Int) -> Double {
        let divisor = pow(10.0, Double(precision))
        return round(self * divisor) / divisor
    }
}

/*
	Raw Accelerometer Data = effects of gravity + effects of device motion
	Applying a low-pass filter to the raw accelerometer data in order to keep only
	the gravity component of the accelerometer data.
	If it was a high-pass filter, we would've kept the device motion component.
	SOURCES
 http://litech.diandian.com/post/2012-10-12/40040708346
 https://gist.github.com/kristopherjohnson/0b0442c9b261f44cf19a
 */
extension Double {
    func lowPassFilter(filterFactor: Double, previousValue: Double) -> Double {
        return (previousValue * filterFactor/100) + (self * (1 - filterFactor/100))
    }
}
enum DgPedometerStatus {
    case Stopped
    case Run
}

protocol DgPedometerDelegate {
    func pedometerStatus(didChangedTo status:DgPedometerStatus)
}

class DgPedometer: NSObject {
    
    let motionManager = CMMotionManager()
    let accelerometerUpdateInterval = 0.1

    var firstAccelerometerData = true// indicates the first time accelerometer data received. about
   
    // low-pass filtering
    var previousXValue: Double!
    var previousYValue: Double!
    var previousZValue: Double!
    
    var xAcceleration: Double!
    var yAcceleration: Double!
    var zAcceleration: Double!
    
    var filteredXAcceleration: Double = 0.0
    var filteredYAcceleration: Double = 0.0
    var filteredZAcceleration: Double = 0.0

    let roundingPrecision = 3
    var accelerometerDataInEuclideanNorm: Double = 0.0
    var accelerometerDataCount: Double = 0.0
    var accelerometerDataInASecond = [Double]()
    var totalAcceleration: Double = 0.0
    var lowPassFilterPercentage = 35.0
    var shouldApplyFilter = true
    
    var staticThreshold = 0.013								// 0.008 g^2
    let slowWalkingThreshold = 0.05							// 0.05 g^2
    
    var pedestrianStatus: String!

    var delegate:DgPedometerDelegate?
    
    override init(){
        super.init()
    }
    
    func start() {

        motionManager.accelerometerUpdateInterval = accelerometerUpdateInterval
        // Initiate accelerometer updates
        motionManager.startAccelerometerUpdatesToQueue(NSOperationQueue.mainQueue()) { (accelerometerData: CMAccelerometerData?, error: NSError?) -> Void in
            if((error) != nil) {
                print(error)
            } else {
                self.estimatePedestrianStatus((accelerometerData?.acceleration)!)
            }
        }
    }

    func estimatePedestrianStatus(acceleration: CMAcceleration) {
        // If it's the first time accelerometer data obtained,
        // get old values as zero since there was no data before.
        // Otherwise get the previous value from the cycle before.
        // This is done for the purpose of the low-pass filter.
        // It requires the previous cycle data.
        
        if firstAccelerometerData {
            previousXValue = 0.0
            previousYValue = 0.0
            previousZValue = 0.0
            
            firstAccelerometerData = false
        } else {
            previousXValue = filteredXAcceleration
            previousYValue = filteredYAcceleration
            previousZValue = filteredZAcceleration
        }
        
        // Retrieve the raw x-axis value and apply low-pass filter on it
        xAcceleration = acceleration.x.roundTo(roundingPrecision)
        filteredXAcceleration = xAcceleration.lowPassFilter(lowPassFilterPercentage, previousValue: previousXValue).roundTo(roundingPrecision)
       
        // Retrieve the raw y-axis value and apply low-pass filter on it
        yAcceleration = acceleration.y.roundTo(roundingPrecision)
        filteredYAcceleration = yAcceleration.lowPassFilter(lowPassFilterPercentage, previousValue: previousYValue).roundTo(roundingPrecision)
        
        // Retrieve the raw z-axis value and apply low-pass filter on it
        zAcceleration = acceleration.z.roundTo(roundingPrecision)
        filteredZAcceleration = zAcceleration.lowPassFilter(lowPassFilterPercentage, previousValue: previousZValue).roundTo(roundingPrecision)
        
        // EUCLIDEAN NORM CALCULATION
        // Take the squares to the low-pass filtered x-y-z axis values
        let xAccelerationSquared = (filteredXAcceleration * filteredXAcceleration).roundTo(roundingPrecision)
        let yAccelerationSquared = (filteredYAcceleration * filteredYAcceleration).roundTo(roundingPrecision)
        let zAccelerationSquared = (filteredZAcceleration * filteredZAcceleration).roundTo(roundingPrecision)
        
        // Calculate the Euclidean Norm of the x-y-z axis values
        accelerometerDataInEuclideanNorm = sqrt(xAccelerationSquared + yAccelerationSquared + zAccelerationSquared)
        
        // Significant figure setting for the Euclidean Norm
        accelerometerDataInEuclideanNorm = accelerometerDataInEuclideanNorm.roundTo(roundingPrecision)
        
        // EUCLIDEAN NORM VARIANCE CALCULATION
        // record 10 values
        // meaning values in a second
        // accUpdateInterval(0.1s) * 10 = 1s
        while accelerometerDataCount < 1 {
            accelerometerDataCount += 0.1
            
            accelerometerDataInASecond.append(accelerometerDataInEuclideanNorm)
            totalAcceleration += accelerometerDataInEuclideanNorm
            
            break	// required since we want to obtain data every acc cycle
            // otherwise goes to infinity
        }
        
        // when accelerometer values are recorded
        // interpret them
        if accelerometerDataCount >= 1 {
            accelerometerDataCount = 0	// reset for the next round
            
            // Calculating the variance of the Euclidian Norm of the accelerometer data
            let accelerationMean = (totalAcceleration / 10).roundTo(roundingPrecision)
            var total: Double = 0.0
            
            for data in accelerometerDataInASecond {
                total += ((data-accelerationMean) * (data-accelerationMean)).roundTo(roundingPrecision)
            }
            
            total = total.roundTo(roundingPrecision)
            
            let result = (total / 10).roundTo(roundingPrecision)
            
            if (result < staticThreshold) {
                pedestrianStatus = "STOPPED"

                self.delegate?.pedometerStatus(didChangedTo: .Stopped)
            } else if ((staticThreshold <= result) && (result <= slowWalkingThreshold)) {
                
                pedestrianStatus = "Slow Walking"
                self.delegate?.pedometerStatus(didChangedTo: .Run)
                
            } else if (slowWalkingThreshold < result) {
                pedestrianStatus = "Fast Walking"
                self.delegate?.pedometerStatus(didChangedTo: .Run)
            }
            
            print("Pedestrian Status: \(pedestrianStatus)\n\n\n")
            
            // reset for the next round
            accelerometerDataInASecond = []
            totalAcceleration = 0.0
        }
    }
}
