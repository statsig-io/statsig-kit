Pod::Spec.new do |spec|

  spec.name         = "Statsig"
  spec.version      = "1.53.9"
  spec.summary      = "Statsig enables developers to ship code faster and more safely."
  spec.description  = <<-DESC
                   Statsig enables developers to ship code faster and more safely by providing:
                   - Feature gating so you can control precisely which subset of your users should see a feature,
                     and have complete control over a features' ON and OFF status remotely without code changes.
                   - Dynamic Configs so you can change the values of your button colors, font sizes, labels and etc.
                     any time you want, for a subset of users or all of them.
                   - Custom event logging so you can track how your critical metrics move with your product launches,
                     and also run A/B tests to understand whether a new feature actually helps your product before shipping.
                   DESC

  spec.homepage     = "https://github.com/statsig-io/statsig-kit"

  spec.license      = { :type => "ISC", :file => "LICENSE" }

  spec.author             = { "Jiakan Wang" => "jkw@statsig.com", "Daniel Loomb" => "daniel@statsig.com" }

  spec.ios.deployment_target = "10.0"
  spec.osx.deployment_target = "10.13"
  spec.tvos.deployment_target = "10.0"
  spec.watchos.deployment_target = "7.0"

  spec.source       = { :git => "https://github.com/statsig-io/statsig-kit.git", :tag => "#{spec.version}" }
  spec.source_files  = "Sources/Statsig/**/*.swift"
  spec.resource_bundles  = {"Statsig" => ["PrivacyInfo.xcprivacy"]}

  spec.swift_version = '5.0'

  spec.test_spec 'Tests' do |test_spec|
      test_spec.source_files = 'Tests/StatsigTests/**/*.{swift}'
      test_spec.platforms = { :ios => "10.0", :osx => "10.13", :tvos => "10.0" }
      test_spec.dependency 'Nimble'
      test_spec.dependency 'Quick'
      test_spec.dependency 'OHHTTPStubs'
      test_spec.dependency 'OHHTTPStubs/Swift'
      test_spec.dependency 'GzipSwift'
  end
end
