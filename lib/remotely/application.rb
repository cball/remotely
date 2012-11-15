module Remotely
  class Application
    attr_reader :name

    def initialize(name, &block)
      @name = name
      instance_eval(&block)
    end

    # Set or get the applications base url.
    #
    # @param [String] url Base url to the appplication
    #
    def url(url=nil)
      return @url unless url
      @url = URI.parse(set_scheme(url)).to_s
    end

    # Set or get BasicAuth credentials.
    #
    # @param [String] user BasicAuth user
    # @param [String] password BasicAuth password
    #
    # user=nil, password=nil
    def basic_auth(*args_or_proc)
      return @basic_auth unless args_or_proc
      @basic_auth = args_or_proc
    end

    # Connection to the application (with BasicAuth if it was set).
    #
    def connection
      return unless @url

      @connection ||= Faraday::Connection.new(@url) do |b|
        b.request :url_encoded
        b.adapter :net_http
      end

      proc_or_username = @basic_auth.first
      if proc_or_username.respond_to?(:call)
        username_password = proc_or_username.call
        @connection.basic_auth(*username_password)
      elsif proc_or_username
        @connection.basic_auth(*basic_auth)
      end

      @connection
    end

    # Strip root json from incoming responses.
    #
    # @param [String] strip_root_json Root json to strip
    #
    def strip_root_json(strip_root_json=nil)
      return @strip_root_json unless strip_root_json
      @strip_root_json = strip_root_json
    end

    # Response to check every request to see if there is an remote authentication error
    #
    # @param [Hash, String] auth_exception_response reponse to check against
    def auth_exception_response(auth_exception_response=nil)
      return @auth_exception_response unless auth_exception_response
      @auth_exception_response = auth_exception_response
    end

    # The exception to throw if auth_exception_response is found
    #
    # @param [Exception, String] auth_exception exception or string to raise if auth_exception_response is found.
    def auth_exception(auth_exception)
      return @auth_exception unless auth_exception
      @auth_exception_response = 'Auth Exception'
    end

  private

    def set_scheme(url)
      url =~ /^http/ ? url : "http://#{url}"
    end
  end
end
