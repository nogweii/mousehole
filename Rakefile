require 'rubygems'
require 'rake/gempackagetask'
require 'rake/clean'
require './lib/mouseHole/constants'

PKG_VERSION = MouseHole::VERSION
PKG_FILES = FileList[
    '[A-Z]*',
    'bin/**/*', 
    'lib/**/*.rb', 
    'test/**/*.rb',
    'images/*'
]
RUBY_FORGE_PROJECT = "mousehole"
RUBY_FORGE_USER = "why"

BINARY_PLATFORMS = ['win32']
DIST_EXTENSIONS = ["gem", "tar.bz2", "zip", "exe"]

CLEAN.include "**/.*.sw*"


specs = {}
specs['standard'] = Gem::Specification.new do |s|
    s.platform = Gem::Platform::RUBY
    s.name = 'mouseHole'
    s.version = PKG_VERSION
    s.summary = "mouseHole is a scriptable proxy, an alternative to Greasemonkey and personal web server."
    s.description = %{
        MouseHole is a personal web proxy written in Ruby (and currently based on WEBrick) 
        designed to be simple to script. Scripts can rewrite the web as you view it, altering 
        content and behavior as you browse. Basically, it's an alternative to Greasemonkey, 
        which does the same but which only works in Firefox."
    }
    #
    s.files = PKG_FILES.to_a
    #
    s.require_path = 'lib'
    s.autorequire = 'rake'
    #
    # s.bindir = "bin"
    # s.executables = ["mouseHole"]
    # s.default_executable = "mouseHole"
    #
    s.has_rdoc = false
    #
    s.author = "why the lucky stiff"
    s.email = "why@ruby-lang.org"
    s.homepage = "http://mousehole.rubyforge.org"
    s.rubyforge_project = "mousehole"
end

