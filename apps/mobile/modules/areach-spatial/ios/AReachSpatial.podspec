Pod::Spec.new do |s|
  s.name           = 'AReachSpatial'
  s.version        = '1.0.0'
  s.summary        = 'Native spatial runtime for AReach'
  s.description    = 'AR camera preview, body pose detection, and nearby peer discovery for AReach.'
  s.author         = 'AReach'
  s.homepage       = 'https://github.com/pedro-miguel-rosa/areach-source'
  s.platforms      = {
    :ios => '15.1'
  }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.frameworks = 'ActivityKit', 'ARKit', 'CoreBluetooth', 'CryptoKit', 'NearbyInteraction', 'Network', 'RealityKit', 'Security', 'Vision'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
