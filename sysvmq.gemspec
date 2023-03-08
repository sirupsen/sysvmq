# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "sysvmq"
  spec.version       = '0.2.2'
  spec.authors       = ["Simon Eskildsen"]
  spec.email         = ["sirup@sirupsen.com"]
  spec.summary       = %q{Ruby wrapper for SysV Message Queues}
  spec.description   = %q{Ruby wrapper for SysV Message Queues}
  spec.homepage      = "https://github.com/Sirupsen/sysvmq"
  spec.license       = "MIT"

  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/extconf.rb"]
end
