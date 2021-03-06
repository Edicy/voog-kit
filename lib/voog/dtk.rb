require 'voog/dtk/version'
require 'parseconfig'
require 'pp'

module Voog
  module Dtk

    CONFIG_FILENAME = '.voog'

    class << self
      def config_exists?(filename=CONFIG_FILENAME)
        filename && !filename.empty? && File.exist?(filename)
      end

      def global_config_exists?(filename=CONFIG_FILENAME)
        filename && !filename.empty? && File.exist?([ENV['HOME'], filename].join('/'))
      end

      def read_config(block = nil, file = CONFIG_FILENAME)
        config = {
          :host => nil,
          :api_token => nil,
          :overwrite => nil,
          :protocol => 'http'
        }
        local_config = config_exists?(file) ? ParseConfig.new(File.expand_path(file)).params : {}
        global_config = global_config_exists?(file) ? ParseConfig.new(File.expand_path([ENV['HOME'], file].join('/'))).params : {}

        options = local_config.merge(global_config)

        unless options.empty?
          @block = case block
          when nil
            options.keys.first
          when :all
            options.keys
          else
            if options.key?(block)
              block
            else
              fail "Site '#{block}' not found in the configuration file!".red
            end
          end

          if @block.is_a?(Array) && @block.size
            config = []
            @block.each do |site|
              config << {
                name: site,
                host: options[site].fetch('host'),
                api_token: options[site].fetch('api_token'),
                overwrite: options[site].fetch('overwrite'),
                protocol: options[site].fetch('protocol')
              }
            end
          else
            config[:host] = options[@block].fetch("host")
            config[:api_token] = options[@block].fetch("api_token")
            config[:overwrite] = options[@block].fetch("overwrite", false) == 'true' ? true : false
            config[:protocol] = options[@block].fetch("protocol", 'http') == "https" ? "https" : "http"
          end
        end
        config
      end

      def write_config(opts)
        block = opts.fetch(:block, '')
        host = opts.fetch(:host, '')
        api_token = opts.fetch(:api_token, '')
        silent = opts.fetch(:silent, false)
        overwrite = opts.fetch(:overwrite, '')
        protocol = opts.fetch(:protocol, '')

        @file = if config_exists?
          CONFIG_FILENAME
        elsif global_config_exists?
          [ENV['HOME'], CONFIG_FILENAME].join('/')
        else
          File.new(CONFIG_FILENAME, 'w+')
          CONFIG_FILENAME
        end

        options = ParseConfig.new(File.expand_path(@file))

        if options.params.key?(block)
          puts "Writing new configuration options to existing config block.".white unless silent
          options.params[block]['host'] = host unless host.empty?
          options.params[block]['api_token'] = api_token unless api_token.empty?
          options.params[block]['overwrite'] = overwrite if (overwrite == true || overwrite == false)
          options.params[block]['protocol'] = (protocol == 'https' ? 'https' : 'http') unless protocol.empty?
        else
          puts "Writing configuration options to new config block.".white unless silent
          options.params[block] = {
            'host' => host,
            'api_token' => api_token,
            'overwrite' => (overwrite == true ? true : false),
            'protocol' => (protocol == 'https' ? 'https' : 'http')
          }
        end

        File.open(@file, 'w+') do |file|
          file.truncate(0)
          file << "\n"
          options.params.each do |param|
            file << "[#{param[0]}]\n"
            param[1].keys.each do |key|
              file << "  #{key}=#{param[1][key]}\n"
            end
            file << "\n"
          end
        end
      end

      def is_api_error?(exception)
        [
          Faraday::ClientError,
          Faraday::ConnectionFailed,
          Faraday::ParsingError,
          Faraday::TimeoutError,
          Faraday::ResourceNotFound
        ].include? exception.class
      end

      def print_debug_info(exception)
        puts
        puts "Exception: #{exception.class}"
        if is_api_error?(exception) && exception.respond_to?(:response) && exception.response
          pp exception.response
        end
        puts exception.backtrace
      end

      def handle_exception(exception, debug, notifier=nil)
        error_msg = if is_api_error?(exception)
          if exception.respond_to?(:response) && exception.response
            if exception.response.fetch(:headers, {}).fetch(:content_type, '') =~ /application\/json/
              body = JSON.parse(exception.response.fetch(:body))
              "#{body.fetch('message', '')} #{("Errors: " + body.fetch('errors', '').inspect) if body.fetch('errors', nil)}".red
            else
              exception.response.fetch(:body)
            end + "(error code #{exception.response[:status]})".red
          else
            "#{exception}"
          end
        else
          "#{exception}"
        end

        if notifier
          notifier.newline
          notifier.error error_msg
          notifier.newline
        else
          puts error_msg
        end
        print_debug_info(exception) if debug
      rescue => e
        handle_exception e, debug, notifier
      end
    end
  end
end
