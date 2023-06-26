//
//  LottieOverlayView.swift
//  LottieVideoDemo
//
//  Created by Gints Osis on 21/06/2023.
//

import UIKit
import Lottie
import dotLottie

class LottieOverlayView: UIView {
    
    private var animationView:AnimationView?
    
    
    /// Initializer with given lottie file name with no extension
    /// - Parameters:
    ///   - frame: frame in which to display the  Overlay initially
    ///   - lottieIdentifier: string identifier to a lottie animation without extension, either .json or .lottie
    init(frame:CGRect,
         lottieIdentifier: String) {
        
        super.init(frame: frame)
        
        // Initialize AnimationView from lottie which will hold the animation UIView
        let animationView = AnimationView()
        
        // Load the animation for given identifier
        DotLottie.load(name: lottieIdentifier) { animation, file in
            
            guard let animation = animation else {
                assertionFailure("Error loading .lottie")
                return
            }
            
            animationView.isUserInteractionEnabled = false
            animationView.animation = animation
            animationView.loopMode = .loop
            animationView.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height)
            self.addSubview(animationView)
            self.animationView = animationView
        }
        
        self.backgroundColor = UIColor.clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    /// Updates the lottie animation to specified time in percentages
    /// - Parameter percentage: percentage from 0.0 to 1.0
    public func updateTime(percentage: CGFloat) {
        
        guard let animationView = self.animationView else { return }
        
        animationView.currentProgress = percentage
        
        // In case the percentage is 0 we have to explicitly hide the animationView
        // Otherwise is remains visible in stopped state
        animationView.isHidden = (percentage == 0)
    }
}

extension LottieOverlayView {
    
    public func rectInSize(size:CGSize) -> CGRect {
        
        guard let superView = self.superview else {
            
            return CGRect.zero
        }
        
        let myRect = self.frame
        let superViewFrame = superView.frame
        
        let widthScaleFactor = size.width / superView.frame.size.width
        let heightScaleFactor = size.height / superView.frame.size.height
        
        let averageScaleFactor = (widthScaleFactor + heightScaleFactor) / 2
                
        let newOriginX = myRect.origin.x / superViewFrame.size.width * size.width
        let newOriginY = myRect.origin.y / superViewFrame.size.height * size.height
        let newWidth = myRect.size.width * averageScaleFactor
        let newHeight = myRect.size.height * averageScaleFactor
        
        return CGRect(x: newOriginX,
                      y: newOriginY,
                      width: newWidth,
                      height: newHeight)
    }
    
    public func prepareToRenderInRect(rect:CGRect) {
        self.frame = rect
        self.layoutIfNeeded()
    }
}
