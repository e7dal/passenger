#!/usr/bin/env ruby
# encoding: binary
module PhusionPassenger
module App
	def self.options
		return @@options
	end
	
	def self.app
		return @@app
	end

	def self.format_exception(e)
		result = "#{e} (#{e.class})"
		if !e.backtrace.empty?
			result << "\n  " << e.backtrace.join("\n  ")
		end
		return result
	end

	def self.exit_code_for_exception(e)
		if e.is_a?(SystemExit)
			return e.status
		else
			return 1
		end
	end
	
	def self.handshake_and_read_startup_request
		STDOUT.sync = true
		STDERR.sync = true
		puts "!> I have control 1.0"
		abort "Invalid initialization header" if STDIN.readline != "You have control 1.0\n"
		
		@@options = {}
		while (line = STDIN.readline) != "\n"
			name, value = line.strip.split(/: */, 2)
			@@options[name] = value
		end
	end
	
	def self.init_passenger
		$LOAD_PATH.unshift(options["ruby_libdir"])
		require 'phusion_passenger'
		PhusionPassenger.locate_directories(options["passenger_root"])
		require 'phusion_passenger/native_support'
		require 'phusion_passenger/ruby_core_enhancements'
		require 'phusion_passenger/utils/tmpdir'
		require 'phusion_passenger/loader_shared_helpers'
		require 'phusion_passenger/request_handler'
		require 'phusion_passenger/rack/thread_handler_extension'
		LoaderSharedHelpers.init
		@@options = LoaderSharedHelpers.sanitize_spawn_options(@@options)
		Utils.passenger_tmpdir = options["generation_dir"]
		NativeSupport.disable_stdio_buffering
		RequestHandler::ThreadHandler.send(:include, Rack::ThreadHandlerExtension)
	rescue Exception => e
		LoaderSharedHelpers.about_to_abort(e) if defined?(LoaderSharedHelpers)
		puts "!> Error"
		puts "!> "
		puts format_exception(e)
		exit exit_code_for_exception(e)
	end
	
	def self.load_app
		LoaderSharedHelpers.before_loading_app_code_step1('config.ru', options)
		LoaderSharedHelpers.run_load_path_setup_code(options)
		LoaderSharedHelpers.before_loading_app_code_step2(options)
		
		require 'rubygems'
		require 'rack'
		rackup_file = ENV["RACKUP_FILE"] || options["rackup_file"] || "config.ru"
		rackup_code = ::File.open(rackup_file, 'rb') do |f|
			f.read
		end
		@@app = eval("Rack::Builder.new {( #{rackup_code}\n )}.to_app",
			TOPLEVEL_BINDING, rackup_file)
		
		LoaderSharedHelpers.after_loading_app_code(options)
	rescue Exception => e
		LoaderSharedHelpers.about_to_abort(e)
		puts "!> Error"
		puts "!> "
		puts format_exception(e)
		exit exit_code_for_exception(e)
	end
	
	
	################## Main code ##################
	
	
	handshake_and_read_startup_request
	init_passenger
	load_app
	LoaderSharedHelpers.before_handling_requests(false, options)
	handler = RequestHandler.new(STDIN, options.merge("app" => app))
	puts "!> Ready"
	LoaderSharedHelpers.advertise_sockets(STDOUT, handler)
	puts "!> "
	handler.main_loop
	LoaderSharedHelpers.after_handling_requests
	
end # module App
end # module PhusionPassenger
