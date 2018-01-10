module Msf::DBManager::Host
  # TODO: doesn't appear to have any callers. How is this used?
  # Deletes a host and associated data matching this address/comm
  def del_host(wspace, address, comm='')
  ::ActiveRecord::Base.connection_pool.with_connection {
    address, scope = address.split('%', 2)
    host = wspace.hosts.find_by_address_and_comm(address, comm)
    host.destroy if host
  }
  end

  def delete_host(opts)
    wspace = opts[:workspace] || opts[:wspace] || workspace
    if wspace.is_a? String
      wspace = find_workspace(wspace)
    end

    ::ActiveRecord::Base.connection_pool.with_connection {
      hosts = []
      if opts[:address] || opts[:host]
        opt_addr = opts[:address] || opts[:host]
        host = wspace.hosts.find_by_address(opt_addr)
        return { error: { message: "Unable to find host by specified address" } } if host.nil? || host.class != ::Mdm::Host
        hosts << host
      elsif opts[:addresses]
        return { error: { message: "Unable to find host by specified addresses" } } if opts[:addresses].class != Array
        hosts = wspace.hosts.where(address: opts[:addresses])
        return { error: { message: "Unable to find hosts for specified addresses" } } if hosts.nil?
      end

      deleted = []
      hosts.each do |host|
        begin
          host.destroy
          deleted << host.address.to_s
        rescue # refs suck
          elog("Forcibly deleting #{host.address}")
          host.delete
          deleted << host.address.to_s
        end
      end

      return { deleted: deleted }
    }
  end

  #
  # Iterates over the hosts table calling the supplied block with the host
  # instance of each entry.
  #
  def each_host(wspace=workspace, &block)
  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace.hosts.each do |host|
      block.call(host)
    end
  }
  end

  # Exactly like report_host but waits for the database to create a host and returns it.
  def find_or_create_host(opts)
    host = get_host(opts)
    return host unless host.nil?

    report_host(opts)
  end

  def add_host_tag(opts)
    workspace = opts[:workspace]
    if workspace.kind_of? String
      workspace = find_workspace(workspace)
    end

    ip = opts[:ip]
    tag_name = opts[:tag_name]

    host = framework.db.get_host(:workspace => workspace, :address => ip)
    if host
      possible_tags = Mdm::Tag.joins(:hosts).where("hosts.workspace_id = ? and hosts.address = ? and tags.name = ?", workspace.id, ip, tag_name).order("tags.id DESC").limit(1)
      tag = (possible_tags.blank? ? Mdm::Tag.new : possible_tags.first)
      tag.name = tag_name
      tag.hosts = [host]
      tag.save! if tag.changed?
    end
  end

  def find_hosts_with_tag(opts)
    workspace_id = opts[:workspace_id]
    host_address = opts[:host_address]
    tag_name = opts[:tag_name]
    Mdm::Tag.joins(:hosts).where("hosts.workspace_id = ? and hosts.address = ? and tags.name = ?", workspace_id, host_address, tag_name).references(:hosts).order("tags.id DESC")
  end

  def find_host_tags(opts)
    workspace_id = opts[:workspace_id]
    host_address = opts[:host_address]
    Mdm::Tag.joins(:hosts).where("hosts.workspace_id = ? and hosts.address = ?", workspace.id, host_address).order("tags.id DESC")
  end

  def delete_host_tag(opts)
    workspace = opts[:workspace]
    if workspace.kind_of? String
      workspace = find_workspace(workspace)
    end

    ip = opts[:rws]
    tag_name = opts[:tag_name]

    tag_ids = []
    if ip.nil?
      found_tags = Mdm::Tag.joins(:hosts).where("hosts.workspace_id = ? and tags.name = ?", workspace.id, tag_name)
      found_tags.each do |t|
        tag_ids << t.id
      end
    else
      found_tags = Mdm::Tag.joins(:hosts).where("hosts.workspace_id = ? and hosts.address = ? and tags.name = ?", workspace.id, ip, tag_name)
      found_tags.each do |t|
        tag_ids << t.id
      end
    end

    tag_ids.each do |id|
      tag = Mdm::Tag.find_by_id(id)
      tag.hosts.delete
      tag.destroy
    end
  end

  #
  # Find a host.  Performs no database writes.
  #
  def get_host(opts)
    if opts.kind_of? ::Mdm::Host
      return opts
    elsif opts.kind_of? String
      raise RuntimeError, "This invokation of get_host is no longer supported: #{caller}"
    else
      address = opts[:addr] || opts[:address] || opts[:host] || return
      return address if address.kind_of? ::Mdm::Host
    end
  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    address = Msf::Util::Host.normalize_host(address)
    return wspace.hosts.find_by_address(address)
  }
  end

  # Look for an address across all comms
  def has_host?(wspace,addr)
  ::ActiveRecord::Base.connection_pool.with_connection {
    address, scope = addr.split('%', 2)
    wspace.hosts.find_by_address(addr)
  }
  end

  # Returns a list of all hosts in the database
  def hosts(opts)
    wspace = opts[:workspace] || opts[:wspace] || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

  ::ActiveRecord::Base.connection_pool.with_connection {
    conditions = {}
    conditions[:state] = [Msf::HostState::Alive, Msf::HostState::Unknown] if opts[:non_dead]
    conditions[:address] = opts[:addresses] if opts[:addresses]
    wspace.hosts.where(conditions).order(:address)
  }
  end

  #
  # Report a host's attributes such as operating system and service pack
  #
  # The opts parameter MUST contain
  # +:host+::         -- the host's ip address
  #
  # The opts parameter can contain:
  # +:state+::        -- one of the Msf::HostState constants
  # +:os_name+::      -- something like "Windows", "Linux", or "Mac OS X"
  # +:os_flavor+::    -- something like "Enterprise", "Pro", or "Home"
  # +:os_sp+::        -- something like "SP2"
  # +:os_lang+::      -- something like "English", "French", or "en-US"
  # +:arch+::         -- one of the ARCH_* constants
  # +:mac+::          -- the host's MAC address
  # +:scope+::        -- interface identifier for link-local IPv6
  # +:virtual_host+:: -- the name of the virtualization software, eg "VMWare", "QEMU", "Xen", "Docker", etc.
  #
  def report_host(opts)

    return if !active
    addr = opts.delete(:host) || return

    # Sometimes a host setup through a pivot will see the address as "Remote Pipe"
    if addr.eql? "Remote Pipe"
      return
    end

  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    ret = { }

    if !addr.kind_of? ::Mdm::Host
      addr = Msf::Util::Host.normalize_host(addr)

      unless ipv46_validator(addr)
        raise ::ArgumentError, "Invalid IP address in report_host(): #{addr}"
      end

      if opts[:comm] and opts[:comm].length > 0
        host = wspace.hosts.where(address: addr, comm: opts[:comm]).first_or_initialize
      else
        host = wspace.hosts.where(address: addr).first_or_initialize
      end
    else
      host = addr
    end

    # Truncate the info field at the maximum field length
    if opts[:info]
      opts[:info] = opts[:info][0,65535]
    end

    # Truncate the name field at the maximum field length
    if opts[:name]
      opts[:name] = opts[:name][0,255]
    end

    if opts[:os_name]
      os_name, os_flavor = split_windows_os_name(opts[:os_name])
      opts[:os_name] = os_name if os_name.present?
      if opts[:os_flavor].present?
        opts[:os_flavor] = os_flavor + opts[:os_flavor]
      else
        opts[:os_flavor] = os_flavor
      end
    end

    opts.each do |k,v|
      if (host.attribute_names.include?(k.to_s))
        unless host.attribute_locked?(k.to_s)
          host[k] = v.to_s.gsub(/[\x00-\x1f]/n, '')
        end
      elsif !v.blank?
        dlog("Unknown attribute for ::Mdm::Host: #{k}")
      end
    end
    host.info = host.info[0,::Mdm::Host.columns_hash["info"].limit] if host.info

    # Set default fields if needed
    host.state       = Msf::HostState::Alive if !host.state
    host.comm        = ''        if !host.comm
    host.workspace   = wspace    if !host.workspace

    if host.changed?
      msf_import_timestamps(opts,host)
      host.save!
    end

    if opts[:task]
      Mdm::TaskHost.create(
          :task => opts[:task],
          :host => host
      )
    end

    host
  }
  end

  def split_windows_os_name(os_name)
    return [] if os_name.nil?
    flavor_match = os_name.match(/Windows\s+(.*)/)
    return [] if flavor_match.nil?
    ["Windows", flavor_match.captures.first]
  end

  #
  # Update a host's attributes via semi-standardized sysinfo hash (Meterpreter)
  #
  # The opts parameter MUST contain the following entries
  # +:host+::           -- the host's ip address
  # +:info+::           -- the information hash
  # * 'Computer'        -- the host name
  # * 'OS'              -- the operating system string
  # * 'Architecture'    -- the hardware architecture
  # * 'System Language' -- the system language
  #
  # The opts parameter can contain:
  # +:workspace+::      -- the workspace for this host
  #
  def update_host_via_sysinfo(opts)

    return if !active
    addr = opts.delete(:host) || return
    info = opts.delete(:info) || return

    # Sometimes a host setup through a pivot will see the address as "Remote Pipe"
    if addr.eql? "Remote Pipe"
      return
    end

  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    if !addr.kind_of? ::Mdm::Host
      addr = Msf::Util::Host.normalize_host(addr)
      addr, scope = addr.split('%', 2)
      opts[:scope] = scope if scope

      unless ipv46_validator(addr)
        raise ::ArgumentError, "Invalid IP address in report_host(): #{addr}"
      end

      if opts[:comm] and opts[:comm].length > 0
        host = wspace.hosts.where(address: addr, comm: opts[:comm]).first_or_initialize
      else
        host = wspace.hosts.where(address: addr).first_or_initialize
      end
    else
      host = addr
    end

    res = {}

    if info['Computer']
      res[:name] = info['Computer']
    end

    if info['Architecture']
      res[:arch] = info['Architecture'].split(/\s+/).first
    end

    if info['OS'] =~ /^Windows\s*([^\(]+)\(([^\)]+)\)/i
      res[:os_name]   = "Windows"
      res[:os_flavor] = $1.strip
      build = $2.strip

      if build =~ /Service Pack (\d+)/
        res[:os_sp] = "SP" + $1
      end
    end

    if info["System Language"]
      case info["System Language"]
        when /^en_/
          res[:os_lang] = "English"
      end
    end


    # Truncate the info field at the maximum field length
    if res[:info]
      res[:info] = res[:info][0,65535]
    end

    # Truncate the name field at the maximum field length
    if res[:name]
      res[:name] = res[:name][0,255]
    end

    res.each do |k,v|
      if (host.attribute_names.include?(k.to_s))
        unless host.attribute_locked?(k.to_s)
          host[k] = v.to_s.gsub(/[\x00-\x1f]/n, '')
        end
      elsif !v.blank?
        dlog("Unknown attribute for Host: #{k}")
      end
    end

    # Set default fields if needed
    host.state       = Msf::HostState::Alive if !host.state
    host.comm        = ''        if !host.comm
    host.workspace   = wspace    if !host.workspace

    if host.changed?
      host.save!
    end

    host
  }
  end
end
