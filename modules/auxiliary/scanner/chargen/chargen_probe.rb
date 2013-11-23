##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##


require 'msf/core'

class Metasploit3 < Msf::Auxiliary
  Rank = ManualRanking

  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::Report
  include Msf::Exploit::Remote::Udp

  def initialize
    super(
      'Name'        => 'Identifies Open Chargen Service Checking The Answer.',
      'Description' => %q{
        Chargen is a debugging and measurement tool and a character
        generator service. A character generator service simply sends
        data without regard to the input.
        Chargen is susceptible to spoofing the source of transmissions
        as well as use in a reflection attack vector. The misuse of the
        testing features of the Chargen service may allow attackers to
        craft malicious network payloads and reflect them by spoofing
        the transmission source to effectively direct it to a target.
        This can result in traffic loops and service degradation with
        large amounts of network traffic.
      },
      'Author'      => 'Matteo Cantoni <goony[at]nothink.org>',
      'License'     => MSF_LICENSE,
      'References'  =>
        [
          [ 'CVE', 'CVE-1999-0103' ],
          [ 'URL', 'https://www.cert.be/pro/docs/chargensnmp-ddos-attacks-rise' ],
          [ 'URL', 'http://tools.ietf.org/html/rfc864' ],
        ],
      'DisclosureDate' => 'Feb 08 1996')

      register_options([
        Opt::RPORT(19),
        OptInt.new('TIMEOUT', [true, 'Timeout for the Chargen probe', 5]),
      ])

      register_advanced_options([
        OptBool.new('DEBUG', [false, 'Show chargen server answer', false]),
      ], self.class)

    deregister_options('PASSWORD','RHOST','USERNAME')
  end

  def to
    return 5 if datastore['TIMEOUT'].to_i.zero?
    datastore['TIMEOUT'].to_i
  end

  def run_host(rhost)
    begin
      ::Timeout.timeout(to) do
        connect_udp
        pkt = Rex::Text.rand_text_alpha_lower(1)
        req = udp_sock.write(pkt)

        while (res = udp_sock.recvfrom(65535,0.1) and res[1])

          if (datastore['DEBUG'])
            print_status("DEBUG: #{res.to_s}")
          end

          res = res.to_s.strip.upcase
          if (res.match(/ABCDEFGHIJKLMNOPQRSTUVWXYZ/i) or res(/0123456789/))
            print_good("#{rhost}:#{rport} answers with #{res.length} bytes (headers + UDP payload)")
            report_service(:host => rhost, :port => rport, :name => "chargen", :info => res.length)
          end
        end

        disconnect_udp
        end
      rescue ::Rex::ConnectionError
      rescue Timeout::Error
        print_error("#{rhost}:#{rport} server timed out after #{to} seconds. Skipping.")
      rescue ::Exception => e
        print_error("#{e} #{e.backtrace}")
    end
  end
end
