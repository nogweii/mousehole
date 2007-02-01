require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'
require 'fileutils'
include FileUtils

NAME = "mouseHole"
REV = File.read(".svn/entries")[/committed-rev="(\d+)"/, 1] rescue nil
VERS = "1.9" + (REV ? ".#{REV}" : "")
CLEAN.include ['**/.*.sw?', '*.gem', '.config']

Rake::RDocTask.new do |rdoc|
    rdoc.rdoc_dir = 'doc/rdoc'
    rdoc.options << '--line-numbers'
    rdoc.rdoc_files.add ['README', 'COPYING', 'lib/**/*.rb', 'doc/**/*.rdoc']
end

desc "Packages up MouseHole 2."
task :default => [:package]
task :package => [:clean]

desc "Run all the tests"
Rake::TestTask.new do |t|
    t.libs << "test"
    t.test_files = FileList['test/test_*.rb']
    t.verbose = true
end

spec =
    Gem::Specification.new do |s|
        s.name = NAME
        s.version = VERS
        s.platform = Gem::Platform::RUBY
        s.has_rdoc = false
        s.extra_rdoc_files = [ "README" ]
        s.summary = "a scriptable proxy, an alternative to Greasemonkey and personal web server."
        s.description = s.summary
        s.author = "why the lucky stiff"
        s.executables = ['mouseHole']

        s.add_dependency('camping-omnibus', '>= 1.5.180')
        s.add_dependency('hpricot', '>=0.5')
        s.add_dependency('json', '>=0.4.2')
        s.required_ruby_version = '>= 1.8.4'

        s.files = %w(COPYING README Rakefile) +
          Dir.glob("{bin,doc/rdoc,test,lib,static}/**/*") + 
          Dir.glob("ext/**/*.{h,c,rb}") +
          Dir.glob("samples/**/*.rb") +
          Dir.glob("tools/*.rb")
        
        s.require_path = "lib"
        # s.extensions = FileList["ext/**/extconf.rb"].to_a
        s.bindir = "bin"
    end

Rake::GemPackageTask.new(spec) do |p|
    p.need_tar = true
    p.gem_spec = spec
end

task :install do
  sh %{rake package}
  sh %{sudo gem install pkg/#{NAME}-#{VERS}}
end

task :uninstall => [:clean] do
  sh %{sudo gem uninstall mongrel}
end
