Pod::Spec.new do |s|
  s.name             = 'Interlude'
  s.version          = '1.0.1'
  s.summary          = 'Token-driven HUD, progress and toast library for UIKit and SwiftUI, built with Swift 6.'
  s.description      = <<-DESC
    Interlude replaces the global show / hide HUD model with one token per task, so concurrent
    requests never dismiss each other's feedback. It ships loading, ring / bar progress, results,
    text and custom HUDs, a full toast system with stacking policies and keyboard avoidance,
    async / await helpers, SwiftUI modifiers, theming, accessibility and nine localizations.
  DESC
  s.homepage         = 'https://github.com/KahnLi-lyc/Interlude'
  s.screenshots      = 'https://raw.githubusercontent.com/KahnLi-lyc/Interlude/main/Docs/Screenshots/hero.png'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'KahnLi-lyc' => 'https://github.com/KahnLi-lyc' }
  s.source           = { :git => 'https://github.com/KahnLi-lyc/Interlude.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions = ['6.0']

  s.source_files = 'Sources/Interlude/**/*.swift'
  s.resource_bundles = {
    'Interlude' => ['Sources/Interlude/Resources/**/*.lproj']
  }
  s.frameworks = 'UIKit', 'SwiftUI'
end
