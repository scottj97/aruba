require 'fileutils'
require 'rspec/expectations'

require 'aruba/extensions/string/strip'

require 'aruba/creators/aruba_file_creator'
require 'aruba/creators/aruba_fixed_size_file_creator'

require 'aruba/platform'
require 'aruba/api/core'
require 'aruba/api/commands'
require 'aruba/api/filesystem'
require 'aruba/api/deprecated'

Aruba::Platform.require_matching_files('../matchers/**/*.rb', __FILE__)

module Aruba
  module Api
    include Aruba::Api::Core
    include Aruba::Api::Deprecated

    # Check if file or directory exist
    #
    # @param [String] file_or_directory
    #   The file/directory which should exist
    def exist?(file_or_directory)
      Aruba::Platform.exist? expand_path(file_or_directory)
    end

    # Check if file exist and is file
    #
    # @param [String] file
    #   The file/directory which should exist
    def file?(file)
      Aruba::Platform.file? expand_path(file)
    end

    # Check if directory exist and is directory
    #
    # @param [String] file
    #   The file/directory which should exist
    def directory?(file)
      Aruba::Platform.directory? expand_path(file)
    end

    # Check if path is absolute
    #
    # @return [TrueClass, FalseClass]
    #   Result of check
    def absolute?(path)
      ArubaPath.new(path).absolute?
    end

    # Check if path is relative
    #
    # @return [TrueClass, FalseClass]
    #   Result of check
    def relative?(path)
      ArubaPath.new(path).relative?
    end

    # Return all existing paths (directories, files) in current dir
    #
    # @return [Array]
    #   List of files and directories
    def all_paths
      list('.').map { |p| expand_path(p) }
    end

    # Return all existing files in current directory
    #
    # @return [Array]
    #   List of files
    def all_files
      list('.').select { |p| file? p }.map { |p| expand_path(p) }
    end

    # Return all existing directories in current directory
    #
    # @return [Array]
    #   List of files
    def all_directories
      list('.').select { |p| directory? p }.map { |p| expand_path(p) }
    end

    # Create directory object
    #
    # @return [Dir]
    #   The directory object
    def directory(path)
      fail ArgumentError, %(Path "#{name}" does not exist.) unless exist? name

      Dir.new(expand_path(path))
    end

    # Return content of directory
    #
    # @return [Array]
    #   The content of directory
    def list(name)
      fail ArgumentError, %(Path "#{name}" does not exist.) unless exist? name
      fail ArgumentError, %(Only directories are supported. Path "#{name}" is not a directory.) unless directory? name

      existing_files            = Dir.glob(expand_path(File.join(name, '**', '*')))
      current_working_directory = ArubaPath.new(expand_path('.'))

      existing_files.map { |d| ArubaPath.new(d).relative_path_from(current_working_directory).to_s }
    end

    # Return content of file
    #
    # @return [Array]
    #   The content of file, without "\n" or "\r\n" at the end. To rebuild the file use `content.join("\n")`
    def read(name)
      fail ArgumentError, %(Path "#{name}" does not exist.) unless exist? name
      fail ArgumentError, %(Only files are supported. Path "#{name}" is not a file.) unless file? name

      File.readlines(expand_path(name)).map(&:chomp)
    end

    # Create a file with given content
    #
    # The method does not check if file already exists. If the file name is a
    # path the method will create all neccessary directories.
    #
    # @param [String] file_name
    #   The name of the file
    #
    # @param [String] file_content
    #   The content which should be written to the file
    def write_file(name, content)
      Creators::ArubaFileCreator.new.write(expand_path(name), content, false)

      self
    end

    # Create an empty file
    #
    # @param [String] file_name
    #   The name of the file
    def touch(*args)
      args = args.flatten

      options = if args.last.kind_of? Hash
                  args.pop
                else
                  {}
                end

      args.each { |p| create_directory(File.dirname(p)) }

      Aruba::Platform.touch(args.map { |p| expand_path(p) }, options)

      self
    end

    # Copy a file and/or directory
    #
    # @param [String, Array] source
    #   A single file or directory, multiple files or directories or multiple
    #   files and directories. If multiple sources are given the destination
    #   needs to be a directory
    #
    # @param [String] destination
    #   A file or directory name. If multiple sources are given the destination
    #   needs to be a directory
    #
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    # def copy(*source, destination)
    def copy(*args)
      args = args.flatten
      destination = args.pop
      source = args

      source.each do |s|
        raise ArgumentError, %(The following source "#{s}" does not exist.) unless exist? s
      end

      raise ArgumentError, "Using a fixture as destination (#{destination}) is not supported" if destination.start_with? aruba.config.fixtures_path_prefix
      raise ArgumentError, "Multiples sources can only be copied to a directory" if source.count > 1 && exist?(destination) && !directory?(destination)

      source_paths     = source.map { |f| expand_path(f) }
      destination_path = expand_path(destination)

      if source_paths.count > 1
        Aruba::Platform.mkdir(destination_path)
      else
        Aruba::Platform.mkdir(File.dirname(destination_path))
        source_paths = source_paths.first
      end

      Aruba::Platform.cp source_paths, destination_path

      self
    end
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/CyclomaticComplexity

    # Create a file with the given size
    #
    # The method does not check if file already exists. If the file name is a
    # path the method will create all neccessary directories.
    #
    # @param [String] file_name
    #   The name of the file
    #
    # @param [Integer] file_size
    #   The size of the file
    def write_fixed_size_file(name, size)
      Creators::ArubaFixedSizeFileCreator.new.write(expand_path(name), size, false)

      self
    end

    # Create a file with given content
    #
    # The method does check if file already exists and fails if the file is
    # missing. If the file name is a path the method will create all neccessary
    # directories.
    def overwrite_file(name, content)
      Creators::ArubaFileCreator.new.write(expand_path(name), content, true)

      self
    end

    # Change file system  permissions of file
    #
    # @param [Octal] mode
    #   File system mode, eg. 0755
    #
    # @param [String] file_name
    #   Name of file to be modified. This file needs to be present to succeed
    def chmod(*args)
      args = args.flatten

      options = if args.last.kind_of? Hash
                  args.pop
                else
                  {}
                end

      mode = args.shift
      mode = if mode.kind_of? String
               mode.to_i(8)
             else
               mode
             end

      args.each { |p| raise "Expected #{p} to be present" unless exist?(p) }
      paths = args.map { |p| expand_path(p) }

      Aruba::Platform.chmod(mode, paths, options)

      self
    end

    # Append data to file
    #
    # @param [String] file_name
    #   The name of the file to be used
    #
    # @param [String] file_content
    #   The content which should be appended to file
    def append_to_file(file_name, file_content)
      file_name = expand_path(file_name)

      Aruba::Platform.mkdir(File.dirname(file_name))
      File.open(file_name, 'a') { |f| f << file_content }
    end

    # Create a directory in current directory
    #
    # @param [String] directory_name
    #   The name of the directory which should be created
    def create_directory(directory_name)
      Aruba::Platform.mkdir expand_path(directory_name)

      self
    end

    # Remove file or directory
    #
    # @param [Array, String] name
    #   The name of the file / directory which should be removed
    def remove(*args)
      args = args.flatten

      options = if args.last.kind_of? Hash
                  args.pop
                else
                  {}
                end

      args = args.map { |p| expand_path(p) }

      Aruba::Platform.rm(args, options)
    end

    # Pipe data in file
    #
    # @param [String] file_name
    #   The file which should be used to pipe in data
    def pipe_in_file(file_name)
      file_name = expand_path(file_name)

      File.open(file_name, 'r').each_line do |line|
        last_command.write(line)
      end
    end

    # Read content of file and yield the content to block
    #
    # @param [String) file
    #   The name of file which should be read from
    #
    # @yield
    #   Pass the content of the given file to this block
    def with_file_content(file, &block)
      stop_processes!

      content = read(file).join("\n")

      yield(content)
    end

    # Unescape string
    #
    # @param [String] string
    #   The string which should be unescaped, e.g. the output of a command
    #
    # @return
    #   The string stripped from escape sequences
    def unescape(string)
      string = string.gsub('\n', "\n").gsub('\"', '"').gsub('\e', "\e")
      string = string.gsub(/\e\[\d+(?>(;\d+)*)m/, '') unless @aruba_keep_ansi
      string
    end

    # Fetch output (stdout, stderr) from command
    #
    # @param [String] cmd
    #   The command
    def output_from(cmd)
      process_monitor.output_from(cmd)
    end

    # Fetch stdout from command
    #
    # @param [String] cmd
    #   The command
    def stdout_from(cmd)
      process_monitor.stdout_from(cmd)
    end

    # Fetch stderr from command
    #
    # @param [String] cmd
    #   The command
    def stderr_from(cmd)
      process_monitor.stderr_from(cmd)
    end

    # Get stdout of all processes
    #
    # @return [String]
    #   The stdout of all process which have run before
    def all_stdout
      process_monitor.all_stdout
    end

    # Get stderr of all processes
    #
    # @return [String]
    #   The stderr of all process which have run before
    def all_stderr
      process_monitor.all_stderr
    end

    # Get stderr and stdout of all processes
    #
    # @return [String]
    #   The stderr and stdout of all process which have run before
    def all_output
      process_monitor.all_output
    end

    # Full compare arg1 and arg2
    #
    # @return [TrueClass, FalseClass]
    #   If arg1 is exactly the same as arg2 return true, otherwise false
    def assert_exact_output(expected, actual)
      actual.force_encoding(expected.encoding) if RUBY_VERSION >= "1.9"
      expect(unescape(actual)).to eq unescape(expected)
    end

    # Partial compare arg1 and arg2
    #
    # @return [TrueClass, FalseClass]
    #   If arg2 contains arg1 return true, otherwise false
    def assert_partial_output(expected, actual)
      actual.force_encoding(expected.encoding) if RUBY_VERSION >= "1.9"
      expect(unescape(actual)).to include(unescape(expected))
    end

    # Regex Compare arg1 and arg2
    #
    # @return [TrueClass, FalseClass]
    #   If arg2 matches arg1 return true, otherwise false
    def assert_matching_output(expected, actual)
      actual.force_encoding(expected.encoding) if RUBY_VERSION >= "1.9"
      expect(unescape(actual)).to match(/#{unescape(expected)}/m)
    end

    # Negative regex compare arg1 and arg2
    #
    # @return [TrueClass, FalseClass]
    #   If arg2 does not match arg1 return true, otherwise false
    def assert_not_matching_output(expected, actual)
      actual.force_encoding(expected.encoding) if RUBY_VERSION >= "1.9"
      expect(unescape(actual)).not_to match(/#{unescape(expected)}/m)
    end

    # Negative partial compare arg1 and arg2
    #
    # @return [TrueClass, FalseClass]
    #   If arg2 does not match/include arg1 return true, otherwise false
    def assert_no_partial_output(unexpected, actual)
      actual.force_encoding(unexpected.encoding) if RUBY_VERSION >= "1.9"
      if Regexp === unexpected
        expect(unescape(actual)).not_to match unexpected
      else
        expect(unescape(actual)).not_to include(unexpected)
      end
    end

    # Partial compare output of interactive command and arg1
    #
    # @return [TrueClass, FalseClass]
    #   If output of interactive command includes arg1 return true, otherwise false
    def assert_partial_output_interactive(expected)
      unescape(last_command.stdout).include?(unescape(expected)) ? true : false
    end

    # Check if command succeeded and if arg1 is included in output
    #
    # @return [TrueClass, FalseClass]
    #   If exit status is 0 and arg1 is included in output return true, otherwise false
    def assert_passing_with(expected)
      assert_success(true)
      assert_partial_output(expected, all_output)
    end

    # Check if command failed and if arg1 is included in output
    #
    # @return [TrueClass, FalseClass]
    #   If exit status is not equal 0 and arg1 is included in output return true, otherwise false
    def assert_failing_with(expected)
      assert_success(false)
      assert_partial_output(expected, all_output)
    end

    # Check exit status of process
    #
    # @return [TrueClass, FalseClass]
    #   If arg1 is true, return true if command was successful
    #   If arg1 is false, return true if command failed
    def assert_success(success)
      if success
        expect(last_command).to be_successfully_executed
      else
        expect(last_command).not_to be_successfully_executed
      end
    end

    # @private
    def assert_exit_status(status)
      expect(last_command).to have_exit_status(status)
    end

    # @private
    def assert_not_exit_status(status)
      expect(last_exit_status).not_to eq(status),
        append_output_to("Exit status was #{last_exit_status} which was not expected.")
    end

    # @private
    def append_output_to(message)
      "#{message} Output:\n\n#{all_output}\n"
    end

    def process_monitor
      return @process_monitor if defined? @process_monitor

      @process_monitor = ProcessMonitor.new(announcer)

      @process_monitor
    end

    # @private
    def processes
      process_monitor.send(:processes)
    end

    # @private
    def stop_processes!
      process_monitor.stop_processes!
    end

    # Terminate all running processes
    def terminate_processes!
      process_monitor.terminate_processes!
    end

    # @private
    def last_command
      processes.last[1]
    end

    # @private
    def register_process(*args)
      process_monitor.register_process(*args)
    end

    # @private
    def get_process(wanted)
      process_monitor.get_process(wanted)
    end

    # Run given command and stop it if timeout is reached
    #
    # @param [String] cmd
    #   The command which should be executed
    #
    # @param [Integer] timeout
    #   If the timeout is reached the command will be killed
    #
    # @yield [SpawnProcess]
    #   Run block with process
    def run(cmd, timeout = nil)
      timeout ||= exit_timeout
      @commands ||= []
      @commands << cmd

      cmd = Aruba::Platform.detect_ruby(cmd)

      announcer.announce(:directory, Dir.pwd)
      announcer.announce(:command, cmd)
      announcer.announce(:environment, 'PATH', ENV['PATH'])
      announcer.announce(:timeout, 'exit-timeout', aruba.config.exit_timeout)

      process = Aruba.process.new(cmd, timeout, io_wait, expand_path('.'), aruba.environment.to_h)

      if aruba.config.before? :cmd
        Aruba::Platform.deprecated('The use of "before"-hook" ":cmd" is deprecated. Use ":command" instead. Please be aware that this hook gets the command passed in not the cmdline itself. To get the commandline use "#cmd.commandline"')
        aruba.config.before(:cmd, self, cmd)
      end

      aruba.config.before(:command, self, process)

      process_monitor.register_process(cmd, process)
      process.run!

      aruba.config.after(:command, self, process)

      block_given? ? yield(process) : process
    end

    # Default exit timeout for running commands with aruba
    #
    # Overwrite this method if you want a different timeout or set
    # `@aruba_timeout_seconds`.
    def exit_timeout
      aruba.config.exit_timeout
    end

    # Default io wait timeout
    #
    # Overwrite this method if you want a different timeout or set
    # `@aruba_io_wait_seconds
    def io_wait
      aruba.config.io_wait_timeout
    end

    # The root directory of aruba
    def root_directory
      aruba.config.root_directory
    end

    # The path to the directory which contains fixtures
    # You might want to overwrite this method to place your data else where.
    #
    # @return [String]
    #   The directory to where your fixtures are stored
    def fixtures_directory
      unless @fixtures_directory
        candidates = aruba.config.fixtures_directories.map { |dir| File.join(root_directory, dir) }
        @fixtures_directory = candidates.find { |dir| Aruba::Platform.directory? dir }
        raise "No fixtures directories are found" unless @fixtures_directory
      end
      raise "#{@fixtures_directory} is not a directory" unless Aruba::Platform.directory?(@fixtures_directory)
      @fixtures_directory
    end

    # Run a command with aruba
    #
    # Checks for error during command execution and checks the output to detect
    # an timeout error.
    #
    # @param [String] cmd
    #   The command to be executed
    #
    # @param [TrueClass,FalseClass] fail_on_error
    #   Should aruba fail on error?
    #
    # @param [Integer] timeout
    #   Timeout for execution
    def run_simple(cmd, fail_on_error = true, timeout = nil)
      command = run(cmd, timeout)
      @last_exit_status = command.stop(announcer)

      @timed_out = command.timed_out?

      if fail_on_error
        expect(command).to have_finished_in_time
        expect(command).to be_successfully_executed
      end
    end

    # Provide data to command via stdin
    #
    # @param [String] input
    #   The input for the command
    def type(input)
      return close_input if "" == input
      last_command.write(input << "\n")
    end

    # Close stdin
    def close_input
      last_command.close_io(:stdin)
    end

    # Use a clean rvm gemset
    #
    # Please make sure that you've got [rvm](http://rvm.io/) installed.
    #
    # @param [String] gemset
    #   The name of the gemset to be used
    def use_clean_gemset(gemset)
      run_simple(%{rvm gemset create "#{gemset}"}, true)
      if all_stdout =~ /'#{gemset}' gemset created \((.*)\)\./
        gem_home = Regexp.last_match[1]
        set_environment_variable('GEM_HOME', gem_home)
        set_environment_variable('GEM_PATH', gem_home)
        set_environment_variable('BUNDLE_PATH', gem_home)

        paths = (ENV['PATH'] || "").split(File::PATH_SEPARATOR)
        paths.unshift(File.join(gem_home, 'bin'))
        set_environment_variable('PATH', paths.uniq.join(File::PATH_SEPARATOR))

        run_simple("gem install bundler", true)
      else
        raise "I didn't understand rvm's output: #{all_stdout}"
      end
    end

    # Unset variables used by bundler
    def unset_bundler_env_vars
      %w[RUBYOPT BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_GEMFILE].each do |key|
        set_environment_variable(key, nil)
      end
    end

    # Set environment variable
    #
    # @param [String] key
    #   The name of the environment variable as string, e.g. 'HOME'
    #
    # @param [String] value
    #   The value of the environment variable. Needs to be a string.
    def set_environment_variable(name, value)
      name = name.to_s
      value = value.to_s

      announcer.announce(:environment, name, value)
      aruba.environment[name] = value

      self
    end

    # Append environment variable
    #
    # @param [String] key
    #   The name of the environment variable as string, e.g. 'HOME'
    #
    # @param [String] value
    #   The value of the environment variable. Needs to be a string.
    def append_environment_variable(name, value)
      name = name.to_s
      value = value.to_s

      aruba.environment.append name, value
      announcer.announce(:environment, name, aruba.environment[name])

      self
    end

    # Prepend environment variable
    #
    # @param [String] key
    #   The name of the environment variable as string, e.g. 'HOME'
    #
    # @param [String] value
    #   The value of the environment variable. Needs to be a string.
    def prepend_environment_variable(name, value)
      name = name.to_s
      value = value.to_s

      aruba.environment.prepend name, value
      announcer.announce(:environment, name, aruba.environment[name])

      self
    end

    # Access to announcer
    def announcer
      @announcer ||= Announcer.new(
        self,
        :stdout => @announce_stdout,
        :stderr => @announce_stderr,
        :dir    => @announce_dir,
        :cmd    => @announce_cmd,
        :env    => @announce_env
      )

      @announcer
    end

    module_function :announcer

    # TODO: move some more methods under here!

    private

    def last_exit_status
      process_monitor.last_exit_status
    end

    def stop_process(process)
      process_monitor.stop_process(process)
    end

    def terminate_process(process)
      process_monitor.terminate_process(process)
    end
  end
end
