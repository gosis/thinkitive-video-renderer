//
//  LottieOverlayView.swift
//  LottieVideoDemo
//
//  Created by Gints Osis on 21/06/2023.
//

import UIKit
import Lottie
import dotLottie
import thinkitive_video_renderer

class LottieOverlayView: UIView  {
    
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
}

extension LottieOverlayView: OverlayRenderable {
    
    func updateTime(percentage: CGFloat) {
        
        guard let animationView = self.animationView else { return }
        
        animationView.currentProgress = percentage
        
        // In case the percentage is 0 we have to explicitly hide the animationView
        // Otherwise is remains visible in stopped state
        animationView.isHidden = (percentage == 0)
    }
}
