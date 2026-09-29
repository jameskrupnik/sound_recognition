Pod::Spec.new do |s|
  s.name             = 'sound_recognition'
  s.version          = '0.1.0'
  s.summary          = 'On-device sound classification with one vocabulary on iOS and Android.'
  s.description      = <<-DESC
Classifies microphone audio on the device with Apple's built-in SoundAnalysis
classifier on iOS 15+, mapped to a canonical vocabulary shared with the
plugin's Android half. No model to ship and no network.
                       DESC
  s.homepage         = 'https://github.com/jameskrupnik/sound_recognition'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Illumination Development' => 'james.krupnik@illuminationdevelopment.com' }
  s.source           = { :path => '.' }
  # One source tree for both package managers: CocoaPods reads the Swift
  # Package's sources in place rather than keeping a second copy in Classes/.
  s.source_files     = 'sound_recognition/Sources/sound_recognition/**/*.swift'
  s.resource_bundles = { 'sound_recognition_privacy' => ['sound_recognition/Sources/sound_recognition/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.frameworks = 'SoundAnalysis', 'AVFoundation'

  # 13.0, not 15.0, although the classifier needs 15. A plugin's floor becomes
  # the app's floor at `pod install`, and an app that supports iOS 13 should
  # be able to add this and hide its sound mode behind `isSupported()`,
  # which answers false there, rather than be refused the dependency.
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
