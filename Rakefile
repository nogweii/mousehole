require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/contrib/rubyforgepublisher'
require File.dirname(__FILE__) + '/lib/mouseHole'

PKG_VERSION = MouseHole::VERSION
PKG_NAME = "mouseHole"
PKG_FILE_NAME = "#{PKG_NAME}-#{PKG_VERSION}"
RUBY_FORGE_PROJECT = "mousehole"
RUBY_FORGE_USER = "why"
RELEASE_NAME = "#{PKG_NAME}-#{PKG_VERSION}"
PKG_FILES = FileList[
    '[A-Z]*',
    'bin/**/*', 
    'lib/**/*.rb', 
    'test/**/*.rb',
    'images/*'
]
BINARY_PLATFORMS = ['win32']

CLEAN.include "**/.*.sw*"

spec = Gem::Specification.new do |s|
    s.name = PKG_NAME
    s.version = PKG_VERSION
    s.summary = "scriptable proxy, browser-neutral alternative to Greasemonkey."
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
    #
    s.bindir = 'bin'
    s.executables = ["mouseHole"]
    s.default_executable = "mouseHole"
    #
    s.has_rdoc = false
    #
    s.author = "why the lucky stiff"
    s.email = "why@ruby-lang.org"
    s.homepage = "http://mousehole.rubyforge.org"
    s.rubyforge_project = "mousehole"
end

Rake::GemPackageTask.new(spec) do |pkg|
    pkg.need_tar_gz = true
    pkg.need_zip = true
end

BINARY_PLATFORMS.each do |platform|
    bin_files = []
    FileList["#{ platform }/**/*"].each do |pkg_file|
        next if File.directory? pkg_file
        target = pkg_file.gsub %r!^#{ platform }/!, ''
        cp pkg_file, target
        bin_files << target
    end

    bin_spec = spec.dup
    bin_spec.platform = platform
    bin_spec.files += bin_files
    # bin_spec.extensions = []

    Rake::GemPackageTask.new(bin_spec) do |pkg|
        pkg.need_zip = true
    end

    p bin_files
    # bin_files.each do |pkg_file|
    #     rm pkg_file
    # end
end

RUBYSCRIPT2EXE   = ENV['RUBYSCRIPT2EXE'] ||
    File.join(Config::CONFIG['bindir'], 'rubyscript2exe.rb')
RUBY_MAIN_SCRIPT = ENV['RUBYMAINSCRIPT'] || 'mouseHole.rb'
EXEC_TARGET      = RUBY_MAIN_SCRIPT.sub(/rb$/, 'exe')

file :executable => [ RUBY_MAIN_SCRIPT ] do | t |
    unless File.exist?(RUBYSCRIPT2EXE)
        raise RuntimeError.new("rubyscript2exe.rb not found " +
            "pass with RUBYSCRIPT2EXE=/path/to/rubyscript2.rb")
    end
    sh %{ruby "#{RUBYSCRIPT2EXE}" #{RUBY_MAIN_SCRIPT}}
    File.move(EXEC_TARGET, 'build')
    puts "Created executable file build/#{EXEC_TARGET}.exe" 
end

desc "Publish the release files to RubyForge."
task :tag_cvs do
    system("cvs tag RELEASE_#{PKG_VERSION.gsub(/\./,'_')} -m 'tag release #{PKG_VERSION}'")
end

desc "Publish the release files to RubyForge."
task :rubyforge_upload => [:package] do
    files = ["exe", "tar.gz", "zip"].map { |ext| "pkg/#{PKG_FILE_NAME}.#{ext}" }

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

            puts "Releasing #{basename}..."

            release_response = Net::HTTP.start("rubyforge.org", 80) do |http|
                release_date = Time.now.strftime("%Y-%m-%d %H:%M")
                type_map = {
                    ".zip"    => "3000",
                    ".tgz"    => "3110",
                    ".gz"     => "3110",
                    ".gem"    => "1400"
                }; type_map.default = "9999"
                type = type_map[file_ext]
                boundary = "rubyqMY6QN9bp6e4kS21H4y0zxcvoor"

                query_hash = if first_file then
                  {
                    "group_id" => group_id,
                    "package_id" => package_id,
                    "release_name" => RELEASE_NAME,
                    "release_date" => release_date,
                    "type_id" => type,
                    "processor_id" => "8000", # Any
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
                    "processor_id" => "8000", # Any
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
