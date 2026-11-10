Pod::Spec.new do |s|
  s.name             = 'aria_device'
  s.version          = '0.1.0'
  s.summary          = 'Aria device bridge'
  s.homepage         = 'https://example.invalid/aria'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Aria'
  s.source           = { :path => '.' }
  s.source_files     = 'aria_device/Sources/aria_device/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
