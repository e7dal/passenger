# encoding: utf-8
#  Phusion Passenger - https://www.phusionpassenger.com/
#  Copyright (c) 2013 Phusion
#
#  "Phusion Passenger" is a trademark of Hongli Lai & Ninh Bui.
#
#  See LICENSE file for license information.

PhusionPassenger.require_passenger_lib 'platform_info'
require 'fileutils'
require 'shellwords'

module PhusionPassenger
module Utils

module Download
	extend self    # Make methods available as class methods.

	def self.included(klass)
		# When included into another class, make sure that Utils
		# methods are made private.
		public_instance_methods(false).each do |method_name|
			klass.send(:private, method_name)
		end
	end

	# Downloads a file from the given URL and saves it to the given filename.
	# Returns whether the download succeeded.
	# 
	# Options:
	#
	#   show_progress: whether to show download progress. Default: false.
	#   logger: the logger to use. If not given, this function will log to STDERR.
	#   cacert: a CA certificate file to use for verifying SSL websites.
	#           The default is to use the download tool's down CA database.
	#   use_cache: Whether to copy the file from the download cache, if available.
	#              Default: false.
	def download(url, output, options = {})
		logger = options[:logger] || Logger.new(STDERR)

		if options[:use_cache] && cache_dir = PhusionPassenger.download_cache_dir
			basename = basename_from_url(url)
			if File.exist?("#{cache_dir}/#{basename}")
				logger.info "Copying #{basename} from #{cache_dir}..."
				FileUtils.cp("#{cache_dir}/#{basename}", output)
				return true
			end
		end

		if PlatformInfo.find_command("curl")
			return download_with_curl(logger, url, output, options)
		elsif PlatformInfo.find_command("wget")
			return download_with_wget(logger, url, output, options)
		else
			logger.error "Could not download #{url}: no download tool found (curl or wget required)"
			return false
		end
	end

private
	def basename_from_url(url)
		return url.sub(/.*\//, '')
	end

	def download_with_curl(logger, url, output, options)
		command = ["curl", "-f", "-L", "-o", output]
		if options[:show_progress]
			command << "-#"
		else
			command << "-s"
			command << "-S"
		end
		if options[:cacert]
			command << "--cacert"
			command << options[:cacert]
		end
		command << url
		command_str = Shellwords.join(command)
		logger.info("Invoking: #{command_str}")

		if options[:show_progress]
			# If curl errors out we don't want it to display 'curl: ' prefixes,
			# so we parse its output.
			begin
				io = IO.popen("#{command_str} 2>&1", "r")
			rescue SystemCallError => e
				logger.error("Could not invoke curl: #{e}")
				return false
			end
			begin
				non_empty_line_encountered = false
				while !io.eof?
					# We split on "\r" because progress bar lines do not contain "\n".
					data = io.gets("\r")
					data = remove_curl_output_prefix(data)

					# If an error occurs then the first few lines may be empty.
					# Skip those.
					if !non_empty_line_encountered && data =~ /\A\n+/
						data.gsub!(/\A\n+/, '')
					end

					non_empty_line_encountered = true
					STDERR.write(data)
					STDERR.flush
				end
			ensure
				io.close
			end
			result = $?.exitstatus == 0
		else
			begin
				output = `#{command_str} 2>&1`
			rescue SystemCallError => e
				logger.error("Could not invoke curl: #{e}")
				return false
			end
			result = $?.exitstatus == 0
			if !result
				output = remove_curl_output_prefix(output)
				output.chomp!
				logger.error("Could not download #{url}: #{output}")
			end
		end

		return result
	end

	def remove_curl_output_prefix(line)
		return line.gsub(/^curl: (\([0-9]+\) )?/, '')
	end

	def download_with_wget(logger, url, output, options)
		command = ["wget", "--tries=3", "-O", output]
		if !options[:show_progress]
			command << "-nv"
		end
		if options[:cacert]
			command << "--ca-certificate=#{options[:cacert]}"
		end
		command << url
		command_str = Shellwords.join(command)
		logger.info("Invoking: #{command_str}")

		if options[:show_progress]
			begin
				result = system(*command)
			rescue SystemCallError => e
				logger.error("Could not invoke wget: #{e}")
				return false
			end
			if !result
				logger.error("Could not download #{url}: #{output}")
			end
		else
			begin
				output = `#{command_str} 2>&1`
			rescue SystemCallError => e
				logger.error("Could not invoke wget: #{e}")
				return false
			end
			result = $?.exitstatus == 0
			if !result
				# Error output may begin with "<URL>:\n" which is redundant.
				output.gsub!(/\A#{Regexp.escape url}:\n/, '')
				output.chomp!
				logger.error("Could not download #{url}: #{output}")
			end
		end

		return result
	end
end

end # module Utils
end # module PhusionPassenger
