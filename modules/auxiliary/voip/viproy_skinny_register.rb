##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Skinny
  include Msf::Exploit::Remote::Tcp

  def initialize
    super(
      'Name'				=> 'Viproy Cisco Skinny Register Analyser',
      'Description' => 'This module helps to develop register tests for Skinny',
      'Author'      => 'Fatih Ozavci <viproy.com/fozavci>',
      'License'     =>  MSF_LICENSE,
    )
    register_options(
      [
        OptString.new('MAC',   [ false, "MAC Address"]),
        OptString.new('MACFILE',   [ false, "Input file contains MAC Addresses"]),
        Opt::RPORT(2000)
      ], self.class)
  end

  def setup
    unless datastore['MAC'] || datastore['MACFILE']
      fail_with(ArgumentError, 'MAC or MACFILE must be defined')
    end
  end

  def run
    # options from the user
    capabilities = datastore['CAPABILITIES']
    platform = datastore['PLATFORM']
    software = datastore['SOFTWARE']
    if datastore['MACFILE']
      macs = macfileimport(datastore['MACFILE'])
    else
      macs = []
    end
    macs << mac if datastore['MAC']
    client = datastore['CISCOCLIENT'].downcase
    if datastore['DEVICE_IP']
      device_ip = datastore['DEVICE_IP']
    else
      device_ip = Rex::Socket.source_address(datastore['RHOST'])
    end

    # Skinny Registration Test
    macs.each do |mac|
      device = "#{datastore['PROTO_TYPE']}#{mac.gsub(":", "")}"
      begin
        connect
        register(sock, device, device_ip, client, mac)
        disconnect
      rescue Rex::ConnectionError => e
        print_error("Connection failed: #{e.class}: #{e}")
        return nil
      end
    end
  end
end
