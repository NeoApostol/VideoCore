Pod::Spec.new do |s|
  s.name                = "VideoCore"
  s.module_name         = "VideoCore"
  s.version             = "0.3.2"
  s.summary             = "An audio and video manipulation and streaming pipeline with support for RTMP."
  s.description      = <<-DESC
                          This is a work-in-progress library with the
                          intention of being an audio and video manipulation
                          and streaming pipeline for iOS.
                          DESC
  s.homepage            = "https://github.com/jgh-/VideoCore"
  s.license             = 'MIT'
  s.authors             = { "James Hurley" => "jamesghurley@gmail.com" }
  s.source              = { :git => "https://github.com/jgh-/VideoCore.git", :tag => s.version.to_s, :submodules => true }

  s.requires_arc        = false

  s.header_dir          = 'videocore'
  s.header_mappings_dir = 'videocore'

  s.source_files        = [ 'mixers/**/*.h*', 'mixers/**/*.cpp', 'mixers/**/*.m*', 
                            'rtmp/**/*.h*', 'rtmp/**/*.cpp', 'rtmp/**/*.m*',
                            'sources/**/*.h*', 'sources/**/*.cpp', 'sources/**/*.m*',
                            'stream/**/*.h*', 'stream/**/*.cpp', 'stream/**/*.m*',
                            'system/**/*.h*', 'system/**/*.cpp', 'system/**/*.m*',
                            'transforms/**/*.h*', 'transforms/**/*.cpp', 'transforms/**/*.m*',
                            'api/**/*.h*', 'api/**/*.m*',
                            'filters/**/*.cpp', 'filters/**/*.h*' ]

  s.frameworks          = [ 'VideoToolbox', 'AudioToolbox', 'AVFoundation', 'CFNetwork', 'CoreMedia',
                            'CoreVideo', 'OpenGLES', 'Foundation', 'CoreGraphics' ]

  s.libraries           = 'c++'

  s.dependency          'glm'
  s.dependency          'UriParser-cpp', '~> 0.1.3'
  
  

  s.ios.deployment_target = '5.0'

  # Before we can get OS X deployment working, we'll need to use sub-specs to
  # separate out the source files for OS X vs. iOS
  #s.osx.deployment_target = '10.7'

  s.subspec 'Swift' do |swift|
    swift.public_header_files = 'videocore/api/**/*.h'
    swift.source_files        = [ 'videocore/mixers/**/*.h*', 'videocore/mixers/**/*.cpp', 'videocore/mixers/**/*.m*', 
                            'videocore/rtmp/**/*.h*', 'videocore/rtmp/**/*.cpp', 'videocore/rtmp/**/*.m*',
                            'videocore/sources/**/*.h*', 'videocore/sources/**/*.cpp', 'videocore/sources/**/*.m*',
                            'videocore/stream/**/*.h*', 'videocore/stream/**/*.cpp', 'videocore/stream/**/*.m*',
                            'videocore/system/**/*.h*', 'videocore/system/**/*.cpp', 'videocore/system/**/*.m*',
                            'videocore/transforms/**/*.h*', 'videocore/transforms/**/*.cpp', 'videocore/transforms/**/*.m*',
                            'videocore/api/**/*.h*', 'videocore/api/**/*.m*',
                            'videocore/filters/**/*.cpp', 'videocore/filters/**/*.h*' ]
	swift.xcconfig            = { "HEADER_SEARCH_PATHS" => "${PODS_ROOT}/VideoCore" }
    swift.ios.deployment_target = '8.0'
  end

end