# copy platform-specific files into place, prepare gemspecs
BINARY_PLATFORMS.each do |platform|

    specs[platform] = specs['standard'].dup
    specs[platform].platform = platform
    specs[platform].extensions = []
    specs[platform].files += FileList["#{platform}/**/*"].map do |pf| 
        target = pf.gsub( /^#{ platform }\//, '' )
        unless File.directory? pf
            file target do
                mkdir_p File.dirname( target )
                cp pf, target
            end
            task :clobber_package do
                rm_r target rescue nil
            end
        end
        target
    end

    # give bin files an .rb extension
    specs[platform].files.map do |pf|
        if pf =~ /^bin\//
            pf_rb = pf + ".rb"
            file pf_rb do
                cp pf, pf_rb
            end
            task :clobber_package do
                rm_r pf_rb rescue nil
            end
            pf_rb
        end
        pf
    end
end

# create all distributions
Rake::GemPackageTask.new specs['standard'] do |pkg|
    pkg.package_dir = 'pkg/standard'
    pkg.need_tar_bz2 = true
    pkg.need_zip    = true
end
BINARY_PLATFORMS.each do |platform|
    Rake::GemPackageTask.new specs[platform] do |pkg|
        pkg.package_dir = "pkg/#{ platform }"
        pkg.need_zip = true
    end
end
task :clobber_package do
    rm_r 'pkg' rescue nil
end
task :package do
    specs.keys.each do |platform|
        Dir["pkg/#{platform}/*"].each do |pkgf|
            next if File.directory? pkgf
            pkgnew = File.basename( pkgf )
            unless platform == 'standard'
                pkgnew.gsub!( /(-#{platform})?.(#{ DIST_EXTENSIONS.join '|' })/, "-#{platform}\.\\2" )
            end
            mv pkgf, "pkg/" + pkgnew
        end
    end
end

desc "Tag the release in CVS."
task :tag_cvs do
    system("cvs tag RELEASE_#{PKG_VERSION.gsub(/\./,'_')}")
end

desc "Publish the release files to RubyForge."
task :rubyforge_upload => [:package] do
    files = Dir["pkg/*.{#{ DIST_EXTENSIONS.join ',' }}"]

    if RUBY_FORGE_PROJECT then
        require 'net/http'
        require 'open-uri'

        project_uri = "http://rubyforge.org/projects/#{RUBY_FORGE_PROJECT}/"
        project_data = open(project_uri) { |data| data.read }
        group_id = project_data[/[?&]group_id=(\d+)/, 1]
        raise "Couldn't get group id" unless group_id

        # This echos password to shell which is a bit sucky
        if ENV["RUBY_FORGE_PASSWORD"]
            password = ENV["RUBY_FORGE_PASSWORD"]
        else
            print "#{RUBY_FORGE_USER}@rubyforge.org's password: "
            password = STDIN.gets.chomp
        end

        login_response = Net::HTTP.start("rubyforge.org", 80) do |http|
            data = [
                "login=1",
                "form_loginname=#{RUBY_FORGE_USER}",
                "form_pw=#{password}"
            ].join("&")
            http.post("/account/login.php", data)
        end

        cookie = login_response["set-cookie"]
        raise "Login failed" unless cookie
        headers = { "Cookie" => cookie }

        release_uri = "http://rubyforge.org/frs/admin/?group_id=#{group_id}"
        release_data = open(release_uri, headers) { |data| data.read }
        package_id = release_data[/[?&]package_id=(\d+)/, 1]
        raise "Couldn't get package id" unless package_id

        first_file = true
        release_id = ""

        files.each do |filename|
            basename  = File.basename(filename)
            file_ext  = File.extname(filename)
            file_data = File.open(filename, "rb") { |file| file.read }
            platform  = $1 if filename =~ /-(\w+)\.#{ file_ext }$/

            puts "Releasing #{basename}..."

            release_response = Net::HTTP.start("rubyforge.org", 80) do |http|
                release_date = Time.now.strftime("%Y-%m-%d %H:%M")
                type_map = {
                    ".zip"    => "3000",
                    ".tgz"    => "3110",
                    ".bz2"    => "3110",
                    ".gz"     => "3110",
                    ".exe"    => "1100",
                    ".dmg"    => "1200",
                    ".gem"    => "1400"
                }; type_map.default = "9999"
                arch_map = {
                    "win32"   => "1000"
                }; arch_map.default = "8000"
                arch = arch_map[platform]
                boundary = "rubyqMY6QN9bp6e4kS21H4y0zxcvoor"

                query_hash = if first_file then
                  {
                    "group_id" => group_id,
                    "package_id" => package_id,
                    "release_name" => PKG_VERSION,
                    "release_date" => release_date,
                    "type_id" => type,
                    "processor_id" => arch,
                    "release_notes" => "",
                    "release_changes" => "",
                    "preformatted" => "1",
                    "submit" => "1"
                  }
                else
                  {
                    "group_id" => group_id,
                    "release_id" => release_id,
                    "package_id" => package_id,
                    "step2" => "1",
                    "type_id" => type,
                    "processor_id" => arch,
                    "submit" => "Add This File"
                  }
                end

                query = "?" + query_hash.map do |(name, value)|
                    [name, URI.encode(value)].join("=")
                end.join("&")

                data = [
                    "--" + boundary,
                    "Content-Disposition: form-data; name=\"userfile\"; filename=\"#{basename}\"",
                    "Content-Type: application/octet-stream",
                    "Content-Transfer-Encoding: binary",
                    "", file_data, ""
                    ].join("\x0D\x0A")

                release_headers = headers.merge(
                    "Content-Type" => "multipart/form-data; boundary=#{boundary}"
                )

                target = first_file ? "/frs/admin/qrs.php" : "/frs/admin/editrelease.php"
                http.post(target + query, data, release_headers)
            end

            if first_file then
                release_id = release_response.body[/release_id=(\d+)/, 1]
                raise("Couldn't get release id") unless release_id
            end

            first_file = false
        end
    end
end
