require 'rubygems'
require 'rake/clean'
require 'rake/gempackagetask'

CLEAN.include("pkg")

spec = Gem::Specification.new do |s|
    s.name       = "mavenizer"
    s.version    = "0.0.1"
    s.author     = "Jiri Pisa"
    s.email      = "jiri.pisa@jiripisa.net"
    s.homepage   = "http://jiripisa.net"
    s.summary    = "Mavenizer is an API for creating scripts converting Java projects to Maven."
    s.platform   = Gem::Platform::RUBY
    s.files      = FileList["{lib}/**/*"].exclude("rdoc").to_a
    s.require_path      = "lib"
    s.has_rdoc          = false
end

Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_zip   = true
end

desc "Installs the gem"
task :install do
  Dir.chdir"pkg"
  system "gem install mavenizer"
end

task :default => [:clean, :package, :install, :clean]