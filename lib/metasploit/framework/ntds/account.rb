module Metasploit
  module Framework
    module NTDS
      # This class represents an NTDS account structure as sent back by Meterpreter's
      # priv extension.
      class Account

        #@return [String] The AD Account Description
        attr_accessor :description
        #@return [Boolean] If the AD account is disabled
        attr_accessor :disabled
        #@return [Boolean] If the AD account password is expired
        attr_accessor :expired
        #@return [String] Human Readable Date for the account's password expiration
        attr_accessor :expiry_date
        #@return [String] The LM Hash of the current password
        attr_accessor :lm_hash
        #@return [Array<String>] The LM hashes for previous passwords, up to 24
        attr_accessor :lm_history
        #@return [Fixnum] The count of historical LM hashes
        attr_accessor :lm_history_count
        #@return [Boolean] If the AD account is locked
        attr_accessor :locked
        #@return [Fixnum] The number of times this account has logged in
        attr_accessor :logon_count
        #@return [String] Human Readable Date for the last time the account logged in
        attr_accessor :logon_date
        #@return [String] Human Readable Time for the last time the account logged in
        attr_accessor :logon_time
        #@return [String] The samAccountName of the account
        attr_accessor :name
        #@return [Boolean] If the AD account password does not expire
        attr_accessor :no_expire
        #@return [Boolean] If the AD account does not require a password
        attr_accessor :no_pass
        #@return [String] The NT Hash of the current password
        attr_accessor :nt_hash
        #@return [Array<String>] The NT hashes for previous passwords, up to 24
        attr_accessor :nt_history
        #@return [Fixnum] The count of historical NT hashes
        attr_accessor :nt_history_count
        #@return [String] Human Readable Date for the last password change
        attr_accessor :pass_date
        #@return [String] Human Readable Time for the last password change
        attr_accessor :pass_time
        #@return [Fixnum] The Relative ID of the account
        attr_accessor :rid
        #@return [String] Byte String for the Account's SID
        attr_accessor :sid

        # @param raw_data [String] the raw 3948 byte string from the wire
        # @raise [ArgumentErrror] if a 3948 byte string is not supplied
        def initialize(raw_data)
          raise ArgumentError, "No Data Supplied" unless raw_data.present?
          raise ArgumentError, "Invalid Data" unless raw_data.length == 3948
          data = raw_data.dup
          @name = get_string(data,40)
          @description = get_string(data,2048)
          @rid = get_int(data)
          @disabled = get_boolean(data)
          @locked = get_boolean(data)
          @no_pass = get_boolean(data)
          @no_expire = get_boolean(data)
          @expired = get_boolean(data)
          @logon_count = get_int(data)
          @nt_history_count = get_int(data)
          @lm_history_count = get_int(data)
          @expiry_date = get_string(data,30)
          @logon_date =  get_string(data,30)
          @logon_time = get_string(data,30)
          @pass_date = get_string(data,30)
          @pass_time = get_string(data,30)
          @lm_hash = get_string(data,33)
          @nt_hash = get_string(data,33)
          @lm_history = get_hash_history(data)
          @nt_history = get_hash_history(data)
          @sid = data
        end

        # @return [String] String representation of the account data
        def to_s
          <<-EOS.strip_heredoc
          #{@name} (#{@description})
          #{ntlm_hash}
          Password Expires: #{@expiry_date}
          Last Password Change: #{@pass_time} #{@pass_date}
          Last Logon: #{@logon_time} #{@logon_date}
          Logon Count: #{@logon_count}
          #{uac_string}
          Hash History:
          #{hash_history}
          EOS
        end

        # @return [String] the NTLM hash string for the current password
        def ntlm_hash
          "#{@name}:#{@rid}:#{@lm_hash}:#{@nt_hash}"
        end

        # @return [String] Each historical NTLM Hash on a new line
        def hash_history
          history_string = ''
          @lm_history.each_with_index do | lm_hash, index|
            history_string << "#{@name}:#{@rid}:#{lm_hash}:#{@nt_history[index]}\n"
          end
          history_string
        end

        private

        def get_boolean(data)
          get_int(data) == 1
        end

        def get_hash_history(data)
          raw_history = data.slice!(0,792)
          split_history = raw_history.scan(/.{1,33}/)
          split_history.map!{ |hash| hash.gsub(/\x00/,'')}
          split_history.reject!{ |hash| hash.blank? }
        end

        def get_int(data)
          data.slice!(0,4).unpack('L').first
        end

        def get_string(data,length)
          data.slice!(0,length).gsub(/\x00/,'')
        end

        def uac_string
          status_string = ''
          if @disabled
            status_string << " - Account Disabled\n"
          end
          if @expired
            status_string << " - Password Expired\n"
          end
          if @locked
            status_string << " - Account Locked Out\n"
          end
          if @no_expire
            status_string << " - Password Never Expires\n"
          end
          if @no_pass
            status_string << " - No Password Required\n"
          end
          status_string
        end
      end
    end
  end
end
