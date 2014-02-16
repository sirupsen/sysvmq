# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "sysvmq"
  spec.version       = '0.0.1'
  spec.authors       = ["Simon Eskildsen"]
  spec.email         = ["sirup@sirupsen.com"]
  spec.summary       = %q{Ruby wrapper for SysV Message Queues}
  spec.description   = %q{Ruby wrapper for SysV Message Queues}
  spec.homepage      = "https://github.com/Sirupsen/sysvmq"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/extconf.rb"]

  spec.add_development_dependency "pry"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
end
