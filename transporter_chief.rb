#!/usr/bin/ruby

#TODO: Make a class of it

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'pathname'
require 'tmpdir'

$script_path = File.expand_path(File.dirname(__FILE__))
$temp_path = Dir.mktmpdir
$fruitstrap_executable = "#{$script_path}/fruitstrap"

def purge_temp
  FileUtils.rm_rf($temp_path)
end

def initialize_temp
  purge_temp
  FileUtils.mkdir($temp_path)
end

def execute(command, verbose)
  if verbose
    system command
  else
    system "#{command} >> /dev/null"
  end
end

def log(message)
  puts "# Transporter chief: #{message}, Sir."
end

def fail(message)
  log message
  purge_temp
  exit 1
end

# prepare the options and their parser
options = OpenStruct.new
options.update_fruitstrap = false
options.verbose = false
options.device_id = nil
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] path_or_bundle_id"

  opts.separator ""
  opts.separator "Supported types for path_or_bundle_id:\n    *.app (app bundle directory)\n    *.ipa (iPhone application file)\n    Bundle Identifier to uninstall"
  opts.separator ""
  opts.separator "Options:"

  opts.on('-d', '--device IDENTIFIER', 'Beam to specific device') do |id|
    options.device_id = id
  end

  opts.on('-u', '--update', 'Update fruitstrap binary to latest version') do
    options.update_fruitstrap = true
  end

  opts.on('-v', '--verbose', 'Redirect logs of ship\'s computer to console') do
    options.verbose = true
  end

  opts.on('-n', '--uninstall', 'Uninstalls application also will try uninstall if path_or_bundle_id is neither .app nor .ipa') do
    options.uninstall = true
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end

# parse the command line parameters or print the help message
if ARGV.length < 1
  puts option_parser
  exit
else
  option_parser.parse!
end

# update fruitstrap if it's not installed or an update was requested
if options.update_fruitstrap || !File.exist?($fruitstrap_executable)
  initialize_temp

  if File.exist? $fruitstrap_executable
    log "Removing current fruitstrap"
    FileUtils.rm_rf($fruitstrap_executable)
  end

  Dir.chdir($temp_path) do
    log "Fetching latest fruitstrap"
    quiet = options.verbose ? "" : "-q"
#    execute("git clone #{quiet} git://github.com/jgranick/fruitstrap.git", options.verbose)
    execute("git clone #{quiet} git://github.com/igorsokolov/fruitstrap.git", options.verbose)
    Dir.chdir("fruitstrap/") do
      log "Compiling fruitstrap"
      execute("make fruitstrap", options.verbose)
    end
  end
  FileUtils.mv(File.join($temp_path, "/fruitstrap/fruitstrap"), $script_path)
end

# install the app if a valid path was given
path_to_app = ARGV.last()
if path_to_app != nil
  # deploy the given app/ipa path to the first connected device
  if File.exist?(path_to_app) && File.extname(path_to_app) == ".ipa"
    # unzip the ipa to make way to the app bundle - updates path_to_app
    initialize_temp

    log "Extracting app"
    execute("unzip -o '#{path_to_app}' -d #{$temp_path}", options.verbose)
    if $? == 0
      path_to_app = Pathname(File.join($temp_path, "Payload/")).children.first
    else
      fail "Cannot unzip ipa at #{path_to_app}. Run verbose to get a more specific error message"
    end
  end

  if File.exist?(path_to_app) && File.extname(path_to_app) == ".app"
    # fruitstrap the app bundle
    device_id_string = options.device_id == nil ? "" : " #{options.device_id}"
    device_id_parameter = options.device_id == nil ? "" : "-i #{options.device_id}"
    log "Beaming app to device#{device_id_string}"
    execute("'#{$fruitstrap_executable}' install #{device_id_parameter} -b '#{path_to_app}'", options.verbose)
    if $? != 0
      fail "Unable to deploy app to device. Run verbose to get a more specific error message"
    end
  else
    # Try to uninstall if the path parameter is bundle identifier
    log "Removing app from device#{device_id_string}"
    execute("'#{$fruitstrap_executable}' uninstall #{device_id_parameter} -b '#{path_to_app}'", options.verbose)
    fail "Unknown app type or bundle id at #{path_to_app}" if $? != 0
  end
end

purge_temp
log "All done"