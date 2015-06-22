# -*- coding: binary -*-

require 'openssl'
require 'socket'
require 'msf/core'
require 'msf/core/exploit/mssql_commands'

class TDSSSLProxy

  @s1 = 0 # write ssl to this sock
  @s2 = 0 # demux the unencrypted stream on this sock
  @tdssock = 0
  @sslsock = 0
  @t1 = 0

  TYPE_TDS7_LOGIN = 16
  TYPE_PRE_LOGIN_MESSAGE = 18
  STATUS_END_OF_MESSAGE = 0x01

  def initialize(sock)
    @tdssock = sock
    @s1,@s2 = Socket.pair(:UNIX,:STREAM,0)
  end

  def cleanup()
    Thread.kill(@t1)
  end

  def setup_ssl
    @t1 = Thread.start { ssl_setup_thread(@s2)  }
    ssl_context = OpenSSL::SSL::SSLContext.new(:TLSv1)
    @ssl_socket = OpenSSL::SSL::SSLSocket.new(@s1, ssl_context)
    @ssl_socket.connect
  end

  def send_recv(pkt)
    @ssl_socket.write(pkt)
    done = false
    resp = ""

    while(not done)
      head = @ssl_socket.sysread(8)
      if !(head and head.length == 8)
        return false
      end

      # Is this the last buffer?
      if(head[1,1] == "\x01" or not check_status )
        done = true
      end

      # Grab this block's length
      rlen = head[2,2].unpack('n')[0] - 8

      while(rlen > 0)
        buff = @ssl_socket.sysread(rlen)
        return if not buff
        resp << buff
        rlen -= buff.length
      end

    end
    resp
  end

  def ssl_setup_thread(s_two)

    while true do
      res = select([@tdssock,s_two],nil,nil)
      for r in res[0]

        # response from SQL Server for client
        if r == @tdssock
          resp = @tdssock.recv(4096)
          if @ssl_socket.state[0,5] == "SSLOK"
            s_two.send(resp,0)
          else
            s_two.send(resp[8..-1],0)
          end
        end

        # request from client for SQL Server
        if r == s_two
          resp = s_two.recv(4096)
          # SSL negotiation completed - just send it on
          if @ssl_socket.state[0,5] == "SSLOK"
            @tdssock.send(resp,0)
          # Still doing SSL
          else
            tds_pkt_len = 8 + resp.length
            pkt_hdr = ''
            pkt  = ''
            pkt_hdr << [TYPE_PRE_LOGIN_MESSAGE,STATUS_END_OF_MESSAGE,tds_pkt_len,0x0000,0x00,0x00].pack('CCnnCC')
            pkt = pkt_hdr << resp
            @tdssock.send(pkt,0)
          end
        end
      end
    end
  end
end

