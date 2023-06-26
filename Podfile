# Uncomment the next line to define a global platform for your project
platform :ios, '11.0'

target 'thinkitive-video-renderer' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for thinkitive-video-renderer
  	pod 'lottie-ios'
	pod 'dotLottie'

  target 'thinkitive-video-rendererTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'thinkitive-video-rendererUITests' do
    # Pods for testing
  end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
    end
  end
end
end